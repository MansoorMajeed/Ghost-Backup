FROM alpine:3.21

LABEL org.opencontainers.image.source="https://github.com/TryGhost/ghost-backup"
LABEL org.opencontainers.image.description="Backup solution for Ghost Docker deployments"
LABEL org.opencontainers.image.licenses="MIT"

RUN apk add --no-cache \
    restic \
    mysql-client \
    bash \
    curl \
    coreutils \
    tzdata

COPY entrypoint.sh /entrypoint.sh
COPY scripts/ /scripts/

RUN chmod +x /entrypoint.sh /scripts/*.sh

ENTRYPOINT ["/entrypoint.sh"]
