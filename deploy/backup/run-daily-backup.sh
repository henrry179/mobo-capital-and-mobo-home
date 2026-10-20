#!/usr/bin/env bash
# =============================================================================
# 每日备份：pg_dump -Fc 双库 + globals + 思源/n8n 卷 + 配置 -> Restic -> OSS
# 注意：不直接备份运行中的 pg_data；数据库必须走逻辑导出。
# =============================================================================
set -Eeuo pipefail

log() { echo "[$(date '+%F %T')] $*"; }

on_error() {
    log "ERROR: line $1 failed: $2"
}
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

require() {
    local name="$1"
    if [ -z "${!name:-}" ]; then
        log "ERROR: 缺少环境变量 $name"
        exit 1
    fi
}

require PGHOST
require PGUSER
require PGPASSWORD
require MOBOBRAIN_DB_NAME
require ARCHIVE_DB_NAME
require RESTIC_REPOSITORY
require RESTIC_PASSWORD

STAGING_DIR="${BACKUP_STAGING_DIR:-/backup}"
DUMP_DIR="${STAGING_DIR}/dumps"
SIYUAN_DATA_DIR="${SIYUAN_DATA_DIR:-/data/mobobrain_data}"
N8N_DATA_DIR="${N8N_DATA_DIR:-/data/n8n_data}"
CONFIG_DIR="${CONFIG_DIR:-/data/config}"
TS="$(date '+%Y%m%d-%H%M%S')"
HOSTNAME_VALUE="$(hostname)"

mkdir -p "$DUMP_DIR"
chmod 700 "$DUMP_DIR"

RESTIC_OPTS=()
if [ -n "${RESTIC_OPTIONS:-}" ]; then
    # shellcheck disable=SC2206
    RESTIC_OPTS=(${RESTIC_OPTIONS})
fi

log "开始备份 $TS；仓库=$RESTIC_REPOSITORY"

# -----------------------------------------------------------------------------
# 1. 数据库逻辑备份
# -----------------------------------------------------------------------------
log "pg_dump db_mobobrain"
pg_dump -h "$PGHOST" -p "${PGPORT:-5432}" -U "$PGUSER" \
    -d "$MOBOBRAIN_DB_NAME" -Fc \
    -f "$DUMP_DIR/db_mobobrain-${TS}.dump"

log "pg_dump db_archive"
pg_dump -h "$PGHOST" -p "${PGPORT:-5432}" -U "$PGUSER" \
    -d "$ARCHIVE_DB_NAME" -Fc \
    -f "$DUMP_DIR/db_archive-${TS}.dump"

log "pg_dumpall --globals-only"
pg_dumpall -h "$PGHOST" -p "${PGPORT:-5432}" -U "$PGUSER" \
    --globals-only -f "$DUMP_DIR/globals-${TS}.sql"

chmod 600 "$DUMP_DIR"/*-"${TS}".dump "$DUMP_DIR/globals-${TS}.sql"

# -----------------------------------------------------------------------------
# 2. Restic 仓库初始化（仅首次）
# -----------------------------------------------------------------------------
if ! restic "${RESTIC_OPTS[@]}" cat config >/dev/null 2>&1; then
    log "Restic 仓库不可读，尝试初始化（首次部署）"
    restic "${RESTIC_OPTS[@]}" init
fi

# -----------------------------------------------------------------------------
# 3. 备份 dump + 文件卷 + 配置
# -----------------------------------------------------------------------------
BACKUP_PATHS=("$DUMP_DIR")
for p in "$SIYUAN_DATA_DIR" "$N8N_DATA_DIR" "$CONFIG_DIR"; do
    if [ -d "$p" ]; then
        BACKUP_PATHS+=("$p")
    else
        log "WARN: 路径不存在，跳过 $p"
    fi
done

log "Restic backup：${BACKUP_PATHS[*]}"
restic "${RESTIC_OPTS[@]}" backup "${BACKUP_PATHS[@]}" \
    --tag mobo-daily \
    --host "$HOSTNAME_VALUE" \
    --verbose

# -----------------------------------------------------------------------------
# 4. 保留策略 + 校验
# -----------------------------------------------------------------------------
log "Restic forget/prune"
restic "${RESTIC_OPTS[@]}" forget \
    --keep-daily "${BACKUP_KEEP_DAILY:-7}" \
    --keep-weekly "${BACKUP_KEEP_WEEKLY:-4}" \
    --keep-monthly "${BACKUP_KEEP_MONTHLY:-6}" \
    --prune

# 每周日做一次元数据校验；每月 1 日抽查 5% 数据
if [ "$(date '+%u')" = "7" ]; then
    log "Restic check（每周）"
    restic "${RESTIC_OPTS[@]}" check
fi
if [ "$(date '+%d')" = "01" ]; then
    log "Restic check --read-data-subset=5%（每月）"
    restic "${RESTIC_OPTS[@]}" check --read-data-subset=5%
fi

# -----------------------------------------------------------------------------
# 5. 清理本地临时 dump（只保留最近 2 天）
# -----------------------------------------------------------------------------
find "$DUMP_DIR" -type f -mtime +2 -delete || true

log "备份完成；最近快照："
restic "${RESTIC_OPTS[@]}" snapshots --latest 3 || true
log "本地 dump："
ls -lh "$DUMP_DIR" | tail -n 10 || true
