const state = { viewerPath: null };

function message(error) {
  return error instanceof Error ? error.message : String(error);
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: {"Content-Type": "application/json", ...(options.headers || {})},
    cache: "no-store",
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.error || `Request failed (${response.status})`);
  return payload;
}

function setStatus(text, failed = false) {
  document.querySelector("#runtime-status").textContent = text;
  document.querySelector(".status-dot").classList.toggle("failed", failed);
}

function element(name, text) {
  const node = document.createElement(name);
  node.textContent = text;
  return node;
}

function renderRemotes(remotes) {
  const list = document.querySelector("#remotes");
  const select = document.querySelector("#install-remote");
  list.replaceChildren();
  select.replaceChildren();
  if (!remotes.length) {
    list.append(element("li", "No remotes configured."));
    return;
  }
  for (const remote of remotes) {
    const row = document.createElement("li");
    const details = document.createElement("span");
    details.textContent = `${remote.title || remote.name} (${remote.url})`;
    const remove = element("button", "Remove");
    remove.className = "danger small";
    remove.type = "button";
    remove.addEventListener("click", async () => {
      if (!confirm(`Remove remote "${remote.name}"?`)) return;
      try {
        await api(`/api/remotes/${encodeURIComponent(remote.name)}`, {method: "DELETE"});
        await refresh();
      } catch (error) {
        alert(message(error));
      }
    });
    row.append(details, remove);
    list.append(row);
    const option = element("option", remote.name);
    option.value = remote.name;
    select.append(option);
  }
}

function renderApps(apps) {
  const container = document.querySelector("#apps");
  container.replaceChildren();
  if (!apps.length) {
    container.append(element("p", "No Flatpak applications are installed yet."));
    return;
  }
  const template = document.querySelector("#app-template");
  for (const app of apps) {
    const card = template.content.firstElementChild.cloneNode(true);
    card.querySelector("h3").textContent = app.name;
    card.querySelector(".badge").textContent = app.running ? "Running" : "Stopped";
    card.querySelector(".badge").classList.toggle("running", app.running);
    card.querySelector(".app-id").textContent = app.id;
    card.querySelector(".app-version").textContent = app.version || "Unknown";
    card.querySelector(".app-origin").textContent = app.origin || "Unknown";
    const invoke = (action, options = {}) => async () => {
      try {
        await api(`/api/apps/${encodeURIComponent(app.id)}${action}`, options);
        await refresh();
      } catch (error) {
        alert(message(error));
      }
    };
    card.querySelector(".run").addEventListener("click", invoke("/run", {method: "POST"}));
    card.querySelector(".stop").addEventListener("click", invoke("/stop", {method: "POST"}));
    card.querySelector(".remove").addEventListener("click", async () => {
      if (!confirm(`Uninstall ${app.id}?`)) return;
      await invoke("", {method: "DELETE"})();
    });
    card.querySelector(".viewer").addEventListener("click", () => openViewer(app));
    container.append(card);
  }
}

function renderTasks(tasks) {
  const list = document.querySelector("#tasks");
  list.replaceChildren();
  if (!tasks.length) {
    list.append(element("p", "No background tasks yet."));
    return;
  }
  for (const task of tasks) {
    const item = document.createElement("article");
    item.className = `task task-${task.status}`;
    const heading = element("strong", `${task.name}: ${task.status}`);
    const output = element("pre", task.output || "Waiting for output...");
    item.append(heading, output);
    list.append(item);
  }
}

function openViewer(app) {
  if (!state.viewerPath) {
    alert("The viewer is not ready. Refresh the page and try again.");
    return;
  }
  document.querySelector("#viewer-title").textContent = app.name;
  document.querySelector("#viewer-frame").src = state.viewerPath;
  document.querySelector("#viewer-dialog").showModal();
}

async function refresh() {
  try {
    const [status, remotes, apps, tasks] = await Promise.all([
      api("/api/status"),
      api("/api/remotes"),
      api("/api/apps"),
      api("/api/tasks"),
    ]);
    state.viewerPath = status.viewer_path;
    setStatus(status.flatpak_version);
    renderRemotes(remotes.remotes);
    renderApps(apps.apps);
    renderTasks(tasks.tasks);
  } catch (error) {
    setStatus(message(error), true);
  }
}

document.querySelector("#remote-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const form = new FormData(event.currentTarget);
  try {
    await api("/api/remotes", {
      method: "POST",
      body: JSON.stringify({name: form.get("name"), url: form.get("url")}),
    });
    await refresh();
  } catch (error) {
    alert(message(error));
  }
});

document.querySelector("#install-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const form = new FormData(event.currentTarget);
  try {
    await api("/api/install", {
      method: "POST",
      body: JSON.stringify({remote: form.get("remote"), app_id: form.get("app_id")}),
    });
    event.currentTarget.reset();
    await refresh();
  } catch (error) {
    alert(message(error));
  }
});

document.querySelector("#refresh").addEventListener("click", refresh);
document.querySelector("#close-viewer").addEventListener("click", () => {
  const dialog = document.querySelector("#viewer-dialog");
  dialog.close();
  document.querySelector("#viewer-frame").src = "about:blank";
});

setInterval(refresh, 5000);
refresh();
