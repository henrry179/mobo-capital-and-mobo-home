# 数据库迁移

> 本目录只放“初始化之后”的增量变更；`deploy/postgres/initdb/01~06.sql` 只在空数据卷首次启动执行。

## 1. 命名

```text
YYYYMMDDHHMM__short_description.sql
```

示例：

```text
202610200001__schema_migrations.sql
202611010001__add_asset_checksum_index.sql
```

- 双下划线分隔版本与描述。
- 描述用英文小写+下划线，避免空格/中文路径问题。
- 每个迁移文件头部写：目的、影响表、是否可回滚、预计耗时。

## 2. 版本表

`202610200001__schema_migrations.sql` 创建：

```sql
CREATE TABLE IF NOT EXISTS public.schema_migrations (
    version     TEXT PRIMARY KEY,
    description TEXT NOT NULL,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    checksum    TEXT NOT NULL
);
```

## 3. 执行

### 3.1 手工执行（推荐先演练）

```bash
cd /opt/mobo-stack

# 1) 备份
docker compose exec -T restic-backup /usr/local/bin/run-daily-backup.sh

# 2) 在事务中执行
docker compose exec -T postgres psql -U postgres -d db_archive \
  -v ON_ERROR_STOP=1 -f /migrations/202611010001__example.sql
```

> 迁移文件需挂载/复制到容器，或通过 `docker compose cp`。生产建议用 `migrations/apply.sh`。

### 3.2 Runner

```bash
./migrations/apply.sh db_archive
./migrations/apply.sh db_mobobrain
```

Runner 会：

1. 创建 `schema_migrations`（如不存在）。
2. 按文件名排序。
3. 跳过已记录版本。
4. 在单事务中执行（`CREATE INDEX CONCURRENTLY` 除外）。
5. 记录版本/描述/SHA-256。

## 4. 回滚

- 优先写 `*.rollback.sql`，并在迁移头注释说明。
- 数据回滚优先“恢复到新库再切换”，不要在生产直接 `DROP COLUMN`。
- 破坏性变更必须停机窗口 + 备份 + 演练。

## 5. 检查清单

- [ ] 本地空库/演练库执行通过。
- [ ] 幂等或明确只执行一次。
- [ ] 不修改 `n8n` Schema（n8n 自己管理）。
- [ ] 大表索引使用 `CONCURRENTLY`。
- [ ] 更新 `docs/04-数据库设计/` 字典。
- [ ] 备份后再执行。
- [ ] 执行后跑 `tests/sql/smoke.sql`。
