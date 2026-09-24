FROM nginx:alpine

COPY docker/nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY docker/entrypoint.sh /usr/local/bin/webflatpak-entrypoint
COPY public/ /usr/share/nginx/html/

RUN chmod 0555 /usr/local/bin/webflatpak-entrypoint \
    && find /usr/share/nginx/html -type f -exec chmod 0444 {} \;

ENV WEBFLATPAK_UPSTREAM=""

EXPOSE 8080 6080 7681 7690-7789

ENTRYPOINT ["/usr/local/bin/webflatpak-entrypoint"]
CMD ["nginx", "-g", "daemon off;"]
