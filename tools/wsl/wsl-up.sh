#!/usr/bin/env bash
# =============================================================================
# WSL2 本地全栈启动脚本（幂等）
#   1) 生成 Caddy BasicAuth 哈希 → 写入 .env.local
#   2) 校验 compose
#   3) 起 postgres（首次执行 01~09 初始化）
#   4) 跑 tests/sql/smoke.sql（9 组检查）
#   5) 起全栈六容器
#   6) 输出状态与内存占用
#
# 用法（WSL 内）：
#   cd /mnt/e/01-文档资料/报告与规划/莫伯双站系统 && bash tools/wsl/wsl-up.sh
# =============================================================================
set -uo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT" || { echo "找不到项目目录"; exit 1; }

COMPOSE="docker compose -f docker-compose.yml -f docker-compose.wsl.yml --env-file .env.local"
PASS="${LOCAL_PREVIEW_PASS:-mobo-local}"

if [ ! -f .env.local ]; then
  echo "[!] 未找到 .env.local，请先复制 .env.example 并按本地指南覆盖本地口令与 localhost 域名"
  exit 1
fi

echo "=== [1/6] 生成 Caddy BasicAuth 哈希（口令：$PASS）==="
if docker image inspect caddy:2.9-alpine >/dev/null 2>&1; then
  HASH=$(docker run --rm caddy:2.9-alpine caddy hash-password --plaintext "$PASS" 2>/dev/null | tr -d '\r')
  if [ -n "$HASH" ]; then
    sed -i "s|^CADDY_ADMIN_PASSWORD_HASH=.*|CADDY_ADMIN_PASSWORD_HASH='$HASH'|" .env.local
    echo "  已写入 .env.local"
  else
    echo "  生成失败，沿用占位符（BasicAuth 将不可用）"
  fi
else
  echo "  caddy 镜像未就绪，可稍后重跑本脚本自动补齐"
fi

echo
echo "=== [2/6] 校验 compose ==="
$COMPOSE config >/dev/null && echo "  compose config: OK" || { echo "  compose config: FAILED"; exit 1; }

echo
echo "=== [3/6] 启动 postgres（首次会执行 01~09 初始化）==="
$COMPOSE up -d postgres
echo "  等待就绪..."
for i in $(seq 1 90); do
  if $COMPOSE exec -T postgres pg_isready -U postgres >/dev/null 2>&1; then
    echo "  postgres 就绪（${i}s）"; break
  fi
  sleep 1
done
$COMPOSE logs postgres 2>/dev/null | grep -Ei 'FATAL|ERROR|initdb: error' | tail -5

echo
echo "=== [4/6] 数据库冒烟（tests/sql/smoke.sql）==="
$COMPOSE cp tests/sql/smoke.sql postgres:/tmp/smoke.sql >/dev/null 2>&1
$COMPOSE exec -T postgres psql -U postgres -d db_archive -v ON_ERROR_STOP=1 -f /tmp/smoke.sql 2>&1 | grep -E '^(NOTICE|SMOKE|psql:.*ERROR)' | head -25

echo
echo "=== [5/6] 启动全栈 ==="
$COMPOSE up -d 2>&1 | tail -8
sleep 10
$COMPOSE ps --format 'table {{.Name}}\t{{.Status}}' 2>/dev/null || $COMPOSE ps

echo
echo "=== [6/6] 内存占用（红线：合计 < 1.55GB）==="
docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}' 2>/dev/null
echo "--- 合计 ---"
docker stats --no-stream --format '{{.MemUsage}}' 2>/dev/null \
  | awk -F' / ' '{split($1,a,"m|MiB"); s+=a[1]} END {printf "  约 %.0f MiB\n", s}'

cat <<'DONE'

入口（Windows 浏览器与 WSL 内均可；BasicAuth：mobo / mobo-local）：
  http://localhost/            莫伯资本
  http://mobohome.localhost/    莫伯之家
  http://lab.localhost/         生命体征实验室
  http://kb.localhost/          思源笔记（另有思源访问码）
  http://n8n.localhost/         n8n
  http://admin.localhost/       操作台

提示：本机若配置了 http_proxy，命令行测试请加 --noproxy '*'。
DONE
