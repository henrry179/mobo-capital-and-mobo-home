#!/usr/bin/env bash
# =============================================================================
# 迁移 runner：按文件名顺序执行 migrations/*.sql，并记录到 schema_migrations
# 用法：
#   ./migrations/apply.sh db_archive
#   ./migrations/apply.sh db_mobobrain
#   DRY_RUN=1 ./migrations/apply.sh db_archive
#
# 前置：docker compose 正在运行 postgres 服务。
# 说明：
# - 默认 psql -1（单事务）；文件含 "-- migrate:no-transaction" 时不加 -1。
# - 已执行且 checksum 不变则跳过；checksum 变化则报错，需人工处理。
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_DB="${1:-db_archive}"
PGUSER="${PGUSER:-postgres}"
DRY_RUN="${DRY_RUN:-0}"

case "$TARGET_DB" in
    db_archive|db_mobobrain) ;;
    *) echo "ERROR: 目标库必须是 db_archive 或 db_mobobrain"; exit 1 ;;
esac

command -v docker >/dev/null 2>&1 || { echo "ERROR: 缺少 docker"; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "ERROR: 缺少 sha256sum"; exit 1; }

cd "$COMPOSE_DIR"
[ -n "$(docker compose ps -q postgres 2>/dev/null || true)" ] || { echo "ERROR: postgres 未运行"; exit 1; }

psql_exec() {
    docker compose exec -T postgres psql -U "$PGUSER" -d "$TARGET_DB" -v ON_ERROR_STOP=1 "$@"
}

psql_value() {
    docker compose exec -T postgres psql -U "$PGUSER" -d "$TARGET_DB" -tAc "$1" | tr -d '[:space:]'
}

echo "[$(date '+%F %T')] 迁移目标：$TARGET_DB"

# 版本表（先于所有迁移）
psql_exec -c "
CREATE TABLE IF NOT EXISTS public.schema_migrations (
    version     TEXT PRIMARY KEY,
    description TEXT NOT NULL,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    checksum    TEXT NOT NULL
);" >/dev/null

shopt -s nullglob
FILES=("$SCRIPT_DIR"/*.sql)
shopt -u nullglob
if [ "${#FILES[@]}" -eq 0 ]; then
    echo "没有迁移文件"
    exit 0
fi

mapfile -t SORTED < <(printf '%s\n' "${FILES[@]}" | sort)

APPLIED=0
SKIPPED=0

for file in "${SORTED[@]}"; do
    base="$(basename "$file")"
    version="${base%%__*}"
    desc="${base#*__}"
    desc="${desc%.sql}"
    checksum="$(sha256sum "$file" | awk '{print $1}')"

    existing="$(psql_value "SELECT checksum FROM public.schema_migrations WHERE version='${version}'")"
    if [ -n "$existing" ]; then
        if [ "$existing" = "$checksum" ]; then
            echo "  [skip] $base"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
        echo "ERROR: $base 已执行但 checksum 变化（库=$existing，文件=$checksum）"
        echo "请新增迁移，不要修改已执行文件。"
        exit 1
    fi

    echo "  [apply] $base"
    if [ "$DRY_RUN" = "1" ]; then
        APPLIED=$((APPLIED + 1))
        continue
    fi

    TX=(-1)
    if grep -q -- '-- migrate:no-transaction' "$file"; then
        TX=()
        echo "         (no-transaction)"
    fi

    psql_exec "${TX[@]}" -f - < "$file"
    psql_exec -c "
        INSERT INTO public.schema_migrations (version, description, checksum)
        VALUES ('${version}', '${desc//\'/\'\'}', '${checksum}')
        ON CONFLICT (version) DO NOTHING;" >/dev/null
    APPLIED=$((APPLIED + 1))
done

echo "[$(date '+%F %T')] 完成：applied=$APPLIED skipped=$SKIPPED dry_run=$DRY_RUN"
