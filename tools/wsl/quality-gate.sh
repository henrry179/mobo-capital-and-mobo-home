#!/usr/bin/env bash
# =============================================================================
# 质量门（Quality Gate）Q0–Q14 · 正式投入开发部署前的硬闸门
# 用法（WSL 内）：
#   bash tools/wsl/quality-gate.sh
# 退出码：0 = 全部通过；1 = 存在 FAIL
#
# 约定：所有检查项以「退出码 0 = 通过」判定（shell 语义），避免自写脚本反判。
# =============================================================================
set -uo pipefail
export LANG=C.UTF-8 LC_ALL=C.UTF-8

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1

C="docker compose -f docker-compose.yml -f docker-compose.wsl.yml --env-file .env.local"
VENV="${MOBO_VENV:-/root/venv-mobo-cli}"
PASS=0; FAIL=0
ck() { if [ "$2" -eq 0 ]; then echo "  [PASS] $1"; PASS=$((PASS+1)); else echo "  [FAIL] $1"; FAIL=$((FAIL+1)); fi; }

git config --global --add safe.directory "$PROJECT_DIR" 2>/dev/null || true

echo "############ Q0 仓库与权限 ############"
git rev-parse --is-inside-work-tree >/dev/null 2>&1; ck "git 仓库可访问（safe.directory）" $?
echo "    未提交变更: $(git status --porcelain | wc -l)"

echo
echo "############ Q1 Shell 语法 ############"
n=0; bad=0
while IFS= read -r f; do n=$((n+1)); bash -n "$f" 2>/dev/null || { echo "    FAIL: $f"; bad=$((bad+1)); }; done < <(git ls-files '*.sh')
echo "    检查 $n 个脚本"
[ "$n" -gt 5 ] && [ "$bad" -eq 0 ]; ck "bash -n 全部通过" $?

echo
echo "############ Q2 工作流 JSON ############"
bad=0; for f in workflows/*.json; do node -e "JSON.parse(require('fs').readFileSync('$f','utf8'))" 2>/dev/null || { echo "    FAIL: $f"; bad=$((bad+1)); }; done
ck "工作流模板 JSON 全部可解析" "$bad"

echo
echo "############ Q3 Compose 编排 ############"
docker compose -f docker-compose.yml --env-file .env.local config >/dev/null 2>&1; ck "基础编排可解析" $?
docker compose -f docker-compose.yml -f docker-compose.local.yml --env-file .env.local config >/dev/null 2>&1; ck "本地覆盖可解析" $?
docker compose -f docker-compose.yml -f docker-compose.wsl.yml --env-file .env.local config >/dev/null 2>&1; ck "WSL 覆盖可解析" $?

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
process.exit(miss?1:0)"; ck "引用变量均在 .env.example 中" $?

echo
echo "############ Q5 密钥零入库 ############"
SECRET_RE='LTAI5t[A-Za-z0-9]{16,}|MoBo_(PgSuper|Capital|Home|Restic)[A-Za-z0-9_]{8,}|BEGIN OPENSSH'
hits=$(git grep -InE "$SECRET_RE" -- . 2>/dev/null | grep -vE 'REPLACE|xxxx' | wc -l | tr -d ' ')
git grep -InE "$SECRET_RE" -- . 2>/dev/null | grep -vE 'REPLACE|xxxx' | head -5 | sed 's/^/    /'
echo "    命中（排除占位符后）: $hits"
[ "$hits" -eq 0 ]; ck "无真实密钥入库（占位符除外）" $?

echo
echo "############ Q6 容器健康 ############"
for i in $(seq 1 40); do
  h=$($C ps --format '{{.Status}}' 2>/dev/null | grep -c 'healthy'); [ "$h" -ge 4 ] && break; sleep 3
done
tot=$($C ps -q 2>/dev/null | wc -l); healthy=$($C ps --format '{{.Status}}' 2>/dev/null | grep -c 'healthy')
unhealthy=$($C ps --format '{{.Status}}' 2>/dev/null | grep -c 'unhealthy')
echo "    容器=$tot healthy=$healthy unhealthy=$unhealthy"
$C ps --format 'table {{.Name}}\t{{.Status}}' 2>/dev/null | sed 's/^/    /'
[ "$tot" -ge 6 ] && [ "$healthy" -ge 4 ] && [ "$unhealthy" -eq 0 ]; ck "六容器运行、关键服务 healthy、无 unhealthy" $?

echo
echo "############ Q7 数据库冒烟 ############"
$C cp tests/sql/smoke.sql postgres:/tmp/smoke.sql >/dev/null 2>&1
out=$($C exec -T postgres psql -U postgres -d db_archive -v ON_ERROR_STOP=1 -f /tmp/smoke.sql 2>&1)
echo "$out" | grep -E '^(NOTICE|SMOKE)' | sed 's/^/    /' | tail -12
echo "$out" | grep -q 'SMOKE TEST PASSED'; ck "smoke.sql 全绿" $?

echo
echo "############ Q8 CLI 单测 ############"
(cd services/mobo-cli && "$VENV/bin/python" -m pytest tests -q >/tmp/mobo_qgate_cli.log 2>&1); rc=$?
tail -3 /tmp/mobo_qgate_cli.log | sed 's/^/    /'; ck "mobo-cli 单测通过" $rc

echo
echo "############ Q9 看板单测 ############"
(cd services/archive-dashboard && "$VENV/bin/python" -m pytest tests -q >/tmp/mobo_qgate_dash.log 2>&1); rc=$?
tail -3 /tmp/mobo_qgate_dash.log | sed 's/^/    /'; ck "archive-dashboard 单测通过" $rc

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
ck "公开站 200 / 受保护站 401→200" $ok
c=$(curl -sS --noproxy '*' -o /dev/null -w '%{http_code}' --max-time 8 -H 'Host: localhost' http://127.0.0.1/internal/internal-data.json 2>/dev/null)
ck "/internal/* 未认证 401" "$([ "$c" = "401" ] && echo 0 || echo 1)"

echo
echo "############ Q11 CLI 闭环与脱敏 ############"
"$VENV/bin/mobo-cli" --env-file .env.local doctor >/tmp/mobo_qgate_doctor.log 2>&1; rc=$?
grep -E '结果' /tmp/mobo_qgate_doctor.log | sed 's/^/    /'
ck "doctor FAIL=0" $rc
"$VENV/bin/mobo-cli" --env-file .env.local export-site --site all >/dev/null 2>&1; ck "export-site 产出数据包" $?
pv=$(grep -c 'private_blotter_oss_key\|oss_object_key' sites/mobocapital/data/public-data.json 2>/dev/null | head -1)
iv=$(grep -c '"INTERNAL"' sites/mobocapital/data/public-data.json 2>/dev/null | head -1)
echo "    公域包 私有字段=${pv:-0} INTERNAL=${iv:-0}"
[ "${pv:-0}" = "0" ] && [ "${iv:-0}" = "0" ]; ck "公域包 0 私有字段 / 0 INTERNAL" $?

echo
echo "############ Q12 内存红线 ############"
docker stats --no-stream --format '{{.Name}}|{{.MemUsage}}' 2>/dev/null | sed 's/^/    /'
TOT=$(docker stats --no-stream --format '{{.MemUsage}}' 2>/dev/null | awk -F' / ' '{split($1,a," "); v=a[1]+0; if (a[2] ~ /GiB/) v*=1024; else if (a[2] ~ /KiB/) v/=1024; s+=v} END {printf "%.0f", s}')
echo "    合计 ${TOT} MiB（红线 1550 MiB）"
[ "${TOT%%.*}" -lt 1550 ]; ck "常驻合计 < 1550 MiB" $?

echo
echo "############ Q13 迁移与备份机制 ############"
bash -n migrations/apply.sh 2>/dev/null && ls migrations/*.sql >/dev/null 2>&1; ck "迁移 runner 与迁移文件就绪" $?
bash -n deploy/backup/restore-drill.sh 2>/dev/null && bash -n deploy/backup/disaster-recovery.sh 2>/dev/null; ck "恢复/灾备脚本语法通过" $?

echo
echo "############ Q14 文档链接 ############"
node -e "
const fs=require('fs'),path=require('path');
let bad=0,n=0;
(function walk(d){for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);
 if(e.isDirectory()){if(!['.git','node_modules','证据'].includes(e.name))walk(p);}
 else if(e.name.endsWith('.md')){for(const m of fs.readFileSync(p,'utf8').matchAll(/\]\(([^)#][^)]*\.md)\)/g)){const t=path.resolve(path.dirname(p),m[1]);n++;if(!fs.existsSync(t)){console.log('    BROKEN '+p+' -> '+m[1]);bad++;}}}}})('.');
console.log('    检查 '+n+' 条相对链接');
process.exit(bad?1:0)"; ck "Markdown 相对链接 0 断链" $?

echo
echo "############################################################"
echo "  质量门：PASS=$PASS  FAIL=$FAIL"
echo "############################################################"
[ "$FAIL" -eq 0 ]
