FROM alpine:3.22

RUN apk add --no-cache \
        apache2-utils \
        dbus \
        dbus-x11 \
        flatpak \
        font-dejavu \
        mesa-dri-gallium \
        nginx \
        novnc \
        openbox \
        py3-flask \
        py3-gunicorn \
        su-exec \
        tini \
        websockify \
        x11vnc \
        xvfb \
    && addgroup -S webflatpak \
    && adduser -S -D -h /var/lib/webflatpak -G webflatpak webflatpak \
    && mkdir -p /app/public /run/user/1000 /var/lib/webflatpak \
    && chown -R webflatpak:webflatpak /run/user/1000 /var/lib/webflatpak

COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/entrypoint.sh /usr/local/bin/webflatpak-entrypoint
COPY docker/runtime.sh /usr/local/bin/webflatpak-runtime
COPY app/server.py /app/server.py
COPY public/ /app/public/

RUN chmod 0555 /usr/local/bin/webflatpak-entrypoint /usr/local/bin/webflatpak-runtime \
    && find /app/public -type f -exec chmod 0444 {} \;

ENV WEBFLATPAK_USERNAME=admin
ENV WEBFLATPAK_HOME=/var/lib/webflatpak

EXPOSE 8080

VOLUME ["/var/lib/webflatpak"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD wget -q --spider http://127.0.0.1:8080/healthz || exit 1

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/webflatpak-entrypoint"]
CMD ["nginx", "-g", "daemon off;"]
