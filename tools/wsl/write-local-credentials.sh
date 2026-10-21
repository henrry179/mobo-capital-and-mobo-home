#!/usr/bin/env bash
set -uo pipefail
export LANG=C.UTF-8 LC_ALL=C.UTF-8
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1
ENV_FILE="${MOBO_ENV_FILE:-.env.local}"
[ -f "$ENV_FILE" ] || ENV_FILE=".env"

# 本地开发凭据（仅本地模式；文件被 .gitignore 忽略，不入库）
CODE=$(grep -E '^SIYUAN_ACCESS_AUTH_CODE=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'")
USER_NAME=$(grep -E '^CADDY_ADMIN_USER=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'")
mkdir -p services/console/data
cat > services/console/data/credentials.local.json <<JSON
{
  "note": "本地开发凭据；仅本地模式有效；本文件不入 Git（services/console/data/*.json 已被忽略）",
  "layers": [
    { "layer": "网关 BasicAuth", "where": "lab / n8n / kb / admin 域名的登录框", "username": "${USER_NAME:-mobo}", "password": "mobo-local" },
    { "layer": "思源 工作区访问码", "where": "思源 'lock screen password' 输入框", "password": "${CODE}" },
    { "layer": "n8n owner 账号", "where": "首次进入 n8n 的 Set up owner account", "password": "首次进入时自行设置（不预置）" }
  ],
  "public_sites": ["莫伯资本 http://localhost/", "莫博之家 http://mobohome.localhost/"]
}
JSON
echo "[credentials] 已写入 services/console/data/credentials.local.json"
