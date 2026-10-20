#!/usr/bin/env bash
# =============================================================================
# 上线冒烟测试：容器 / HTTP 鉴权 / 数据库 / Restic / 资源
# 用法：在项目根目录执行 ./deploy/scripts/smoke-test.sh
# 可选：
#   SKIP_HTTP=1        无 DNS/证书时跳过 HTTP 检查
#   INSECURE=1         本地自签证书时 curl -k
#   SKIP_RESTIC=1      首次备份前跳过快照检查
# =============================================================================
set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
COMPOSE_DIR="$(pwd)"

PASS=0
FAIL=0
WARN=0

ok()   { PASS=$((PASS+1)); echo "  [PASS] $*"; }
bad()  { FAIL=$((FAIL+1)); echo "  [FAIL] $*"; }
warn() { WARN=$((WARN+1)); echo "  [WARN] $*"; }

# 载入 .env
if [ ! -f .env ]; then
    echo "ERROR: 缺少 .env；先 cp .env.example .env 并填写"
    exit 1
fi
set -a
# shellcheck disable=SC1091
. ./.env
set +a

: "${POSTGRES_SUPER_USER:?缺少 POSTGRES_SUPER_USER}"
: "${ARCHIVE_DB_NAME:?缺少 ARCHIVE_DB_NAME}"
: "${MOBOBRAIN_DB_NAME:?缺少 MOBOBRAIN_DB_NAME}"

CURL_OPTS=(-sS -o /dev/null -w '%{http_code}' --max-time 10)
CURL_HEADER=(-sS -I --max-time 10)
[ "${INSECURE:-0}" = "1" ] && CURL_OPTS+=(-k) && CURL_HEADER+=(-k)

echo "============================================================"
echo " 莫伯双站 Smoke Test"
echo " 目录: $COMPOSE_DIR"
echo " 时间: $(date '+%F %T %Z')"
echo "============================================================"

# -----------------------------------------------------------------------------
# 1. Compose / 容器
# -----------------------------------------------------------------------------
echo
echo "[1] Compose 与容器"
if docker compose config >/dev/null 2>&1; then
    ok "docker compose config"
else
    bad "docker compose config 失败"
fi

EXPECTED_SERVICES=(caddy postgres mobobrain-pkm mobobrain-n8n archive-dashboard restic-backup)
for svc in "${EXPECTED_SERVICES[@]}"; do
    cid="$(docker compose ps -q "$svc" 2>/dev/null || true)"
    if [ -z "$cid" ]; then
        bad "$svc 未运行"
        continue
    fi
    status="$(docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || echo unknown)"
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid" 2>/dev/null || echo none)"
    if [ "$status" = "running" ] && { [ "$health" = "healthy" ] || [ "$health" = "none" ]; }; then
        ok "$svc running ($health)"
    else
        bad "$svc status=$status health=$health"
    fi
done

# -----------------------------------------------------------------------------
# 2. HTTP / 鉴权
# -----------------------------------------------------------------------------
echo
echo "[2] HTTP 与鉴权"
if [ "${SKIP_HTTP:-0}" = "1" ]; then
    warn "SKIP_HTTP=1，跳过 HTTP"
else
    check_code() {
        local name="$1" url="$2" expected="$3"
        local code
        code="$(curl "${CURL_OPTS[@]}" "$url" 2>/dev/null || echo 000)"
        if [ "$code" = "$expected" ]; then
            ok "$name -> $code"
        else
            bad "$name -> $code（期望 $expected）"
        fi
    }

    check_code "www 公开站" "https://${DOMAIN_WWW}/" "200"
    check_code "kb 知识库匿名" "https://${DOMAIN_KB}/" "401"
    check_code "n8n 匿名" "https://${DOMAIN_N8N}/" "401"
    check_code "archive 匿名" "https://${DOMAIN_ARCHIVE}/" "401"
    check_code "admin 匿名" "https://${DOMAIN_ADMIN}/" "401"

    if curl "${CURL_HEADER[@]}" "https://${DOMAIN_ARCHIVE}/" 2>/dev/null | grep -qi 'x-robots-tag:.*noindex'; then
        ok "archive noindex"
    else
        bad "archive 缺少 X-Robots-Tag: noindex"
    fi
fi

# -----------------------------------------------------------------------------
# 3. 数据库结构
# -----------------------------------------------------------------------------
echo
echo "[3] 数据库"
PG_EXEC=(docker compose exec -T postgres psql -U "$POSTGRES_SUPER_USER" -v ON_ERROR_STOP=1)

if "${PG_EXEC[@]}" -d postgres -tAc "SELECT 1" >/dev/null 2>&1; then
    ok "Postgres 可连接"
else
    bad "Postgres 不可连接"
fi

for db in "$MOBOBRAIN_DB_NAME" "$ARCHIVE_DB_NAME"; do
    if "${PG_EXEC[@]}" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${db}'" | grep -q 1; then
        ok "数据库存在：$db"
    else
        bad "数据库缺失：$db"
    fi
done

for tbl in timeline_events entity_links reading_items reading_logs fitness_workouts fitness_biometrics project_retrospectives archive_assets; do
    if "${PG_EXEC[@]}" -d "$ARCHIVE_DB_NAME" -tAc "SELECT to_regclass('archive.${tbl}') IS NOT NULL" | grep -q t; then
        ok "archive.$tbl"
    else
        bad "archive.$tbl 缺失"
    fi
done

for tbl in sources articles_vault content_drafts ingestion_runs llm_usage; do
    if "${PG_EXEC[@]}" -d "$MOBOBRAIN_DB_NAME" -tAc "SELECT to_regclass('intel.${tbl}') IS NOT NULL" | grep -q t; then
        ok "intel.$tbl"
    else
        bad "intel.$tbl 缺失"
    fi
done

if "${PG_EXEC[@]}" -d "$ARCHIVE_DB_NAME" -tAc "SELECT count(*) FROM archive.v_weekly_life_analytics" >/dev/null 2>&1; then
    ok "v_weekly_life_analytics 可查询"
else
    bad "v_weekly_life_analytics 查询失败"
fi

TRIGGERS="$("${PG_EXEC[@]}" -d "$ARCHIVE_DB_NAME" -tAc "
SELECT count(*) FROM pg_trigger
WHERE tgrelid IN ('archive.reading_items'::regclass,
                  'archive.reading_logs'::regclass,
                  'archive.fitness_workouts'::regclass,
                  'archive.project_retrospectives'::regclass)
  AND NOT tgisinternal;")"
if [ "${TRIGGERS:-0}" -ge 4 ]; then
    ok "时间线触发器数量：$TRIGGERS"
else
    bad "时间线触发器不足：$TRIGGERS"
fi

# 触发器幂等快速验证（在事务中回滚，不污染生产）
if "${PG_EXEC[@]}" -d "$ARCHIVE_DB_NAME" >/dev/null 2>&1 <<'SQL'
BEGIN;
INSERT INTO archive.reading_items (title, status, domain, finished_at)
VALUES ('smoke-test-book', 'COMPLETED', 'LEARNING_EXAM', CURRENT_DATE)
RETURNING item_id \gset
INSERT INTO archive.reading_logs (item_id, log_type, duration_minutes, start_page, end_page)
VALUES (:'item_id', 'SESSION', 30, 1, 20);
SELECT count(*) FROM archive.timeline_events
WHERE source_table = 'reading_items' AND source_id = :'item_id';
ROLLBACK;
SQL
then
    ok "完读触发器/阅读日志触发器可执行（已回滚）"
else
    bad "触发器幂等测试失败"
fi

# -----------------------------------------------------------------------------
# 4. Restic
# -----------------------------------------------------------------------------
echo
echo "[4] Restic"
if [ "${SKIP_RESTIC:-0}" = "1" ]; then
    warn "SKIP_RESTIC=1，跳过"
else
    if docker compose exec -T restic-backup restic snapshots --latest 1 >/dev/null 2>&1; then
        ok "Restic 快照可读"
    else
        warn "Restic 快照不可读（首次备份前正常）"
    fi
fi

# -----------------------------------------------------------------------------
# 5. 资源
# -----------------------------------------------------------------------------
echo
echo "[5] 资源"
docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}' 2>/dev/null || true
if command -v free >/dev/null 2>&1; then
    free -m | sed -n '1,3p'
fi
if command -v df >/dev/null 2>&1; then
    df -h / | tail -n 1
fi

# -----------------------------------------------------------------------------
# 6. 可选 CLI
# -----------------------------------------------------------------------------
echo
echo "[6] CLI"
if command -v mobo-cli >/dev/null 2>&1; then
    if mobo-cli doctor >/dev/null 2>&1; then
        ok "mobo-cli doctor"
    else
        warn "mobo-cli doctor 有告警/失败（可能未配置本地 DB）"
    fi
else
    warn "未安装 mobo-cli，跳过"
fi

echo
echo "============================================================"
echo " 结果：PASS=$PASS  FAIL=$FAIL  WARN=$WARN"
echo "============================================================"
[ "$FAIL" -eq 0 ]
