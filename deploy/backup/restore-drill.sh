#!/usr/bin/env bash
# =============================================================================
# 恢复演练（非破坏性）
# 从最新 Restic 快照恢复双库到 *_drill 数据库，对账后删除；不碰生产库/卷。
#
# 用法：
#   ./deploy/backup/restore-drill.sh
#   RESTORE_TARGET=<snapshot-id> ./deploy/backup/restore-drill.sh
#
# 前置：restic / psql / pg_restore / createdb；Postgres 已通过 127.0.0.1:5432 暴露。
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="${COMPOSE_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
STAGING_DIR="${STAGING_DIR:-$COMPOSE_DIR/drill-restore}"
RESTORE_TARGET="${RESTORE_TARGET:-latest}"
KEEP_STAGING="${KEEP_STAGING:-0}"
DRILL_SUFFIX="${DRILL_SUFFIX:-drill}"

log() { echo "[$(date '+%F %T')] $*"; }
die() { log "ERROR: $*"; exit 1; }

if [ -f "$COMPOSE_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$COMPOSE_DIR/.env"
    set +a
fi

PGHOST="${PGHOST:-127.0.0.1}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-${PG_SUPER_USER:-postgres}}"
PGPASSWORD="${PGPASSWORD:-${PG_SUPER_PASSWORD:-}}"
MOBOBRAIN_DB_NAME="${PG_DB_MOBOBRAIN:-${MOBOBRAIN_DB_NAME:?缺少 MOBOBRAIN_DB_NAME}}"
ARCHIVE_DB_NAME="${PG_DB_ARCHIVE:-${ARCHIVE_DB_NAME:?缺少 ARCHIVE_DB_NAME}}"
MOBOBRAIN_DB_USER="${PG_USER_MOBOBRAIN:-${MOBOBRAIN_DB_USER:?缺少 MOBOBRAIN_DB_USER}}"
ARCHIVE_DB_USER="${PG_USER_ARCHIVE:-${ARCHIVE_DB_USER:?缺少 ARCHIVE_DB_USER}}"

DRILL_MOBO="${MOBOBRAIN_DB_NAME}_${DRILL_SUFFIX}"
DRILL_ARCHIVE="${ARCHIVE_DB_NAME}_${DRILL_SUFFIX}"

export PGPASSWORD

RESTIC_OPTS=()
if [ -n "${RESTIC_OPTIONS:-}" ]; then
    # shellcheck disable=SC2206
    RESTIC_OPTS=(${RESTIC_OPTIONS})
fi

[ -n "${RESTIC_REPOSITORY:-}" ] || die "缺少 RESTIC_REPOSITORY"
[ -n "${RESTIC_PASSWORD:-}" ] || die "缺少 RESTIC_PASSWORD"
for cmd in restic psql pg_restore createdb; do
    command -v "$cmd" >/dev/null 2>&1 || die "缺少命令：$cmd"
done

mkdir -p "$STAGING_DIR"

cleanup() {
    local rc=$?
    log "清理演练数据库 $DRILL_MOBO / $DRILL_ARCHIVE"
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -v ON_ERROR_STOP=0 \
        -c "DROP DATABASE IF EXISTS \"$DRILL_MOBO\" WITH (FORCE);" >/dev/null 2>&1 || true
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -v ON_ERROR_STOP=0 \
        -c "DROP DATABASE IF EXISTS \"$DRILL_ARCHIVE\" WITH (FORCE);" >/dev/null 2>&1 || true
    if [ "$KEEP_STAGING" = "1" ] || [ "$rc" -ne 0 ]; then
        log "保留 staging：$STAGING_DIR"
    else
        rm -rf "$STAGING_DIR"
    fi
}
trap cleanup EXIT

log "快照："
restic "${RESTIC_OPTS[@]}" snapshots --tag mobo-daily --latest 1

log "恢复快照到 staging：$STAGING_DIR"
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

log "重建演练库"
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -v ON_ERROR_STOP=1 \
    -c "DROP DATABASE IF EXISTS \"$DRILL_MOBO\" WITH (FORCE);"
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -v ON_ERROR_STOP=1 \
    -c "DROP DATABASE IF EXISTS \"$DRILL_ARCHIVE\" WITH (FORCE);"
createdb -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -O "$MOBOBRAIN_DB_USER" "$DRILL_MOBO"
createdb -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -O "$ARCHIVE_DB_USER" "$DRILL_ARCHIVE"

log "恢复 db_mobobrain -> $DRILL_MOBO"
pg_restore -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$DRILL_MOBO" "$MOBO_DUMP"

log "恢复 db_archive -> $DRILL_ARCHIVE"
pg_restore -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$DRILL_ARCHIVE" "$ARCHIVE_DUMP"

log "对账（快照库 vs 当前生产库；生产可能有增量，允许差异）"
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$DRILL_ARCHIVE" -v ON_ERROR_STOP=1 -c "
SELECT 'drill.timeline_events' AS scope, count(*) FROM archive.timeline_events
UNION ALL SELECT 'drill.reading_items', count(*) FROM archive.reading_items
UNION ALL SELECT 'drill.fitness_workouts', count(*) FROM archive.fitness_workouts
UNION ALL SELECT 'drill.project_retrospectives', count(*) FROM archive.project_retrospectives
UNION ALL SELECT 'drill.archive_assets', count(*) FROM archive.archive_assets;
"

psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$ARCHIVE_DB_NAME" -v ON_ERROR_STOP=1 -c "
SELECT 'prod.timeline_events' AS scope, count(*) FROM archive.timeline_events
UNION ALL SELECT 'prod.reading_items', count(*) FROM archive.reading_items
UNION ALL SELECT 'prod.fitness_workouts', count(*) FROM archive.fitness_workouts
UNION ALL SELECT 'prod.project_retrospectives', count(*) FROM archive.project_retrospectives
UNION ALL SELECT 'prod.archive_assets', count(*) FROM archive.archive_assets;
"

log "检查触发器/视图"
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$DRILL_ARCHIVE" -v ON_ERROR_STOP=1 -c "
SELECT tgname FROM pg_trigger
WHERE tgrelid IN ('archive.reading_items'::regclass,
                  'archive.reading_logs'::regclass,
                  'archive.fitness_workouts'::regclass,
                  'archive.project_retrospectives'::regclass)
  AND NOT tgisinternal
ORDER BY 1;
"
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$DRILL_ARCHIVE" -v ON_ERROR_STOP=1 -c "
SELECT count(*) AS weekly_rows FROM archive.v_weekly_life_analytics;
"

log "文件快照检查（不恢复卷）"
restic "${RESTIC_OPTS[@]}" ls "$RESTORE_TARGET" --tag mobo-daily | \
    grep -E '/(mobobrain_data|n8n_data|config)/' | head -n 20 || true

log "演练成功；记录实际耗时/结果到 docs/05-运维与灾备/备份与恢复演练.md"
