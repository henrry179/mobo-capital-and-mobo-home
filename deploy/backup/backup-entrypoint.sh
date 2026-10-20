#!/usr/bin/env bash
# =============================================================================
# 备份容器入口：写入 crontab，默认每天 03:00 执行
# 环境变量：
#   RUN_ONCE=1            只执行一次后退出（手工测试）
#   BACKUP_RUN_ON_START=1 启动后先跑一次，再进入 cron
# =============================================================================
set -Eeuo pipefail

mkdir -p /backup/dumps /var/log

if [ "${RUN_ONCE:-0}" = "1" ]; then
    echo "[$(date '+%F %T')] RUN_ONCE=1，执行一次备份"
    exec /usr/local/bin/run-daily-backup.sh
fi

if [ "${BACKUP_RUN_ON_START:-0}" = "1" ]; then
    echo "[$(date '+%F %T')] BACKUP_RUN_ON_START=1，启动即备份"
    /usr/local/bin/run-daily-backup.sh || echo "[$(date '+%F %T')] 启动备份失败，继续进入 cron"
fi

cat > /etc/crontabs/root <<'CRON'
0 3 * * * /usr/local/bin/run-daily-backup.sh >> /var/log/mobo-backup.log 2>&1
CRON

echo "[$(date '+%F %T')] 备份 cron 已启动：每天 03:00（容器时区 ${TZ:-UTC}）"
exec crond -f -l 2
