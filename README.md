# WebFlatpak

WebFlatpak packages the StrataOS WebUI assets in an Alpine Linux-based NGINX
container. It presents the existing WebUI at port `9090` and proxies its API,
noVNC, ttyd, and dynamic Docker terminal ports to a StrataOS WebUI instance.

It intentionally contains no Docker socket mount, host PID namespace, or
privileged mode. Administration actions remain authenticated and are executed
by the configured StrataOS WebUI upstream, not by this container.

## Run

1. Create an environment file and set the upstream address:

   ```sh
   cp .env.example .env
   # Edit .env: WEBFLATPAK_UPSTREAM=http://<strataos-host>:9090
   ```

   `WEBFLATPAK_UPSTREAM` must be an `http://` or `https://` URL with a host
   and optional port, but no path. If the terminal and noVNC services are on a
   different host, set `WEBFLATPAK_STREAM_UPSTREAM` to its scheme and host
   without a port.

2. Start the proxy:

   ```sh
   docker compose up --build -d
   ```

3. Open `http://<webflatpak-host>:9090/`.

The compose configuration publishes port `9090` for the UI and API, `6080`
for noVNC, `7681` for the system terminal, and `7690-7789` for dynamic Docker
terminals. The browser always uses these WebFlatpak ports; they are proxied to
the same numbered ports on the configured upstream host.

## Health check

```sh
curl --fail http://127.0.0.1:9090/healthz
```

## Build without Compose

```sh
docker build -t webflatpak .
docker run --rm \
  -e WEBFLATPAK_UPSTREAM=http://strataos-webui:9090 \
  -p 9090:8080 -p 6080:6080 -p 7681:7681 -p 7690-7789:7690-7789 \
  webflatpak
```

## Source relationship

`public/` is the current StrataOS WebUI static frontend. The system-specific
CGI handlers, authentication provider, Docker control helpers, and Flatpak
runtime remain in StrataOS and are accessed only through the configured
upstream. This keeps the container focused on Alpine-based delivery without
granting it host-management privileges.
