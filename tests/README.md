# 测试与校验

> 目标：让每次部署/迁移后能用 5–10 分钟证明“结构、触发器、权限、视图”都是对的。

## 目录

```text
tests/
├─ README.md            # 本文件
└─ sql/
   └─ smoke.sql         # 数据库结构 + 触发器 + 权限冒烟
```

## 1. 数据库冒烟

```bash
cd /opt/mobo-stack
docker compose cp tests/sql/smoke.sql postgres:/tmp/smoke.sql
docker compose exec -T postgres psql -U postgres -d db_archive \
  -v ON_ERROR_STOP=1 -f /tmp/smoke.sql
```

预期输出：各检查项 `OK`，最后 `SMOKE TEST PASSED`。任一项失败会以非零码退出。

覆盖范围：

- `db_archive`：8 表 + 3 视图存在。
- `db_mobobrain`：`intel` 5 表 + 1 视图、`n8n` Schema 存在。
- 4 个时间线同步触发器存在。
- 运动/阅读写入 → 时间线自动同步（事务内，结束回滚）。
- 周视图行数约 53。
- `user_dashboard_ro` 只读、`user_backup` 只读、应用账号权限正确。

## 2. Python 单测

```bash
# 看板
cd services/archive-dashboard
pip install -r requirements-dev.txt
pytest -q

# CLI
cd services/mobo-cli
pip install -e ".[dev]"
pytest -q
```

## 3. Shell 静态检查

```bash
# 语法（需要 bash）
bash -n deploy/backup/run-daily-backup.sh
bash -n deploy/backup/restore-drill.sh
bash -n deploy/backup/disaster-recovery.sh
bash -n deploy/scripts/host-hardening.sh
bash -n deploy/scripts/smoke-test.sh
bash -n migrations/apply.sh
```

## 4. Compose/Caddy 校验

```bash
docker compose config >/dev/null
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile
```

## 5. 上线全量验收

见 [`deploy/scripts/smoke-test.sh`](../deploy/scripts/smoke-test.sh) 与
[`docs/02-需求与验收/验收标准与DoD.md`](../docs/02-需求与验收/验收标准与DoD.md)。
