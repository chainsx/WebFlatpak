# WebFlatpak

WebFlatpak is a self-contained Alpine Linux Docker application for installing
and running GUI Flatpak applications in a browser. It provides:

- a Flatpak user installation and persistent application data;
- D-Bus, Xvfb, Openbox, and software Mesa for graphical Flatpak sessions;
- x11vnc and noVNC, exposed only through the authenticated WebFlatpak UI;
- a browser application manager for remotes, installs, launches, stops, and
  uninstalls.

It has no dependency on StrataOS, no Docker socket mount, and no host process
or network namespace sharing.

## Run

1. Create an environment file and set a unique password:

   ```sh
   cp .env.example .env
   # Edit .env: WEBFLATPAK_PASSWORD=...
   ```

2. Start the container:

   ```sh
   docker compose up --build -d
   ```

3. Open `http://<webflatpak-host>:8080/` and sign in with
   `WEBFLATPAK_USERNAME` and `WEBFLATPAK_PASSWORD`.

Add a remote in the **Remotes** section. For Flathub, use `flathub` and
`https://dl.flathub.org/repo/flathub.flatpakrepo`. Enter an application ID
such as `org.gnome.TextEditor`, wait for its installation task to finish, then
select **Run** and **Open viewer**.

The persistent `webflatpak-data` volume stores the Flatpak repository,
installed applications, and per-user data. Remove it explicitly only when all
application data should be discarded:

```sh
docker compose down -v
```

## Runtime requirements

Flatpak uses Linux namespaces, bind mounts, and bubblewrap sandboxing. The
Compose service therefore runs with `privileged: true`; this is a requirement
for Flatpak applications to create their own sandbox within a standard Docker
container. Deploy only on a host you administer, keep port `8080` on a trusted
network, and use a long, unique Web UI password.

All graphical applications share one isolated virtual X display. This allows
the active application to be viewed in the browser through the built-in noVNC
page. Stop an application before launching another graphical application to
avoid overlapping windows on the shared display.

## Health check

```sh
curl --fail http://127.0.0.1:8080/healthz
```

## Build without Compose

```sh
docker build -t webflatpak .
docker run --rm --privileged \
  -e WEBFLATPAK_PASSWORD='replace-with-a-long-unique-password' \
  -p 8080:8080 \
  webflatpak
```
