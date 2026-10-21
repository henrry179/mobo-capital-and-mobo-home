#!/usr/bin/env bash
# 路径: /opt/mobo-stack/scripts/mobo_watchdog.sh
# 定时任务: */15 * * * * /opt/mobo-stack/scripts/mobo_watchdog.sh

source /opt/mobo-stack/.env

MEM_AVAIL_MB=$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo)
DISK_USED_PCT=$(df / | awk 'NR==2 {gsub("%",""); print $5}')
UNHEALTHY_CONTAINERS=$(docker ps --filter "health=unhealthy" --format "{{.Names}}")

ALERT_MSG=""
if [ "$MEM_AVAIL_MB" -lt 300 ]; then
    ALERT_MSG="${ALERT_MSG}[内存预警] 2C4G 宿主机可用内存仅剩 ${MEM_AVAIL_MB}MB；"
fi

if [ "$DISK_USED_PCT" -gt 85 ]; then
    ALERT_MSG="${ALERT_MSG}[磁盘预警] 根分区使用率已达 ${DISK_USED_PCT}%；"
fi

if [ -n "$UNHEALTHY_CONTAINERS" ]; then
    ALERT_MSG="${ALERT_MSG}[容器异常] 发现不健康容器: ${UNHEALTHY_CONTAINERS}，正在自动重启；"
    docker restart $UNHEALTHY_CONTAINERS
fi

if [ -n "$ALERT_MSG" ] && [ -n "${ALERT_WEBHOOK_URL:-}" ]; then
    curl -s -X POST "$ALERT_WEBHOOK_URL" \
      -H 'Content-Type: application/json' \
      -d "{\"msg_type\":\"text\",\"content\":{\"text\":\"🚨 莫伯双站巡检哨兵告警: ${ALERT_MSG}\"}}" > /dev/null
fi