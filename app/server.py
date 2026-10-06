import json
import logging
import os
import re
import secrets
import signal
import subprocess
import threading
import time
from pathlib import Path

from flask import Flask, jsonify, request

app = Flask(__name__)
app.logger.setLevel(logging.INFO)

APP_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$")
REMOTE_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
REMOTE_URL_PATTERN = re.compile(r"^https://[A-Za-z0-9.-]+(?::[0-9]{1,5})?(?:/[^\s]*)?$")
MAX_TASK_OUTPUT = 16 * 1024

processes = {}
process_lock = threading.Lock()
tasks = {}
tasks_lock = threading.Lock()


def command_environment():
    environment = os.environ.copy()
    environment["HOME"] = os.environ.get("WEBFLATPAK_HOME", "/var/lib/webflatpak")
    environment["XDG_RUNTIME_DIR"] = "/run/user/1000"
    environment["DISPLAY"] = ":99"
    environment["LIBGL_ALWAYS_SOFTWARE"] = "1"
    return environment


def valid_app_id(value):
    return isinstance(value, str) and APP_ID_PATTERN.fullmatch(value) is not None


def valid_remote(value):
    return isinstance(value, str) and REMOTE_PATTERN.fullmatch(value) is not None


def flatpak(arguments, check=True, user=True):
    command = ["flatpak"]
    if user:
        command.append("--user")
    command.extend(arguments)
    return subprocess.run(
        command,
        env=command_environment(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=check,
    )


def task_snapshot():
    with tasks_lock:
        return sorted(tasks.values(), key=lambda task: task["created_at"], reverse=True)


def start_task(name, arguments):
    task_id = secrets.token_urlsafe(12)
    task = {
        "id": task_id,
        "name": name,
        "status": "running",
        "output": "",
        "created_at": int(time.time()),
        "completed_at": None,
    }
    with tasks_lock:
        tasks[task_id] = task

    def execute():
        try:
            result = flatpak(arguments)
            output = result.stdout
            status = "completed"
        except subprocess.CalledProcessError as error:
            output = error.stdout or str(error)
            status = "failed"
        with tasks_lock:
            task["status"] = status
            task["output"] = output[-MAX_TASK_OUTPUT:]
            task["completed_at"] = int(time.time())

    threading.Thread(target=execute, daemon=True).start()
    return task


def fail(message, status=400):
    return jsonify({"error": message}), status


def request_json():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return None
    return payload


def installed_applications():
    result = flatpak(["list", "--app", "--columns=application,name,version,branch,origin"])
    applications = []
    with process_lock:
        active = {app_id: process.poll() is None for app_id, process in processes.items()}
    for line in result.stdout.splitlines():
        columns = line.split("\t")
        if not columns or not columns[0]:
            continue
        columns.extend([""] * (5 - len(columns)))
        app_id, name, version, branch, origin = columns[:5]
        applications.append(
            {
                "id": app_id,
                "name": name or app_id,
                "version": version,
                "branch": branch,
                "origin": origin,
                "running": active.get(app_id, False),
            }
        )
    return applications


@app.get("/api/status")
def status():
    return jsonify(
        {
            "flatpak_version": flatpak(["--version"], user=False).stdout.strip(),
            "display": os.environ.get("DISPLAY"),
            "viewer_path": "/novnc/vnc.html?autoconnect=1&resize=remote&path=websockify",
        }
    )


@app.get("/api/apps")
def list_apps():
    try:
        return jsonify({"apps": installed_applications()})
    except subprocess.CalledProcessError as error:
        app.logger.error("flatpak list failed: %s", error.stdout)
        return fail("Unable to list installed applications.", 502)


@app.get("/api/remotes")
def list_remotes():
    try:
        result = flatpak(["remotes", "--columns=name,title,url"])
    except subprocess.CalledProcessError as error:
        app.logger.error("flatpak remotes failed: %s", error.stdout)
        return fail("Unable to list configured remotes.", 502)
    remotes = []
    for line in result.stdout.splitlines():
        columns = line.split("\t")
        if not columns or not columns[0]:
            continue
        columns.extend([""] * (3 - len(columns)))
        remotes.append({"name": columns[0], "title": columns[1], "url": columns[2]})
    return jsonify({"remotes": remotes})


@app.post("/api/remotes")
def add_remote():
    payload = request_json()
    if payload is None:
        return fail("A JSON request body is required.")
    name, url = payload.get("name"), payload.get("url")
    if not valid_remote(name):
        return fail("Remote names may contain only letters, numbers, dots, underscores, and hyphens.")
    if not isinstance(url, str) or REMOTE_URL_PATTERN.fullmatch(url) is None:
        return fail("Remote URLs must use HTTPS.")
    return jsonify({"task": start_task(f"Add remote {name}", ["remote-add", "--if-not-exists", name, url])}), 202


@app.delete("/api/remotes/<remote>")
def remove_remote(remote):
    if not valid_remote(remote):
        return fail("Invalid remote name.")
    return jsonify({"task": start_task(f"Remove remote {remote}", ["remote-delete", remote])}), 202


@app.post("/api/install")
def install_app():
    payload = request_json()
    if payload is None:
        return fail("A JSON request body is required.")
    remote, app_id = payload.get("remote"), payload.get("app_id")
    if not valid_remote(remote):
        return fail("Invalid remote name.")
    if not valid_app_id(app_id):
        return fail("Enter a valid Flatpak application ID.")
    return jsonify({"task": start_task(f"Install {app_id}", ["install", "--noninteractive", "-y", remote, app_id])}), 202


@app.post("/api/apps/<app_id>/run")
def run_app(app_id):
    if not valid_app_id(app_id):
        return fail("Invalid Flatpak application ID.")
    with process_lock:
        current = processes.get(app_id)
        if current and current.poll() is None:
            return jsonify({"status": "already-running"})
    try:
        flatpak(["info", app_id])
    except subprocess.CalledProcessError:
        return fail("The requested application is not installed.", 404)
    process = subprocess.Popen(
        ["flatpak", "--user", "run", app_id],
        env=command_environment(),
        start_new_session=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    with process_lock:
        processes[app_id] = process
    return jsonify({"status": "started"}), 202


@app.post("/api/apps/<app_id>/stop")
def stop_app(app_id):
    if not valid_app_id(app_id):
        return fail("Invalid Flatpak application ID.")
    with process_lock:
        process = processes.get(app_id)
    if process is None or process.poll() is not None:
        return fail("The application is not running.", 409)
    os.killpg(process.pid, signal.SIGTERM)
    return jsonify({"status": "stopping"}), 202


@app.delete("/api/apps/<app_id>")
def uninstall_app(app_id):
    if not valid_app_id(app_id):
        return fail("Invalid Flatpak application ID.")
    with process_lock:
        process = processes.get(app_id)
    if process and process.poll() is None:
        return fail("Stop the application before uninstalling it.", 409)
    return jsonify({"task": start_task(f"Uninstall {app_id}", ["uninstall", "--noninteractive", "-y", app_id])}), 202


@app.get("/api/tasks")
def list_tasks():
    return jsonify({"tasks": task_snapshot()})


@app.errorhandler(Exception)
def unhandled_exception(error):
    app.logger.exception("Unhandled API error")
    return fail("An unexpected server error occurred.", 500)


if __name__ == "__main__":
    Path(os.environ.get("WEBFLATPAK_HOME", "/var/lib/webflatpak")).mkdir(parents=True, exist_ok=True)
    app.run(host="127.0.0.1", port=5000, threaded=True)
