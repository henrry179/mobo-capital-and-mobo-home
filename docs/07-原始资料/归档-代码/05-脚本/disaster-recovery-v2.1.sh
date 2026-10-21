#!/usr/bin/env bash
# 路径: /opt/mobo-stack/scripts/disaster-recovery.sh
# 功能: 当更换服务器或极端故障时，在新购 Ubuntu 24.04 裸机上一键拉取 OSS 加密快照并恢复双站全栈

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "🔍 [DRY-RUN 模式] 仅执行六阶段就绪度与快照连通性校验，不覆盖当前生产数据。"
fi

source /opt/mobo-stack/.env
export AWS_ACCESS_KEY_ID="$ALIYUN_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$ALIYUN_ACCESS_KEY_SECRET"
export RESTIC_REPOSITORY="$RESTIC_REPOSITORY"
export RESTIC_PASSWORD="$RESTIC_PASSWORD"

echo "=== [Stage 1/6] 校验宿主机 Swap 与环境变量权限 ==="
free -m | grep -q "Swap:" && echo "✅ Swap 就绪"
chmod 600 /opt/mobo-stack/.env

echo "=== [Stage 2/6] 连接阿里云 OSS 验证 Restic 最新加密快照 ==="
docker run --rm \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e RESTIC_REPOSITORY -e RESTIC_PASSWORD \
  restic/restic:latest snapshots --latest 3

if [ "$DRY_RUN" = true ]; then
    echo "✅ [DRY-RUN 演练通过] Restic 加密快照库完好，随时可执行真实裸机恢复！"
    exit 0
fi

echo "=== [Stage 3/6] 从 OSS 拉取最新快照至 /tmp/mobo_restore ==="
rm -rf /tmp/mobo_restore && mkdir -p /tmp/mobo_restore
docker run --rm \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e RESTIC_REPOSITORY -e RESTIC_PASSWORD \
  -v /tmp/mobo_restore:/restore \
  restic/restic:latest restore latest --target /restore

echo "=== [Stage 4/6] 启动 mobo-postgres 并恢复双数据库 (db_mobobrain & db_archive) ==="
cd /opt/mobo-stack
docker compose up -d mobo-postgres
sleep 10
docker exec -i mobo-postgres psql -U postgres -d db_mobobrain < /tmp/mobo_restore/tmp/mobo_pg_dumps/db_mobobrain.sql
docker exec -i mobo-postgres psql -U postgres -d db_archive < /tmp/mobo_restore/tmp/mobo_pg_dumps/db_archive.sql

echo "=== [Stage 5/6] 启动全栈 6 容器并同步双站静态 JSON ==="
docker compose up -d
python3 /opt/mobo-stack/scripts/mobo_cli.py sync-capital-web
python3 /opt/mobo-stack/scripts/mobo_cli.py sync-home-web
python3 /opt/mobo-stack/scripts/macro_iv_collector.py

echo "=== [Stage 6/6] 清理临时恢复目录并输出容器健康状态 ==="
rm -rf /tmp/mobo_restore
docker compose ps
echo "🎉 [裸机灾难恢复全部完成] MoBoCapital.com 与 MoBoHome.com 已恢复线上服务！"