#!/bin/sh
set -eu

fail() {
    printf '%s\n' "webflatpak: $*" >&2
    exit 1
}

: "${WEBFLATPAK_PASSWORD:?WEBFLATPAK_PASSWORD must be set}"
: "${WEBFLATPAK_USERNAME:=admin}"

printf '%s' "$WEBFLATPAK_USERNAME" | grep -Eq '^[A-Za-z0-9_.-]{1,64}$' ||
    fail "WEBFLATPAK_USERNAME must contain only letters, numbers, dots, underscores, or hyphens"

umask 077
htpasswd -Bbn "$WEBFLATPAK_USERNAME" "$WEBFLATPAK_PASSWORD" > /run/webflatpak.htpasswd
chown root:nginx /run/webflatpak.htpasswd
chmod 0640 /run/webflatpak.htpasswd
unset WEBFLATPAK_PASSWORD

mkdir -p /run/dbus /run/user/1000 "$WEBFLATPAK_HOME" /tmp/.X11-unix
chown webflatpak:webflatpak /run/user/1000 "$WEBFLATPAK_HOME"
chmod 1777 /tmp/.X11-unix

dbus-daemon --system --fork --nopidfile
su-exec webflatpak /usr/local/bin/webflatpak-runtime &
runtime_pid=$!

"$@" &
nginx_pid=$!

cleanup() {
    kill -TERM "$nginx_pid" "$runtime_pid" 2>/dev/null || true
    wait "$nginx_pid" "$runtime_pid" 2>/dev/null || true
}
trap cleanup INT TERM

wait "$nginx_pid"
status=$?
cleanup
exit "$status"
