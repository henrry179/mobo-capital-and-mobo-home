# 数据库设计

> 本目录是数据库的“人读版本”；机器可执行版本是 `deploy/postgres/initdb/01~09.sql`。两者冲突时，以 SQL 为准，并立即回写文档。

## 1. 设计原则

1. **单实例双库**：一个 PostgreSQL 16 + pgvector 实例，逻辑隔离为 `db_mobobrain` 与 `db_archive`。
2. **Schema 隔离**：网站 A 用 `intel`（业务）+ `n8n`（自动化）；网站 B 用 `archive`。
3. **最小权限**：应用账号只访问自己的库/Schema；看板只读；备份账号只读。
4. **时间统一**：所有时间列使用 `TIMESTAMPTZ`，业务日期使用 `DATE`；容器与数据库时区均为 `Asia/Shanghai`。
5. **可追溯**：主键统一 `UUID`；`created_at` / `updated_at` 由数据库默认值与触发器维护。
6. **软删除优先**：资产用 `deleted_at`；业务表删除前先确认引用与备份。
7. **向量维度固定**：当前基线 `vector(1536)`；换模型必须走迁移，不能只改环境变量。

## 2. 对象地图

| 数据库 | Schema | 表/视图 | 说明 |
|---|---|---|---|
| `db_archive` | `archive` | `archive_assets` | 数字资产元数据总账 |
| `db_archive` | `archive` | `timeline_events` | 统一时间线 |
| `db_archive` | `archive` | `entity_links` | 多态弱关联 |
| `db_archive` | `archive` | `reading_items` / `reading_logs` | 阅读书目/日志 |
| `db_archive` | `archive` | `fitness_workouts` / `fitness_biometrics` | 运动/生理基线 |
| `db_archive` | `archive` | `project_retrospectives` | 结构化复盘 |
| `db_archive` | `archive` | `v_weekly_life_analytics` | 52 周看板主视图 |
| `db_archive` | `archive` | `v_asset_storage_summary` | 资产容量汇总 |
| `db_archive` | `archive` | `v_recent_timeline` | 近 90 天时间线 |
| `db_mobobrain` | `intel` | `sources` | RSS/URL 情报源 |
| `db_mobobrain` | `intel` | `articles_vault` | 采集文章金库 |
| `db_mobobrain` | `intel` | `content_drafts` | 多平台草稿 |
| `db_mobobrain` | `intel` | `ingestion_runs` | 采集运行记录 |
| `db_mobobrain` | `intel` | `llm_usage` | LLM 用量/成本 |
| `db_mobobrain` | `intel` | `v_recent_high_value` | 高分文章候选 |
| `db_mobobrain` | `capital` | `macro_theses` | 宏观与产业投研论点 |
| `db_mobobrain` | `capital` | `strategy_playbooks` | 策略标准手册 |
| `db_mobobrain` | `capital` | `trade_reviews` | 实战交易复盘与归因 |
| `db_mobobrain` | `capital` | `fund_incubation_milestones` | 基金三阶段孵化里程碑 |
| `db_mobobrain` | `capital` | `fund_governance_docs` | 基金治理与合规文档 |
| `db_mobobrain` | `capital` | `capital_publications` | “1+3”四端合成与发布主表 |
| `db_mobobrain` | `capital` | `media_channel_metrics` | 自媒体渠道运营指标 |
| `db_mobobrain` | `capital` | `portfolio_nav_ledger` | 组合净值台账（触发器维护） |
| `db_mobobrain` | `capital` | `macro_indicator_series` | 宏观先行指标日频序列 |
| `db_mobobrain` | `capital` | `options_vol_surface_daily` | 期权隐含波动率曲面日频快照 |
| `db_mobobrain` | `capital` | `v_strategy_performance_summary` | 策略胜率/盈亏比/纪律聚合 |
| `db_mobobrain` | `capital` | `v_media_conversion_funnel` | 多平台分发与导流漏斗 |
| `db_mobobrain` | `capital` | `v_latest_macro_indicators` | 最新宏观指标快照 |
| `db_mobobrain` | `capital` | `v_latest_options_vol_surface` | 最新期权波动率曲面 |
| `db_mobobrain` | `n8n` | n8n 内部表 | 由 n8n 迁移管理，本项目不手改 |

## 3. 角色

| 角色 | 权限 | 用途 |
|---|---|---|
| `user_mobobrain` | `db_mobobrain.intel` + `db_mobobrain.capital` 读写、建表 | 业务应用/CLI |
| `user_n8n` | `db_mobobrain.n8n` 读写建表；`intel` 与 `capital` 指定表读写 | n8n 工作流 |
| `user_archive` | `db_archive.archive` 读写、建表 | CLI/后台写入 |
| `user_dashboard_ro` | `db_archive.archive` 只读 | Streamlit 看板 |
| `user_backup` | 全库只读（`pg_read_all_data`） | 备份/审计 |
| `postgres` | 超级用户 | 仅初始化/灾备，应用禁用 |

> `capital` 域不对 `user_dashboard_ro` 开放：看板服务网站 B，投研数据仅经 CLI 脱敏后以静态 JSON 出现在网站 A。

## 4. 初始化顺序

`docker-entrypoint-initdb.d` 按文件名排序执行：

1. `01-init-dual-db.sql`：角色、双库、四 Schema、连接与 Schema 权限。
2. `02-archive-schema.sql`：`archive` 表、基础索引、视图。
3. `03-archive-triggers.sql`：四大时间线同步触发器。
4. `04-mobobrain-schema.sql`：`intel` 表、索引、视图。
5. `05-mobocapital-schema.sql`：`capital` 投研七表、两个视图、孵化里程碑种子。
6. `06-mobocapital-nav-and-triggers.sql`：NAV 台账、回撤熔断触发器、策略与论点种子。
7. `07-mobocapital-terminal-schema.sql`：宏观指标、期权曲面与最新快照视图。
8. `08-indexes-grants.sql`：HNSW/trgm/全文索引、看板/备份授权、n8n 授权。
9. `09-updated-at-triggers.sql`：三域 `updated_at` 统一触发器。

> 只在 **空数据卷首次启动** 执行。生产变更必须走 `migrations/`，不要删除 `pg_data` 重跑初始化。

## 5. 迁移约定

- 文件名：`YYYYMMDDHHMM__short_description.sql`。
- 每个迁移必须可重复执行（`IF NOT EXISTS` / `DO $$` 守卫）或明确只执行一次。
- 迁移先写“向前”，再写“回滚说明”；破坏性变更必须先备份。
- 迁移记录表：`public.schema_migrations(version, description, applied_at, checksum)`，由 runner 维护。
- 详见 [`迁移与备份策略.md`](迁移与备份策略.md)。

## 6. 相关文档

- [网站 B 数据字典](网站B数据字典.md)
- [网站 A 数据字典](网站A数据字典.md)
- [触发器与视图](触发器与视图.md)
- [迁移与备份策略](迁移与备份策略.md)
