#!/usr/bin/env bash
# =============================================================================
# 裸机/整机灾备恢复（破坏性！）
# 适用：服务器重装、数据卷损坏、数据库损坏，需要从 Restic 快照恢复。
#
# 前置：
#   1) 已安装 docker / docker compose / restic / postgresql-client / rsync
#   2) 已从密码管理器恢复 /opt/mobo-stack/.env（含 RESTIC_PASSWORD、N8N_ENCRYPTION_KEY）
#   3) 当前目录是项目根（含 docker-compose.yml）
#
# 用法：
#   CONFIRM_RESTORE=YES ./deploy/backup/disaster-recovery.sh
#   RESTORE_TARGET=<snapshot-id> CONFIRM_RESTORE=YES ./deploy/backup/disaster-recovery.sh
#
# 警告：
#   - 会停止容器、覆盖数据卷、DROP 并重建两个数据库。
#   - 不会恢复 .env；必须从密码管理器单独恢复。
#   - 大文件恢复时间取决于 OSS 下载带宽，4–24h 是合理预期。
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="${COMPOSE_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
STAGING_DIR="${STAGING_DIR:-$COMPOSE_DIR/restore-staging}"
RESTORE_TARGET="${RESTORE_TARGET:-latest}"
RESTORE_GLOBALS="${RESTORE_GLOBALS:-0}"
KEEP_STAGING="${KEEP_STAGING:-0}"
CONFIRM_RESTORE="${CONFIRM_RESTORE:-NO}"

log() { echo "[$(date '+%F %T')] $*"; }
die() { log "ERROR: $*"; exit 1; }

# 载入 .env（只用于取数据库/Restic 变量；不会覆盖已导出的变量）
if [ -f "$COMPOSE_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$COMPOSE_DIR/.env"
    set +a
fi

PGHOST="${PGHOST:-127.0.0.1}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-${POSTGRES_SUPER_USER:-postgres}}"
PGPASSWORD="${PGPASSWORD:-${POSTGRES_SUPER_PASSWORD:-}}"
MOBOBRAIN_DB_NAME="${MOBOBRAIN_DB_NAME:?缺少 MOBOBRAIN_DB_NAME}"
ARCHIVE_DB_NAME="${ARCHIVE_DB_NAME:?缺少 ARCHIVE_DB_NAME}"
MOBOBRAIN_DB_USER="${MOBOBRAIN_DB_USER:?缺少 MOBOBRAIN_DB_USER}"
ARCHIVE_DB_USER="${ARCHIVE_DB_USER:?缺少 ARCHIVE_DB_USER}"

SIYUAN_DATA_DIR="${SIYUAN_DATA_DIR:-$COMPOSE_DIR/deploy/volumes/mobobrain_data}"
N8N_DATA_DIR="${N8N_DATA_DIR:-$COMPOSE_DIR/deploy/volumes/n8n_data}"
SIYUAN_UID="${SIYUAN_UID:-1000}"
SIYUAN_GID="${SIYUAN_GID:-1000}"
N8N_UID="${N8N_UID:-1000}"
N8N_GID="${N8N_GID:-1000}"

export PGPASSWORD

RESTIC_OPTS=()
if [ -n "${RESTIC_OPTIONS:-}" ]; then
    # shellcheck disable=SC2206
    RESTIC_OPTS=(${RESTIC_OPTIONS})
fi

# -----------------------------------------------------------------------------
# 0. 安全门禁与前置检查
# -----------------------------------------------------------------------------
[ "$CONFIRM_RESTORE" = "YES" ] || die "必须显式设置 CONFIRM_RESTORE=YES 才能执行破坏性恢复"
[ "$(id -u)" = "0" ] || die "请用 root 执行（需要 chown 数据卷）"
[ -f "$COMPOSE_DIR/docker-compose.yml" ] || die "找不到 $COMPOSE_DIR/docker-compose.yml"
[ -n "${RESTIC_REPOSITORY:-}" ] || die "缺少 RESTIC_REPOSITORY"
[ -n "${RESTIC_PASSWORD:-}" ] || die "缺少 RESTIC_PASSWORD（应从密码管理器恢复）"
[ -n "${PGPASSWORD:-}" ] || die "缺少 PGPASSWORD / POSTGRES_SUPER_PASSWORD"

for cmd in docker restic psql pg_restore createdb rsync; do
    command -v "$cmd" >/dev/null 2>&1 || die "缺少命令：$cmd"
done

log "恢复目标：$RESTORE_TARGET；仓库：$RESTIC_REPOSITORY"
log "Compose：$COMPOSE_DIR；staging：$STAGING_DIR"
free -m || true
df -h "$COMPOSE_DIR" || true

mkdir -p "$STAGING_DIR"

cleanup() {
    local rc=$?
    if [ "$KEEP_STAGING" = "1" ] || [ "$rc" -ne 0 ]; then
        log "保留 staging 以便排查：$STAGING_DIR"
    else
        log "清理 staging：$STAGING_DIR"
        rm -rf "$STAGING_DIR"
    fi
}
trap cleanup EXIT

cd "$COMPOSE_DIR"
docker compose config >/dev/null

# -----------------------------------------------------------------------------
# 1. 选择快照
# -----------------------------------------------------------------------------
log "可用快照（mobo-daily，最近 1 条）："
restic "${RESTIC_OPTS[@]}" snapshots --tag mobo-daily --latest 1

# -----------------------------------------------------------------------------
# 2. 停止应用（保留 Postgres 运行到恢复前？这里全部停止，避免卷写入）
# -----------------------------------------------------------------------------
log "停止容器（保留 Postgres 数据卷，不删除）"
docker compose stop caddy mobobrain-pkm mobobrain-n8n archive-dashboard restic-backup || true
docker compose stop postgres || true

# -----------------------------------------------------------------------------
# 3. 拉取快照到 staging
# -----------------------------------------------------------------------------
log "Restic restore -> $STAGING_DIR"
restic "${RESTIC_OPTS[@]}" restore "$RESTORE_TARGET" \
    --tag mobo-daily \
    --target "$STAGING_DIR" \
    --verbose

DUMP_DIR="$STAGING_DIR/backup/dumps"
[ -d "$DUMP_DIR" ] || die "快照中缺少 $DUMP_DIR"

MOBO_DUMP="$(ls -1t "$DUMP_DIR"/db_mobobrain-*.dump 2>/dev/null | head -n1 || true)"
ARCHIVE_DUMP="$(ls -1t "$DUMP_DIR"/db_archive-*.dump 2>/dev/null | head -n1 || true)"
[ -n "$MOBO_DUMP" ] || die "找不到 db_mobobrain dump"
[ -n "$ARCHIVE_DUMP" ] || die "找不到 db_archive dump"
log "使用 dump：$MOBO_DUMP"
log "使用 dump：$ARCHIVE_DUMP"

# -----------------------------------------------------------------------------
# 4. 恢复文件卷与配置
# -----------------------------------------------------------------------------
if [ -d "$STAGING_DIR/data/mobobrain_data" ]; then
    log "恢复思源工作区 -> $SIYUAN_DATA_DIR"
    mkdir -p "$SIYUAN_DATA_DIR"
    rsync -a --delete "$STAGING_DIR/data/mobobrain_data/" "$SIYUAN_DATA_DIR/"
    chown -R "$SIYUAN_UID:$SIYUAN_GID" "$SIYUAN_DATA_DIR"
else
    log "WARN: 快照中没有 mobobrain_data，跳过"
fi

if [ -d "$STAGING_DIR/data/n8n_data" ]; then
    log "恢复 n8n 数据 -> $N8N_DATA_DIR"
    mkdir -p "$N8N_DATA_DIR"
    rsync -a --delete "$STAGING_DIR/data/n8n_data/" "$N8N_DATA_DIR/"
    chown -R "$N8N_UID:$N8N_GID" "$N8N_DATA_DIR"
else
    log "WARN: 快照中没有 n8n_data，跳过"
fi

CONFIG_STAGING="$STAGING_DIR/data/config"
if [ -d "$CONFIG_STAGING" ]; then
    log "恢复 Caddyfile / 初始化 SQL / 备份脚本 / Compose"
    mkdir -p "$COMPOSE_DIR/deploy/caddy" "$COMPOSE_DIR/deploy/backup" "$COMPOSE_DIR/deploy/postgres/initdb"
    [ -d "$CONFIG_STAGING/caddy" ] && rsync -a "$CONFIG_STAGING/caddy/" "$COMPOSE_DIR/deploy/caddy/"
    [ -d "$CONFIG_STAGING/backup" ] && rsync -a "$CONFIG_STAGING/backup/" "$COMPOSE_DIR/deploy/backup/"
    [ -d "$CONFIG_STAGING/initdb" ] && rsync -a "$CONFIG_STAGING/initdb/" "$COMPOSE_DIR/deploy/postgres/initdb/"
    [ -f "$CONFIG_STAGING/docker-compose.yml" ] && cp "$CONFIG_STAGING/docker-compose.yml" "$COMPOSE_DIR/docker-compose.yml"
    # 不恢复 .env：必须来自密码管理器
else
    log "WARN: 快照中没有 config，保留现有配置"
fi

# -----------------------------------------------------------------------------
# 5. 单启 Postgres，DROP/重建并恢复双库
# -----------------------------------------------------------------------------
log "启动 Postgres"
docker compose up -d postgres

log "等待 Postgres ready"
for _ in $(seq 1 60); do
    if docker compose exec -T postgres pg_isready -U "$PGUSER" -d postgres >/dev/null 2>&1; then
        break
    fi
    sleep 2
done
docker compose exec -T postgres pg_isready -U "$PGUSER" -d postgres >/dev/null

log "终止活动连接并重建数据库"
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -v ON_ERROR_STOP=1 <<SQL
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname IN ('$MOBOBRAIN_DB_NAME', '$ARCHIVE_DB_NAME')
  AND pid <> pg_backend_pid();
SQL

psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -v ON_ERROR_STOP=1 \
    -c "DROP DATABASE IF EXISTS \"$MOBOBRAIN_DB_NAME\" WITH (FORCE);"
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -v ON_ERROR_STOP=1 \
    -c "DROP DATABASE IF EXISTS \"$ARCHIVE_DB_NAME\" WITH (FORCE);"

createdb -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -O "$MOBOBRAIN_DB_USER" "$MOBOBRAIN_DB_NAME"
createdb -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -O "$ARCHIVE_DB_USER" "$ARCHIVE_DB_NAME"

log "pg_restore db_mobobrain"
pg_restore -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" \
    -d "$MOBOBRAIN_DB_NAME" --verbose "$MOBO_DUMP"

log "pg_restore db_archive"
pg_restore -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" \
    -d "$ARCHIVE_DB_NAME" --verbose "$ARCHIVE_DUMP"

if [ "$RESTORE_GLOBALS" = "1" ]; then
    GLOBALS_FILE="$(ls -1t "$DUMP_DIR"/globals-*.sql 2>/dev/null | head -n1 || true)"
    if [ -n "$GLOBALS_FILE" ]; then
        log "恢复 globals（角色/权限）；已存在角色可能报错，属正常"
        psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -f "$GLOBALS_FILE" || true
    fi
fi

log "ANALYZE"
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$MOBOBRAIN_DB_NAME" -c "ANALYZE;" || true
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$ARCHIVE_DB_NAME" -c "ANALYZE;" || true

# -----------------------------------------------------------------------------
# 6. 拉起全栈 + 对账
# -----------------------------------------------------------------------------
log "拉起全栈"
docker compose up -d

log "等待服务启动"
sleep 15

log "核心表计数"
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$ARCHIVE_DB_NAME" -c "
SELECT 'timeline_events' AS table_name, count(*) FROM archive.timeline_events
UNION ALL SELECT 'reading_items', count(*) FROM archive.reading_items
UNION ALL SELECT 'fitness_workouts', count(*) FROM archive.fitness_workouts
UNION ALL SELECT 'project_retrospectives', count(*) FROM archive.project_retrospectives
UNION ALL SELECT 'archive_assets', count(*) FROM archive.archive_assets;
"
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$MOBOBRAIN_DB_NAME" -c "
SELECT 'articles_vault' AS table_name, count(*) FROM intel.articles_vault
UNION ALL SELECT 'content_drafts', count(*) FROM intel.content_drafts;
"

log "Smoke Test（若存在）"
if [ -x "$COMPOSE_DIR/deploy/scripts/smoke-test.sh" ]; then
    "$COMPOSE_DIR/deploy/scripts/smoke-test.sh" || log "WARN: Smoke Test 有失败项，请人工检查"
fi

log "恢复完成。请立即检查："
log "  1) https://archive... 登录与看板"
log "  2) https://kb... 思源文档/附件"
log "  3) n8n 工作流与凭证"
log "  4) 记录实际 RTO 到 docs/05-运维与灾备/备份与恢复演练.md"
