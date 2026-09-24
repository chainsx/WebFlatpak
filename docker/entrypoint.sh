#!/bin/sh
set -eu

fail() {
    printf '%s\n' "webflatpak: $*" >&2
    exit 1
}

valid_url() {
    printf '%s' "$1" | grep -Eq '^https?://([A-Za-z0-9.-]+|\[[0-9A-Fa-f:.]+\])(:[0-9]{1,5})?$'
}

: "${WEBFLATPAK_UPSTREAM:?WEBFLATPAK_UPSTREAM must be an http(s) URL without a path}"
valid_url "$WEBFLATPAK_UPSTREAM" ||
    fail "WEBFLATPAK_UPSTREAM must be an http(s) URL without a path"

scheme=${WEBFLATPAK_UPSTREAM%%://*}
authority=${WEBFLATPAK_UPSTREAM#*://}
case "$authority" in
    \[*\]*)
        stream_host=${authority%%]*}]
        stream_host="${stream_host}]"
        ;;
    *)
        stream_host=${authority%%:*}
        ;;
esac

WEBFLATPAK_STREAM_UPSTREAM=${WEBFLATPAK_STREAM_UPSTREAM:-"$scheme://$stream_host"}
valid_url "$WEBFLATPAK_STREAM_UPSTREAM" ||
    fail "WEBFLATPAK_STREAM_UPSTREAM must be an http(s) URL without a path"

stream_authority=${WEBFLATPAK_STREAM_UPSTREAM#*://}
case "$stream_authority" in
    \[*\])
        ;;
    *:*)
        fail "WEBFLATPAK_STREAM_UPSTREAM must not include a port"
        ;;
esac

export WEBFLATPAK_UPSTREAM

cat > /etc/nginx/conf.d/00-websocket-map.conf <<'EOF'
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
EOF

{
    for port in 6080 7681 $(seq 7690 7789); do
        cat <<EOF
server {
    listen ${port};
    server_name _;

    location / {
        proxy_pass ${WEBFLATPAK_STREAM_UPSTREAM}:${port};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
        proxy_ssl_server_name on;
    }
}

EOF
    done
} > /etc/nginx/conf.d/10-stream-proxies.conf

exec /docker-entrypoint.sh "$@"
