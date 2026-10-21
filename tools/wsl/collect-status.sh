#!/usr/bin/env bash
# =============================================================================
# 收集运行时状态 → services/console/data/status.json（控制台数据源）
# 用法（WSL 内）：bash tools/wsl/collect-status.sh
# 幂等：每次覆盖写；文件被 .gitignore 忽略，不入库
# =============================================================================
set -uo pipefail
export LANG=C.UTF-8 LC_ALL=C.UTF-8

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1

ENV_FILE="${MOBO_ENV_FILE:-.env.local}"
[ -f "$ENV_FILE" ] || ENV_FILE=".env"
C="docker compose -f docker-compose.yml -f docker-compose.wsl.yml --env-file $ENV_FILE"
OUT="services/console/data/status.json"
mkdir -p "$(dirname "$OUT")"

# 从 env 文件取域名（本地默认走 *.localhost）
dom() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' ; }
DOM_CAP="${DOM_CAPITAL:-$(dom DOMAIN_CAPITAL)}"; DOM_CAP="${DOM_CAP:-localhost}"
DOM_HOME="${DOM_HOME:-$(dom DOMAIN_HOME)}";      DOM_HOME="${DOM_HOME:-mobohome.localhost}"
DOM_PKM="${DOM_PKM:-$(dom DOMAIN_PKM)}";        DOM_PKM="${DOM_PKM:-kb.localhost}"
DOM_N8N="${DOM_N8N:-$(dom DOMAIN_N8N)}";        DOM_N8N="${DOM_N8N:-n8n.localhost}"
DOM_LAB="${DOM_LAB:-$(dom DOMAIN_LAB)}";        DOM_LAB="${DOM_LAB:-lab.localhost}"
DOM_ADM="${DOM_ADMIN:-$(dom DOMAIN_ADMIN)}";    DOM_ADM="${DOM_ADMIN:-admin.localhost}"

probe() { # name url host expect
  local name="$1" url="$2" host="$3" auth="$4" code
  code=$(curl -sS --noproxy '*' -o /dev/null -w '%{http_code}' --max-time 6 -H "Host: $host" "$url" 2>/dev/null)
  printf '%s\t%s\t%s\t%s\n' "$name" "http://$host/" "$auth" "${code:-000}"
}

echo "[collect] 探测入口…"
{
  probe "莫伯资本 主站" "http://127.0.0.1/" "$DOM_CAP" "公开"
  probe "莫伯之家 主站" "http://127.0.0.1/" "$DOM_HOME" "公开"
  probe "思源 知识库" "http://127.0.0.1/" "$DOM_PKM" "BasicAuth"
  probe "n8n 自动化" "http://127.0.0.1/" "$DOM_N8N" "BasicAuth"
  probe "生命体征 实验室" "http://127.0.0.1/" "$DOM_LAB" "BasicAuth"
  probe "莫伯系统 控制台" "http://127.0.0.1/" "$DOM_ADM" "BasicAuth"
} > /tmp/mobo_services.tsv

echo "[collect] 读取容器状态…"
CONTAINERS=$($C ps --format '{{.Name}}|{{.Status}}' 2>/dev/null)
MEM_LINES=$(docker stats --no-stream --format '{{.Name}}|{{.MemUsage}}|{{.MemPerc}}' 2>/dev/null)

echo "[collect] 读取数据库计数…"
db_count() { $C exec -T postgres psql -U postgres -d "$1" -tAc "$2" 2>/dev/null | tr -d '[:space:]'; }
DB_TIMELINE=$(db_count db_archive "SELECT count(*) FROM archive.timeline_events;")
DB_ASSETS=$(db_count db_archive "SELECT count(*) FROM archive.archive_assets;")
DB_BOOKS=$(db_count db_archive "SELECT count(*) FROM archive.reading_items;")
DB_TRADES=$(db_count db_mobobrain "SELECT count(*) FROM capital.trade_reviews;")
DB_THESES=$(db_count db_mobobrain "SELECT count(*) FROM capital.macro_theses;")
DB_PUBS=$(db_count db_mobobrain "SELECT count(*) FROM capital.capital_publications;")
DB_PENDING=$(db_count db_mobobrain "SELECT count(*) FROM capital.capital_publications WHERE publish_status='PENDING_REVIEW';")
DB_ARTICLES=$(db_count db_mobobrain "SELECT count(*) FROM intel.articles_vault;")
DB_DRAFTS=$(db_count db_mobobrain "SELECT count(*) FROM intel.content_drafts;")
DB_INGEST=$(db_count db_mobobrain "SELECT count(*) FROM intel.ingestion_runs;")
NAV_JSON=$($C exec -T postgres psql -U postgres -d db_mobobrain -tAc \
  "SELECT row_to_json(t) FROM (SELECT valuation_date, gross_nav, high_water_mark, net_nav, current_drawdown_pct, cumulative_r_multiple, risk_regime_status FROM capital.portfolio_nav_ledger ORDER BY created_at DESC LIMIT 1) t;" 2>/dev/null | tr -d '[:space:]')

echo "[collect] 读取备份快照…"
BACKUP_LAST=""
BACKUP_AGE=""
if [ -f "$ENV_FILE" ]; then
  REPO=$(grep -E '^RESTIC_REPOSITORY=' "$ENV_FILE" | cut -d= -f2- | tr -d '"')
  RPASS=$(grep -E '^RESTIC_PASSWORD=' "$ENV_FILE" | cut -d= -f2- | tr -d '"')
  if [ -n "$REPO" ] && [ -d /backup ] || [ -n "$REPO" ]; then
    SNAP=$($C exec -T restic-backup sh -c "RESTIC_REPOSITORY='$REPO' RESTIC_PASSWORD='$RPASS' restic snapshots --latest 1 --json" 2>/dev/null | head -c 400)
    BACKUP_LAST=$(echo "$SNAP" | sed -n 's/.*"time":"\([^"]*\)".*/\1/p' | head -1)
    BACKUP_AGE=$(echo "$SNAP" | sed -n 's/.*"short_id":"\([^"]*\)".*/\1/p' | head -1)
  fi
fi

GIT_COMMIT=$(git rev-parse HEAD 2>/dev/null | head -1)
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | head -1)
GIT_DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

DISK_PCT=$(df / | awk 'NR==2 {gsub("%",""); print $5}')
MEM_TOTAL=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
MEM_AVAIL=$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo)
MEM_USED=$((MEM_TOTAL - MEM_AVAIL))

export DISK_PCT MEM_TOTAL MEM_USED GIT_COMMIT GIT_BRANCH GIT_DIRTY
export DB_TIMELINE DB_ASSETS DB_BOOKS DB_TRADES DB_THESES DB_PUBS DB_PENDING DB_ARTICLES DB_DRAFTS DB_INGEST
export BACKUP_LAST BACKUP_AGE

python3 - "$OUT" "$CONTAINERS" "$MEM_LINES" <<'PY'
import json, sys, os, re
out, containers, mem_lines = sys.argv[1], sys.argv[2], sys.argv[3]

def parse_mem(v):
    m = re.match(r"([\d.]+)\s*([KMG]i?B)", v)
    if not m: return 0.0
    n, u = float(m.group(1)), m.group(2)
    return n * (1024 if u.startswith('G') else 1)

cont = []
for line in (containers or '').splitlines():
    if '|' not in line: continue
    name, status = line.split('|', 1)
    cont.append({'name': name, 'status': status.strip(), 'healthy': 'healthy' in status})

mem_map = {}
for line in (mem_lines or '').splitlines():
    parts = line.split('|')
    if len(parts) == 3:
        mem_map[parts[0]] = (parts[1], float(parts[2].replace('%', '')))

for c in cont:
    usage, pct = mem_map.get(c['name'], ('0MiB', 0.0))
    c['mem'] = usage
    c['mem_pct'] = pct

total_used = sum(parse_mem(v[0]) for v in mem_map.values())

data = {
    'generated_at': __import__('datetime').datetime.now().astimezone().isoformat(),
    'mode': 'local-wsl',
    'containers': cont,
    'memory': {'used_mib': round(total_used), 'limit_mib': 1550},
    'host': {
        'disk_used_pct': int(os.environ.get('DISK_PCT', 0) or 0),
        'mem_total_mib': int(os.environ.get('MEM_TOTAL', 0) or 0),
        'mem_used_mib': int(os.environ.get('MEM_USED', 0) or 0),
    },
    'git': {
        'commit': os.environ.get('GIT_COMMIT', ''),
        'branch': os.environ.get('GIT_BRANCH', ''),
        'dirty': int(os.environ.get('GIT_DIRTY', 0) or 0),
    },
    'db': {
        'timeline_events': int(os.environ.get('DB_TIMELINE', 0) or 0),
        'archive_assets': int(os.environ.get('DB_ASSETS', 0) or 0),
        'reading_items': int(os.environ.get('DB_BOOKS', 0) or 0),
        'trade_reviews': int(os.environ.get('DB_TRADES', 0) or 0),
        'macro_theses': int(os.environ.get('DB_THESES', 0) or 0),
        'publications': int(os.environ.get('DB_PUBS', 0) or 0),
        'pending_review': int(os.environ.get('DB_PENDING', 0) or 0),
        'articles': int(os.environ.get('DB_ARTICLES', 0) or 0),
        'drafts': int(os.environ.get('DB_DRAFTS', 0) or 0),
        'ingestion_runs': int(os.environ.get('DB_INGEST', 0) or 0),
    },
    'backup': {
        'last_snapshot': os.environ.get('BACKUP_LAST', ''),
        'id': os.environ.get('BACKUP_AGE', ''),
    },
}

svcs = []
svc_file = '/tmp/mobo_services.tsv'
if os.path.exists(svc_file):
    for line in open(svc_file, encoding='utf-8'):
        p = line.rstrip('\n').split('\t')
        if len(p) == 4:
            svcs.append({'name': p[0], 'url': p[1], 'auth': p[2], 'code': int(p[3]) if p[3].isdigit() else 0})
data['services'] = svcs

gate_path = 'services/console/data/gate.json'
if os.path.exists(gate_path):
    try:
        data['gate'] = json.load(open(gate_path, encoding='utf-8'))
    except Exception:
        pass

with open(out, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
print(f'[collect] 已写入 {out}')
PY
