#!/bin/sh
set -eu

export HOME="${WEBFLATPAK_HOME:-/var/lib/webflatpak}"
export XDG_RUNTIME_DIR=/run/user/1000
export DISPLAY=:99
export LIBGL_ALWAYS_SOFTWARE=1

mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID

Xvfb "$DISPLAY" -screen 0 1440x900x24 -nolisten tcp &
xvfb_pid=$!
for _ in $(seq 1 50); do
    test -S /tmp/.X11-unix/X99 && break
    sleep 0.1
done
test -S /tmp/.X11-unix/X99 || {
    printf '%s\n' "webflatpak: Xvfb did not create the virtual display" >&2
    exit 1
}
openbox-session &
openbox_pid=$!
x11vnc -display "$DISPLAY" -localhost -forever -shared -nopw -rfbport 5900 -xkb &
x11vnc_pid=$!
websockify --web /usr/share/novnc 127.0.0.1:6080 127.0.0.1:5900 &
websockify_pid=$!

cleanup() {
    kill -TERM "$websockify_pid" "$x11vnc_pid" "$openbox_pid" "$xvfb_pid" "$DBUS_SESSION_BUS_PID" 2>/dev/null || true
    wait "$websockify_pid" "$x11vnc_pid" "$openbox_pid" "$xvfb_pid" 2>/dev/null || true
}
trap cleanup INT TERM

gunicorn --chdir /app --workers 1 --threads 8 --bind 127.0.0.1:5000 server:app &
server_pid=$!
wait "$server_pid"
status=$?
cleanup
exit "$status"
