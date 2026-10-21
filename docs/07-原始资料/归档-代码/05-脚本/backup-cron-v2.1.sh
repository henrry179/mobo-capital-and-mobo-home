#!/bin/sh
# 路径: /opt/mobo-stack/scripts/backup-cron.sh
# 功能: 每日自动导出 db_mobobrain 与 db_archive 双库 SQL，并连同思源笔记/n8n配置加密备份至阿里云 OSS

set -e
BACKUP_TMP="/tmp/mobo_pg_dumps"
mkdir -p "$BACKUP_TMP"

echo "[$(date)] Starting PostgreSQL dual-database dump..."
PGPASSWORD="$PG_SUPER_PASSWORD" pg_dump -h mobo-postgres -U postgres -d db_mobobrain -F p > "$BACKUP_TMP/db_mobobrain.sql"
PGPASSWORD="$PG_SUPER_PASSWORD" pg_dump -h mobo-postgres -U postgres -d db_archive -F p > "$BACKUP_TMP/db_archive.sql"

# 若 Restic 仓库尚未初始化则自动初始化
restic snapshots > /dev/null 2>&1 || restic init

echo "[$(date)] Uploading AES-256 encrypted snapshot to OSS..."
restic backup "$BACKUP_TMP" /backup/siyuan /backup/n8n /backup/caddy --tag mobo-daily

# 保留最近 7 天每日快照、4 周周快照、6 个月月度快照，自动清理过期数据块
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune

rm -rf "$BACKUP_TMP"
echo "[$(date)] Backup completed successfully."