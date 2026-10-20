# =============================================================================
# 每日备份镜像：Restic + PostgreSQL 16 客户端
# 说明：不要用 alpine:3.20 裸镜像；必须显式安装 restic 与 pg_dump。
# =============================================================================
FROM alpine:3.20

RUN apk add --no-cache \
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
