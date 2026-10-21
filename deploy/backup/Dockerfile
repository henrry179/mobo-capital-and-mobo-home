# =============================================================================
# 每日备份镜像：Restic + PostgreSQL 16 客户端
# 说明：不要用 alpine:3.20 裸镜像；必须显式安装 restic 与 pg_dump。
# =============================================================================
FROM alpine:3.20

# apk 源可配置：默认官方源；受限网络下通过 build arg 指向国内镜像
ARG APK_MIRROR=

RUN set -eux; \
    if [ -n "$APK_MIRROR" ]; then \
        sed -i "s|https://dl-cdn.alpinelinux.org|${APK_MIRROR}|g" /etc/apk/repositories; \
    fi; \
    apk add --no-cache \
        bash \
        ca-certificates \
        curl \
        postgresql16-client \
        restic \
        tzdata \
    && mkdir -p /backup/dumps /var/log \
    && rm -rf /var/cache/apk/*

COPY backup-entrypoint.sh /usr/local/bin/backup-entrypoint.sh
COPY run-daily-backup.sh /usr/local/bin/run-daily-backup.sh
COPY disaster-recovery.sh /usr/local/bin/disaster-recovery.sh
COPY restore-drill.sh /usr/local/bin/restore-drill.sh

RUN chmod +x /usr/local/bin/*.sh

ENTRYPOINT ["/usr/local/bin/backup-entrypoint.sh"]
