# 网站 B 数据字典（`db_archive.archive`）

> 对应 SQL：[`02-archive-schema.sql`](../../deploy/postgres/initdb/02-archive-schema.sql)、[`03-archive-triggers.sql`](../../deploy/postgres/initdb/03-archive-triggers.sql)、[`08-indexes-grants.sql`](../../deploy/postgres/initdb/08-indexes-grants.sql)。

## 1. 枚举

| 枚举 | 值 | 用途 |
|---|---|---|
| `archive.privacy_level` | `PUBLIC` / `RESTRICTED` / `PRIVATE` / `VAULT` | 隐私分级；默认 `PRIVATE` |
| `archive.storage_tier` | `LOCAL_CACHE` / `OSS_STANDARD` / `OSS_IA` / `OSS_ARCHIVE` | 资产当前存储层级 |
| `archive.life_domain` | `CAREER_WORK` / `INVEST_TRADING` / `LEARNING_EXAM` / `FITNESS_HEALTH` / `FAMILY_LIFE` / `SYSTEM_TECH` | 六大生命领域 |

## 2. `archive.archive_assets`：数字资产总账

| 列 | 类型 | 空 | 默认/约束 | 说明 |
|---|---|---:|---|---|
| `asset_id` | `UUID` | 否 | `gen_random_uuid()` PK | 资产主键 |
| `asset_category` | `VARCHAR(32)` | 否 | — | `PHOTO`/`VIDEO`/`SCAN_DOC`/`CERTIFICATE`/`MEDICAL`/`OTHER` |
| `title` | `VARCHAR(255)` | 否 | — | 展示标题 |
| `original_filename` | `VARCHAR(512)` | 否 | — | 原始文件名 |
| `mime_type` | `VARCHAR(128)` | 否 | — | MIME |
| `file_size_bytes` | `BIGINT` | 否 | `>= 0` | 原始文件大小 |
| `sha256_hash` | `CHAR(64)` | 否 | 唯一，正则校验 | 内容哈希，去重键 |
| `oss_bucket` | `VARCHAR(128)` | 否 | — | 私有 Bucket 名 |
| `oss_object_key` | `VARCHAR(1024)` | 否 | 与 Bucket 联合唯一 | 原对象 Key |
| `thumbnail_key` | `VARCHAR(1024)` | 是 | — | WebP 缩略图 Key |
| `current_tier` | `archive.storage_tier` | 否 | `OSS_STANDARD` | 生命周期同步层级 |
| `is_encrypted` | `BOOLEAN` | 否 | `FALSE` | 对象是否额外加密 |
| `reference_count` | `INTEGER` | 否 | `1 >= 0` | 逻辑引用计数 |
| `captured_at` | `TIMESTAMPTZ` | 是 | — | 拍摄/创建时间 |
| `document_date` | `DATE` | 是 | — | 文档业务日期 |
| `extracted_text` | `TEXT` | 是 | — | PDF/OCR 文本，前 50 页 |
| `search_vector` | `TSVECTOR` | 是 | — | 应用侧分词全文 |
| `embedding` | `vector(1536)` | 是 | HNSW cosine | 语义检索向量 |
| `media_metadata` | `JSONB` | 否 | `{}` | 宽高、EXIF、缩略图状态等 |
| `domain` | `archive.life_domain` | 否 | `FAMILY_LIFE` | 生命领域 |
| `tags` | `TEXT[]` | 否 | `{}` | 标签，GIN |
| `privacy` | `archive.privacy_level` | 否 | `PRIVATE` | 隐私级别 |
| `deleted_at` | `TIMESTAMPTZ` | 是 | — | 软删除；GC 前确认引用为 0 |
| `created_at` | `TIMESTAMPTZ` | 否 | `NOW()` | 入库时间 |
| `updated_at` | `TIMESTAMPTZ` | 否 | `NOW()` + 触发器 | 更新时间 |

**约束/索引**

- `uq_archive_asset_object (oss_bucket, oss_object_key)`：对象唯一。
- `sha256_hash` 唯一：秒传/去重。
- `idx_assets_category`、`idx_assets_tier`、`idx_assets_domain`、`idx_assets_tags_gin`、`idx_assets_media_gin`。
- `idx_assets_embedding_hnsw`（`05`）、`idx_assets_title_trgm`、`idx_assets_search_vector_gin`。

**生命周期**

OSS 规则见 [`成本台账`](../06-合规与成本/成本台账.md)：`scan_doc/` 90 天 IA；`photo/` 30 天 IA、180 天 Archive；`video/` 7 天 Archive；`restic-cold-backup/` 30 天 IA。数据库 `current_tier` 由运维对账脚本/人工更新，不依赖 OSS 事件。

## 3. `archive.timeline_events`：统一时间线

| 列 | 类型 | 空 | 默认/约束 | 说明 |
|---|---|---:|---|---|
| `event_id` | `UUID` | 否 | PK | 事件主键 |
| `title` | `VARCHAR(255)` | 否 | — | 事件标题 |
| `summary` | `TEXT` | 是 | — | 摘要/复盘原则 |
| `domain` | `archive.life_domain` | 否 | — | 领域 |
| `event_type` | `VARCHAR(64)` | 否 | — | `BOOK_FINISHED`/`WORKOUT_*`/`RETRO_*` |
| `occurred_at` | `TIMESTAMPTZ` | 否 | — | 开始时间 |
| `ended_at` | `TIMESTAMPTZ` | 是 | `>= occurred_at` | 结束时间 |
| `time_span` | `TSTZRANGE` | 否 | 生成列 | 时间范围，GIST |
| `importance_score` | `SMALLINT` | 否 | `5`，1–10 | 重要性 |
| `energy_impact` | `SMALLINT` | 否 | `0`，-5–5 | 能量影响 |
| `duration_minutes` | `INTEGER` | 是 | `>= 0` | 时长 |
| `location_name` | `VARCHAR(128)` | 是 | — | 地点名 |
| `geo_coords` | `POINT` | 是 | — | 经纬度 |
| `source_table` | `VARCHAR(64)` | 是 | 与 `source_id` 联合唯一 | 来源表 |
| `source_id` | `UUID` | 是 | — | 来源主键 |
| `tags` | `TEXT[]` | 否 | `{}` | 标签 |
| `metrics_payload` | `JSONB` | 否 | `{}` | 模块指标 |
| `privacy` | `archive.privacy_level` | 否 | `PRIVATE` | 隐私 |
| `created_at` / `updated_at` | `TIMESTAMPTZ` | 否 | `NOW()` | 审计 |

**幂等键**：`uq_timeline_source_entity (source_table, source_id)`。触发器用 `ON CONFLICT` 更新同一节点。

**索引**：`occurred_at DESC`、`time_span GIST`、`(domain, event_type)`、`tags GIN`、`metrics_payload GIN`、`(source_table, source_id)`、`(privacy, occurred_at DESC)`、`title trgm`。

## 4. `archive.entity_links`：多态弱关联

| 列 | 类型 | 空 | 说明 |
|---|---|---:|---|
| `link_id` | `UUID` | 否 | PK |
| `from_type` / `to_type` | `VARCHAR(64)` | 否 | 实体类型，如 `reading_item` |
| `from_id` / `to_id` | `UUID` | 否 | 实体主键 |
| `relation_type` | `VARCHAR(64)` | 否 | 默认 `RELATED_TO` |
| `note` | `TEXT` | 是 | 关系说明 |
| `created_at` | `TIMESTAMPTZ` | 否 | 创建时间 |

唯一键：`(from_type, from_id, to_type, to_id, relation_type)`。不加强制外键，应用负责一致性。

## 5. `archive.reading_items`：书目

| 列 | 类型 | 空 | 默认/约束 | 说明 |
|---|---|---:|---|---|
| `item_id` | `UUID` | 否 | PK | 书目 ID |
| `item_type` | `VARCHAR(32)` | 否 | `BOOK` | `BOOK`/`PAPER`/`ARTICLE` 等 |
| `title` | `VARCHAR(512)` | 否 | — | 标题 |
| `subtitle` | `VARCHAR(512)` | 是 | — | 副标题 |
| `authors` | `TEXT[]` | 否 | `{}` | 作者数组 |
| `isbn_or_doi` | `VARCHAR(64)` | 是 | — | ISBN/DOI |
| `publisher` / `publish_year` | `VARCHAR(128)` / `SMALLINT` | 是 | — | 出版信息 |
| `language` | `VARCHAR(16)` | 否 | `zh-CN` | 语言 |
| `status` | `VARCHAR(32)` | 否 | `WISHLIST` | `WISHLIST`/`READING`/`COMPLETED`/`ABANDONED` |
| `total_pages` | `INTEGER` | 是 | `> 0` | 总页数 |
| `current_page` | `INTEGER` | 否 | `0 >= 0`，`<= total_pages` | 当前页 |
| `rating` | `NUMERIC(3,1)` | 是 | 0–10 | 评分 |
| `core_takeaways` | `TEXT` | 是 | — | 核心收获 |
| `domain` | `archive.life_domain` | 否 | `LEARNING_EXAM` | 领域 |
| `tags` | `TEXT[]` | 否 | `{}` | 标签 |
| `file_asset_id` / `cover_asset_id` | `UUID` | 是 | 外键资产 | 电子书/封面 |
| `started_at` / `finished_at` | `DATE` | 是 | `finished >= started` | 起止日期 |
| `created_at` / `updated_at` | `TIMESTAMPTZ` | 否 | `NOW()` | 审计 |

**状态机**

```text
WISHLIST → READING → COMPLETED
     └──────────────→ ABANDONED
READING ────────────→ ABANDONED
COMPLETED → READING（触发器删除旧时间线节点）
```

## 6. `archive.reading_logs`：阅读会话/摘录/批注

| 列 | 类型 | 空 | 默认/约束 | 说明 |
|---|---|---:|---|---|
| `log_id` | `UUID` | 否 | PK | 日志 ID |
| `item_id` | `UUID` | 否 | FK → `reading_items`，级联删除 | 书目 |
| `log_type` | `VARCHAR(32)` | 否 | `SESSION` | `SESSION`/`HIGHLIGHT`/`THOUGHT`/`NOTE` |
| `started_at` | `TIMESTAMPTZ` | 否 | `NOW()` | 开始时间 |
| `duration_minutes` | `INTEGER` | 否 | `0 >= 0` | 时长 |
| `start_page` / `end_page` | `INTEGER` | 是 | `>= 0`，`end >= start` | 页码 |
| `pages_read` | `INTEGER` | 否 | 生成列 | `max(0, end-start)` |
| `chapter_title` | `VARCHAR(255)` | 是 | — | 章节 |
| `quote_text` | `TEXT` | 是 | — | 摘录 |
| `comment_markdown` | `TEXT` | 是 | — | 批注 |
| `embedding` | `vector(1536)` | 是 | HNSW | 语义检索 |
| `created_at` | `TIMESTAMPTZ` | 否 | `NOW()` | 创建时间 |

## 7. `archive.fitness_workouts`：训练记录

| 列 | 类型 | 空 | 默认/约束 | 说明 |
|---|---|---:|---|---|
| `workout_id` | `UUID` | 否 | PK | 训练 ID |
| `workout_type` | `VARCHAR(32)` | 否 | — | `RUNNING`/`STRENGTH`/`CYCLING`/`SWIMMING`/`OTHER` |
| `title` | `VARCHAR(255)` | 是 | — | 标题；空则触发器生成 |
| `started_at` / `ended_at` | `TIMESTAMPTZ` | 否/是 | `ended >= started` | 起止 |
| `duration_minutes` | `INTEGER` | 否 | `> 0` | 时长 |
| `calories_kcal` | `INTEGER` | 是 | `>= 0` | 热量 |
| `avg_heart_rate` / `max_heart_rate` | `SMALLINT` | 是 | 30–250 | 心率 |
| `rpe_score` | `NUMERIC(3,1)` | 是 | 1–10 | 主观强度 |
| `training_load` | `INTEGER` | 是 | `>= 0` | 训练负荷 |
| `distance_meters` | `INTEGER` | 是 | `>= 0` | 距离 |
| `avg_pace_sec_km` | `INTEGER` | 是 | `> 0` | 平均配速（秒/km） |
| `avg_cadence` | `SMALLINT` | 是 | `>= 0` | 步频/踏频 |
| `elevation_gain_m` | `NUMERIC(6,1)` | 是 | — | 爬升 |
| `total_volume_kg` | `NUMERIC(10,2)` | 是 | `>= 0` | 力量容量 |
| `total_sets` | `SMALLINT` | 是 | `>= 0` | 组数 |
| `exercise_details` | `JSONB` | 否 | `[]` | 动作明细 |
| `route_asset_id` | `UUID` | 是 | FK 资产 | 轨迹文件 |
| `tags` | `TEXT[]` | 否 | `{}` | 标签 |
| `notes` | `TEXT` | 是 | — | 备注 |
| `created_at` / `updated_at` | `TIMESTAMPTZ` | 否 | `NOW()` | 审计 |

## 8. `archive.fitness_biometrics`：每日生理基线

| 列 | 类型 | 空 | 约束 | 说明 |
|---|---|---:|---|---|
| `record_date` | `DATE` | 否 | PK | 日期，一天一条 |
| `weight_kg` | `NUMERIC(5,2)` | 是 | `> 0` | 体重 |
| `body_fat_pct` | `NUMERIC(4,1)` | 是 | 0–70 | 体脂率 |
| `resting_hr` | `SMALLINT` | 是 | 25–150 | 静息心率 |
| `hrv_ms` | `SMALLINT` | 是 | `>= 0` | HRV |
| `sleep_hours` / `deep_sleep_hours` | `NUMERIC(4,2)` | 是 | 0–24 | 睡眠 |
| `steps_count` | `INTEGER` | 是 | `>= 0` | 步数 |
| `subjective_energy` | `SMALLINT` | 是 | 1–10 | 主观能量 |
| `extra_metrics` | `JSONB` | 否 | `{}` | 扩展指标 |
| `updated_at` | `TIMESTAMPTZ` | 否 | `NOW()` | 更新时间 |

## 9. `archive.project_retrospectives`：结构化复盘

| 列 | 类型 | 空 | 默认/约束 | 说明 |
|---|---|---:|---|---|
| `retro_id` | `UUID` | 否 | PK | 复盘 ID |
| `retro_type` | `VARCHAR(32)` | 否 | — | `WEEKLY`/`PROJECT_POSTMORTEM`/`TRADING_PLAYBOOK`/`EXAM_STAGE`/`OTHER` |
| `domain` | `archive.life_domain` | 否 | — | 领域 |
| `title` | `VARCHAR(255)` | 否 | — | 标题 |
| `period_start` / `period_end` | `DATE` | 否 | `end >= start` | 周期 |
| `initial_hypothesis` | `TEXT` | 是 | — | 初始假设 |
| `actual_execution` | `TEXT` | 是 | — | 实际执行 |
| `root_cause_analysis` | `TEXT` | 是 | — | 根因分析 |
| `codified_principles` | `TEXT` | 是 | — | 原则迭代 |
| `kpi_snapshot` | `JSONB` | 否 | `{}` | KPI 快照 |
| `action_items` | `JSONB` | 否 | `[]` | 行动项 |
| `execution_score` / `outcome_score` | `SMALLINT` | 是 | 1–10 | 执行/结果评分 |
| `tags` | `TEXT[]` | 否 | `{}` | 标签 |
| `embedding` | `vector(1536)` | 是 | HNSW | 语义检索 |
| `privacy` | `archive.privacy_level` | 否 | `PRIVATE` | 隐私 |
| `created_at` / `updated_at` | `TIMESTAMPTZ` | 否 | `NOW()` | 审计 |

## 10. 视图

### `archive.v_weekly_life_analytics`

近 52 周（周一开始）聚合：阅读时长/页数、训练次数/时长/跑量/力量容量、睡眠/静息心率/体重、复盘次数/执行分。看板主数据源。

- 周起始：`date_trunc('week', ...)::date`。
- `reading_hours = SUM(duration_minutes)/60`。
- `strength_tonnage = SUM(total_volume_kg)/1000`。
- 空周补 0；生理指标无记录则为 `NULL`（不要当 0 处理）。

### `archive.v_asset_storage_summary`

按 `current_tier`、`asset_category` 汇总资产数量与容量；只统计 `deleted_at IS NULL`。

### `archive.v_recent_timeline`

近 90 天时间线，按 `occurred_at DESC`，供看板/操作台快速读取。

## 11. 数据质量检查

```sql
-- 时间线孤儿
SELECT count(*) FROM archive.timeline_events t
WHERE t.source_table = 'reading_items'
  AND NOT EXISTS (SELECT 1 FROM archive.reading_items r WHERE r.item_id = t.source_id);

-- 资产软删除但仍被引用
SELECT a.asset_id FROM archive.archive_assets a
WHERE a.deleted_at IS NOT NULL
  AND (EXISTS (SELECT 1 FROM archive.reading_items r WHERE r.file_asset_id = a.asset_id)
       OR EXISTS (SELECT 1 FROM archive.fitness_workouts w WHERE w.route_asset_id = a.asset_id));

-- 周视图行数（应约 53）
SELECT count(*) FROM archive.v_weekly_life_analytics;
```
