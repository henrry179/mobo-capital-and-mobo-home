# 沙盒与示例数据

> 仅用于本地开发、看板演示、SQL Smoke Test。**不要在生产库执行。**

## 文件

| 文件 | 内容 |
|---|---|
| `52-week-sandbox.sql` | 365 天生理基线、52 周训练、52 周复盘、12 本书与阅读日志 |

## 执行

```bash
# 确认是本地/演练库
docker compose exec -T postgres psql -U postgres -d db_archive \
  -v ON_ERROR_STOP=1 -f /seeds/52-week-sandbox.sql
```

容器内路径需要先把 `seeds/` 挂载到 `/seeds`，或：

```bash
docker compose cp seeds/52-week-sandbox.sql postgres:/tmp/
docker compose exec -T postgres psql -U postgres -d db_archive -f /tmp/52-week-sandbox.sql
```

## 说明

- 脚本使用 `ON CONFLICT DO NOTHING` / `NOT EXISTS`，重复执行不会无限增长。
- 会触发时间线同步；这是预期行为。
- 生产环境不要执行；如需演示，用独立 `db_archive_demo` 或看板沙盒模式。
