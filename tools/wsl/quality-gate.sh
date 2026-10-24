#!/usr/bin/env bash
# =============================================================================
# 质量门（Quality Gate）Q0–Q14 · 正式投入开发部署前的硬闸门
# 用法（WSL 内）：bash tools/wsl/quality-gate.sh
# 退出码：0 = 全部通过；1 = 存在 FAIL
# 副作用：把本次结果写入 services/console/data/gate.json（控制台展示，不入库）
# =============================================================================
set -uo pipefail
export LANG=C.UTF-8 LC_ALL=C.UTF-8

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1

C="docker compose -f docker-compose.yml -f docker-compose.wsl.yml --env-file .env.local"
VENV="${MOBO_VENV:-/root/venv-mobo-cli}"
# 日志落在项目内（已 gitignore）；项目目录不可写时退回到 mktemp。
# 早期版本写死 /tmp/mobo_qgate_*.log，非 root 运行时会被 root 残留文件挡住，
# 表现为"单测失败"的假象，故改为可写目录。
GATE_LOG_DIR="$PROJECT_DIR/tools/wsl/logs"
mkdir -p "$GATE_LOG_DIR" 2>/dev/null || GATE_LOG_DIR="$(mktemp -d)"
GATE_ITEMS=()
PASS=0; FAIL=0
ck() {
  local name="$1" code="$2"
  if [ "$code" -eq 0 ]; then
    echo "  [PASS] $name"; PASS=$((PASS+1)); GATE_ITEMS+=("PASS|$name")
  else
    echo "  [FAIL] $name"; FAIL=$((FAIL+1)); GATE_ITEMS+=("FAIL|$name")
  fi
}

git config --global --add safe.directory "$PROJECT_DIR" 2>/dev/null || true
mkdir -p services/console/data

echo "############ Q0 仓库与权限 ############"
git rev-parse --is-inside-work-tree >/dev/null 2>&1; ck "Q0 仓库可访问（safe.directory）" $?

# 预检：CLI venv 是否可用。本地优先模式的 venv 默认在 /root/venv-mobo-cli（仅 root 可读），
# 非 root 运行会表现为"单测失败"的假象，这里提前把话说清楚。
if [ ! -x "$VENV/bin/python" ]; then
  echo "    [!] 不可用的 CLI venv：$VENV"
  echo "    [!] 请用 root 执行：wsl -u root -e bash -lc \"bash tools/wsl/quality-gate.sh\""
  echo "    [!] 或用 MOBO_VENV=/path/to/venv 指定当前用户可读的 venv"
fi

echo
echo "############ Q1 Shell 语法 ############"
n=0; bad=0
while IFS= read -r f; do n=$((n+1)); bash -n "$f" 2>/dev/null || { echo "    FAIL: $f"; bad=$((bad+1)); }; done < <(git ls-files '*.sh')
echo "    检查 $n 个脚本"
[ "$n" -gt 5 ] && [ "$bad" -eq 0 ]; ck "Q1 bash -n 全部通过" $?

echo
echo "############ Q2 工作流 JSON ############"
bad=0; for f in workflows/*.json; do node -e "JSON.parse(require('fs').readFileSync('$f','utf8'))" 2>/dev/null || { echo "    FAIL: $f"; bad=$((bad+1)); }; done
ck "Q2 工作流模板 JSON 可解析" "$bad"

echo
echo "############ Q3 Compose 编排 ############"
docker compose -f docker-compose.yml --env-file .env.local config >/dev/null 2>&1; ck "Q3 基础编排可解析" $?
docker compose -f docker-compose.yml -f docker-compose.local.yml --env-file .env.local config >/dev/null 2>&1; ck "Q3 本地覆盖可解析" $?
docker compose -f docker-compose.yml -f docker-compose.wsl.yml --env-file .env.local config >/dev/null 2>&1; ck "Q3 WSL 覆盖可解析" $?

echo
echo "############ Q4 环境变量对齐 ############"
node -e "
const fs=require('fs');
const env=new Set(fs.readFileSync('.env.example','utf8').split('\n').map(l=>l.trim()).filter(l=>l&&!l.startsWith('#')&&l.includes('=')).map(l=>l.split('=')[0]));
let miss=0;
for (const f of ['docker-compose.yml','docker-compose.local.yml','docker-compose.wsl.yml','deploy/caddy/Caddyfile']) {
  const s=[...new Set([...fs.readFileSync(f,'utf8').matchAll(/\\\$\{([A-Z0-9_]+)[^}]*\}/g)].map(m=>m[1]))].filter(v=>!env.has(v));
  if (s.length) { console.log('    MISSING '+f+': '+s.join(',')); miss+=s.length; }
}
process.exit(miss?1:0)"; ck "Q4 引用变量均在 .env.example 中" $?

echo
echo "############ Q5 密钥零入库 ############"
SECRET_RE='LTAI5t[A-Za-z0-9]{16,}|MoBo_(PgSuper|Capital|Home|Restic)[A-Za-z0-9_]{8,}|BEGIN OPENSSH'
SCAN_PATHS=(-- . ':!tools/wsl/quality-gate.sh')
hits=$(git grep -InE "$SECRET_RE" -- "${SCAN_PATHS[@]}" 2>/dev/null | grep -vE 'REPLACE|xxxx' | wc -l | tr -d ' ')
git grep -InE "$SECRET_RE" -- "${SCAN_PATHS[@]}" 2>/dev/null | grep -vE 'REPLACE|xxxx' | head -5 | sed 's/^/    /'
echo "    命中（排除占位符与本脚本）: $hits"
[ "$hits" -eq 0 ]; ck "Q5 无真实密钥入库" $?

echo
echo "############ Q6 容器健康 ############"
for i in $(seq 1 40); do
  h=$($C ps --format '{{.Status}}' 2>/dev/null | grep -c 'healthy'); [ "$h" -ge 4 ] && break; sleep 3
done
tot=$($C ps -q 2>/dev/null | wc -l); healthy=$($C ps --format '{{.Status}}' 2>/dev/null | grep -c 'healthy')
unhealthy=$($C ps --format '{{.Status}}' 2>/dev/null | grep -c 'unhealthy')
echo "    容器=$tot healthy=$healthy unhealthy=$unhealthy"
[ "$tot" -ge 6 ] && [ "$healthy" -ge 4 ] && [ "$unhealthy" -eq 0 ]; ck "Q6 六容器运行、无 unhealthy" $?

echo
echo "############ Q7 数据库冒烟 ############"
$C cp tests/sql/smoke.sql postgres:/tmp/smoke.sql >/dev/null 2>&1
out=$($C exec -T postgres psql -U postgres -d db_archive -v ON_ERROR_STOP=1 -f /tmp/smoke.sql 2>&1)
echo "$out" | grep -q 'SMOKE TEST PASSED'; ck "Q7 smoke.sql 全绿" $?

echo
echo "############ Q8 CLI 单测 ############"
(cd services/mobo-cli && "$VENV/bin/python" -m pytest tests -q >"$GATE_LOG_DIR/mobo_qgate_cli.log" 2>&1); rc=$?
tail -2 "$GATE_LOG_DIR/mobo_qgate_cli.log" | sed 's/^/    /'; ck "Q8 mobo-cli 单测通过" $rc

echo
echo "############ Q9 看板单测 ############"
(cd services/archive-dashboard && "$VENV/bin/python" -m pytest tests -q >"$GATE_LOG_DIR/mobo_qgate_dash.log" 2>&1); rc=$?
tail -2 "$GATE_LOG_DIR/mobo_qgate_dash.log" | sed 's/^/    /'; ck "Q9 archive-dashboard 单测通过" $rc

echo
echo "############ Q10 网关入口与鉴权 ############"
ok=0
for h in localhost mobohome.localhost; do
  c=$(curl -sS --noproxy '*' -o /dev/null -w '%{http_code}' --max-time 8 -H "Host: $h" http://127.0.0.1/ 2>/dev/null)
  [ "$c" = "200" ] || { ok=1; echo "    $h -> $c"; }
done
for h in lab.localhost n8n.localhost admin.localhost; do
  c1=$(curl -sS --noproxy '*' -o /dev/null -w '%{http_code}' --max-time 10 -H "Host: $h" http://127.0.0.1/ 2>/dev/null)
  c2=$(curl -sS --noproxy '*' -o /dev/null -w '%{http_code}' --max-time 10 -u mobo:mobo-local -H "Host: $h" http://127.0.0.1/ 2>/dev/null)
  { [ "$c1" = "401" ] && [ "$c2" = "200" ]; } || { ok=1; echo "    $h 未认证=$c1 认证=$c2"; }
done
ck "Q10 公开站 200 / 受保护站 401→200" $ok
c=$(curl -sS --noproxy '*' -o /dev/null -w '%{http_code}' --max-time 8 -H 'Host: localhost' http://127.0.0.1/internal/internal-data.json 2>/dev/null)
[ "$c" = "401" ]; ck "Q10 /internal/* 未认证 401" $?

echo
echo "############ Q10b 控制台数据面 ############"
c=$(curl -sS --noproxy '*' -o /dev/null -w '%{http_code}' --max-time 8 -u mobo:mobo-local -H 'Host: admin.localhost' http://127.0.0.1/api/capital/data/public-data.json 2>/dev/null)
echo "    /api/capital/data/public-data.json -> $c"
[ "$c" = "200" ]; ck "Q10b 控制台可读取两站脱敏数据" $?

echo
echo "############ Q11 CLI 闭环与脱敏 ############"
"$VENV/bin/mobo-cli" --env-file .env.local doctor >"$GATE_LOG_DIR/mobo_qgate_doctor.log" 2>&1; rc=$?
grep -E '结果' "$GATE_LOG_DIR/mobo_qgate_doctor.log" | sed 's/^/    /'
ck "Q11 doctor FAIL=0" $rc
"$VENV/bin/mobo-cli" --env-file .env.local export-site --site all >/dev/null 2>&1; ck "Q11 export-site 产出数据包" $?
pv=$(grep -c 'private_blotter_oss_key\|oss_object_key' sites/mobocapital/data/public-data.json 2>/dev/null | head -1)
iv=$(grep -c '"INTERNAL"' sites/mobocapital/data/public-data.json 2>/dev/null | head -1)
echo "    公域包 私有字段=${pv:-0} INTERNAL=${iv:-0}"
[ "${pv:-0}" = "0" ] && [ "${iv:-0}" = "0" ]; ck "Q11 公域包 0 私有字段 / 0 INTERNAL" $?

echo
echo "############ Q12 内存红线 ############"
docker stats --no-stream --format '{{.Name}}|{{.MemUsage}}' 2>/dev/null | sed 's/^/    /'
TOT=$(docker stats --no-stream --format '{{.MemUsage}}' 2>/dev/null | awk -F' / ' '{split($1,a," "); v=a[1]+0; if (a[2] ~ /GiB/) v*=1024; else if (a[2] ~ /KiB/) v/=1024; s+=v} END {printf "%.0f", s}')
echo "    合计 ${TOT} MiB（红线 1550 MiB）"
[ "${TOT%%.*}" -lt 1550 ]; ck "Q12 常驻合计 < 1550 MiB" $?

echo
echo "############ Q13 迁移与备份机制 ############"
bash -n migrations/apply.sh 2>/dev/null && ls migrations/*.sql >/dev/null 2>&1; ck "Q13 迁移 runner 与迁移文件就绪" $?
bash -n deploy/backup/restore-drill.sh 2>/dev/null && bash -n deploy/backup/disaster-recovery.sh 2>/dev/null; ck "Q13 恢复/灾备脚本语法通过" $?

echo
echo "############ Q14 文档链接 ############"
# 原料仓（五大夹）是待迁移的**内容资产**，不是项目文档：占 4.4 万文件、含第三方仓库自带
# 的历史 Markdown，扫它们的相对链接会产生上万条假断链。
# 详见 docs/07-原始资料/内容原料仓深度整合与整理方案-v2.md（Phase P9）。
node -e "
const fs=require('fs'),path=require('path');
const SKIP=['.git','node_modules','证据','01-工作与项目','hermes-migration','AIGC原稿','ITPM原稿内容','ReadingBooks'];
let bad=0,n=0;
(function walk(d){for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);
 if(e.isDirectory()){if(!SKIP.includes(e.name))walk(p);}
 else if(e.name.endsWith('.md')){for(const m of fs.readFileSync(p,'utf8').matchAll(/\]\(([^)#][^)]*\.md)\)/g)){const t=path.resolve(path.dirname(p),m[1]);n++;if(!fs.existsSync(t)){console.log('    BROKEN '+p+' -> '+m[1]);bad++;}}}}})('.');
console.log('    检查 '+n+' 条相对链接');
process.exit(bad?1:0)"; ck "Q14 Markdown 相对链接 0 断链" $?

# ---- 写入门禁结果（控制台展示用）----
{
  printf '{\n  "at": "%s",\n  "pass": %d,\n  "fail": %d,\n  "items": [\n' \
    "$(date -Iseconds)" "$PASS" "$FAIL"
  first=1
  for item in "${GATE_ITEMS[@]}"; do
    st="${item%%|*}"; nm="${item#*|}"
    [ $first -eq 0 ] && printf ',\n'
    first=0
    printf '    { "id": "%s", "name": "%s", "ok": %s }' \
      "$(echo "$nm" | sed -E 's/^(Q[0-9]+[a-z]?) .*/\1/')" "$nm" \
      "$([ "$st" = "PASS" ] && echo true || echo false)"
  done
  printf '\n  ]\n}\n'
} > services/console/data/gate.json 2>/dev/null || true

echo
echo "############ Q15 控制台数据契约 ############"
node services/console/tests/contract-check.mjs 2>&1 | sed 's/^/    /'
node services/console/tests/contract-check.mjs >/dev/null 2>&1; ck "Q15 控制台数据契约满足（页面不空白的静态保证）" $?

echo
echo "############ Q16 本地凭据文件不入库 ############"
if git ls-files --error-unmatch services/console/data/credentials.local.json >/dev/null 2>&1; then
  echo "    警告：凭据文件被 Git 跟踪"
  ck "Q16 credentials.local.json 未入库" 1
else
  ck "Q16 credentials.local.json 未入库" 0
fi

echo
echo "############ Q17 看板四模块真数据 ############"
$C cp tests/sql/dashboard-real-data.sql postgres:/tmp/dashboard-real-data.sql >/dev/null 2>&1
dout=$($C exec -T postgres psql -U postgres -d db_archive -t -A -f /tmp/dashboard-real-data.sql 2>&1)
echo "$dout" | grep -v '^$' | sed 's/^/    /'
echo "$dout" | grep -q 'DASHBOARD REAL DATA OK'; ck "Q17 看板四模块数据源有真实行（非内存沙盒）" $?
denv=$(docker exec archive-dashboard env 2>/dev/null | grep -c '^PG_PASS_ARCHIVE=' || true)
echo "    archive-dashboard 注入 PG_PASS_ARCHIVE：${denv}"
[ "${denv:-0}" -ge 1 ]; ck "Q17 看板容器已注入数据库凭据" $?

echo
echo "############ Q18 量化终端采集器与 Cron 接线 ############"
"$VENV/bin/python" services/mobo-cli/collectors/macro_iv_collector.py --env-file .env.local --check >"$GATE_LOG_DIR/mobo_qgate_collector.log" 2>&1
rc=$?
tail -6 "$GATE_LOG_DIR/mobo_qgate_collector.log" | sed 's/^/    /'
ck "Q18 采集器可连通 db_mobobrain（PG_* 口径正确）" $rc
if command -v crontab >/dev/null 2>&1; then
  if crontab -l 2>/dev/null | grep -q 'macro_iv_collector.py'; then
    echo "    crontab 已包含 macro_iv_collector.py 条目"
    ck "Q18 采集器已接本地 Cron" 0
  else
    echo "    缺失：请执行 bash tools/wsl/install-local-cron.sh"
    ck "Q18 采集器已接本地 Cron" 1
  fi
else
  echo "    WARN：本机无 crontab 命令，跳过 Cron 接线检查"
fi

echo
echo "############################################################"
echo "  质量门：PASS=$PASS  FAIL=$FAIL"
echo "############################################################"
[ "$FAIL" -eq 0 ]
