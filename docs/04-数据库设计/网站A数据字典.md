# 网站 A 数据字典（`db_mobobrain.intel` + `n8n`）

> 对应 SQL：[`04-mobobrain-schema.sql`](../../deploy/postgres/initdb/04-mobobrain-schema.sql)、[`08-indexes-grants.sql`](../../deploy/postgres/initdb/08-indexes-grants.sql)。
> 莫伯资本投研域（`capital` Schema）见 [`莫伯资本数据字典.md`](莫伯资本数据字典.md)。

## 1. 边界

- `intel`：本项目业务表，存情报源、文章、草稿、采集运行、LLM 用量。
- `n8n`：n8n 自己的 Schema，存工作流、凭证、执行记录；由 n8n 迁移管理，**不手写业务表**。
- 思源笔记的正文/附件不在 PostgreSQL；数据库只存 `siyuan_doc_id` 等桥接字段。

## 2. `intel.sources`：情报源

| 列 | 类型 | 空 | 默认/约束 | 说明 |
|---|---|---:|---|---|
| `source_id` | `UUID` | 否 | PK | 来源 ID |
| `name` | `VARCHAR(255)` | 否 | — | 来源名 |
| `feed_url` | `TEXT` | 否 | 唯一 | RSS/URL |
| `source_type` | `VARCHAR(32)` | 否 | `RSS` | `RSS`/`URL`/`MANUAL`/`NEWSLETTER` |
| `category` | `VARCHAR(64)` | 是 | — | 分类 |
| `enabled` | `BOOLEAN` | 否 | `TRUE` | 是否启用 |
| `fetch_interval_minutes` | `INTEGER` | 否 | `240 >= 15` | 采集间隔 |
| `last_fetched_at` | `TIMESTAMPTZ` | 是 | — | 最近采集 |
| `metadata` | `JSONB` | 否 | `{}` | 扩展 |
| `created_at` / `updated_at` | `TIMESTAMPTZ` | 否 | `NOW()` | 审计 |

**索引**：`(enabled, last_fetched_at)`、`category`。

## 3. `intel.articles_vault`：文章金库

| 列 | 类型 | 空 | 默认/约束 | 说明 |
|---|---|---:|---|---|
| `article_id` | `UUID` | 否 | PK | 文章 ID |
| `source_id` | `UUID` | 是 | FK → `sources`，删除置空 | 来源 |
| `source_url` | `TEXT` | 否 | — | 原文 URL |
| `url_hash` | `CHAR(64)` | 否 | 唯一，正则 | URL SHA-256，去重 |
| `title` | `TEXT` | 否 | — | 标题 |
| `author` | `TEXT` | 是 | — | 作者 |
| `published_at` | `TIMESTAMPTZ` | 是 | — | 发布时间 |
| `fetched_at` | `TIMESTAMPTZ` | 否 | `NOW()` | 采集时间 |
| `language` | `VARCHAR(16)` | 否 | `zh-CN` | 语言 |
| `raw_html` | `TEXT` | 是 | — | 原始 HTML |
| `cleaned_text` | `TEXT` | 是 | — | 清洗正文 |
| `summary` | `TEXT` | 是 | — | 摘要 |
| `core_thesis` | `TEXT` | 是 | — | 核心论点 |
| `key_points` | `JSONB` | 否 | `[]` | 要点数组 |
| `second_order` | `TEXT` | 是 | — | 二阶影响 |
| `sentiment_score` | `NUMERIC(4,3)` | 是 | -1–1 | 情绪 |
| `relevance_score` | `SMALLINT` | 是 | 1–10 | 相关性 |
| `tags` | `TEXT[]` | 否 | `{}` | 标签 |
| `embedding` | `vector(1536)` | 是 | HNSW | 向量 |
| `search_vector` | `TSVECTOR` | 是 | — | 应用侧分词 |
| `siyuan_doc_id` | `TEXT` | 是 | — | 思源文档 ID |
| `status` | `VARCHAR(32)` | 否 | `NEW` | `NEW`/`SCORED`/`SYNCED`/`REJECTED`/`FAILED`/`NEEDS_MANUAL` |
| `metadata` | `JSONB` | 否 | `{}` | 扩展 |
| `created_at` / `updated_at` | `TIMESTAMPTZ` | 否 | `NOW()` | 审计 |

**状态机**

```text
NEW → SCORED → SYNCED
  ├→ REJECTED（低分/不相关）
  └→ NEEDS_MANUAL（JSON 解析失败/缺字段）
任意 → FAILED（不可恢复错误，需人工）
```

**索引**：`status, fetched_at`；`relevance_score, published_at`；`published_at`；`source_id, fetched_at`；`tags` GIN；`key_points` GIN；`metadata` GIN；HNSW；`title` trgm；`search_vector` GIN。

## 4. `intel.content_drafts`：多平台草稿

| 列 | 类型 | 空 | 默认/约束 | 说明 |
|---|---|---:|---|---|
| `draft_id` | `UUID` | 否 | PK | 草稿 ID |
| `batch_id` | `UUID` | 否 | `gen_random_uuid()` | 同批生成 |
| `platform` | `VARCHAR(32)` | 否 | — | `WECHAT`/`XUEQIU`/`X` |
| `title` | `TEXT` | 是 | — | 标题 |
| `body_markdown` | `TEXT` | 否 | — | 正文 |
| `meta` | `JSONB` | 否 | `{}` | 平台元数据 |
| `source_article_ids` | `UUID[]` | 否 | `{}` | 来源文章 |
| `status` | `VARCHAR(32)` | 否 | `DRAFT` | `DRAFT`/`APPROVED`/`PUBLISHED`/`ARCHIVED` |
| `model` | `VARCHAR(128)` | 是 | — | 模型 |
| `prompt_tokens` / `completion_tokens` | `INTEGER` | 是 | `>= 0` | token |
| `cost_usd` | `NUMERIC(10,6)` | 是 | `>= 0` | 成本 |
| `created_at` / `updated_at` | `TIMESTAMPTZ` | 否 | `NOW()` | 审计 |

**约束**：平台枚举由 `CHECK` 限制；发布动作永远由人审核，工作流只能写 `DRAFT`。

## 5. `intel.ingestion_runs`：采集运行

| 列 | 类型 | 空 | 默认/约束 | 说明 |
|---|---|---:|---|---|
| `run_id` | `UUID` | 否 | PK | 运行 ID |
| `workflow_name` | `VARCHAR(128)` | 否 | — | 工作流名 |
| `trigger_type` | `VARCHAR(32)` | 否 | `SCHEDULE` | `SCHEDULE`/`MANUAL`/`WEBHOOK`/`RETRY` |
| `started_at` | `TIMESTAMPTZ` | 否 | `NOW()` | 开始 |
| `finished_at` | `TIMESTAMPTZ` | 是 | — | 结束 |
| `status` | `VARCHAR(32)` | 否 | `RUNNING` | `RUNNING`/`SUCCESS`/`PARTIAL`/`FAILED` |
| `items_fetched` / `items_new` / `items_scored` / `items_synced` | `INTEGER` | 否 | `0 >= 0` | 计数 |
| `error_message` | `TEXT` | 是 | — | 错误 |
| `stats` | `JSONB` | 否 | `{}` | 统计 |
| `created_at` | `TIMESTAMPTZ` | 否 | `NOW()` | 创建 |

**用途**：n8n 每次运行写一条；用于判断“是不是跑过”“为什么少了几条”“LLM 成本是否异常”。

## 6. `intel.llm_usage`：LLM 用量/成本

| 列 | 类型 | 空 | 默认/约束 | 说明 |
|---|---|---:|---|---|
| `usage_id` | `UUID` | 否 | PK | 用量 ID |
| `workflow_name` | `VARCHAR(128)` | 否 | — | 工作流 |
| `model` | `VARCHAR(128)` | 否 | — | 模型 |
| `article_id` | `UUID` | 是 | FK → `articles_vault`，删除置空 | 关联文章 |
| `prompt_tokens` / `completion_tokens` | `INTEGER` | 否 | `0 >= 0` | token |
| `cost_usd` | `NUMERIC(10,6)` | 否 | `0 >= 0` | 成本 |
| `created_at` | `TIMESTAMPTZ` | 否 | `NOW()` | 时间 |

**索引**：`created_at`、`(model, created_at)`。

## 7. 视图 `intel.v_recent_high_value`

筛选 `relevance_score >= 7` 且 `status IN ('SCORED','SYNCED')`，按相关性/发布时间排序；工作流 #1 的思源推送候选集。

## 8. n8n Schema

- 表由 n8n 启动时自动迁移创建，例如 `workflow_entity`、`credentials_entity`、`execution_entity`。
- `user_n8n` 拥有 `USAGE, CREATE`；`user_mobobrain` 只有 `USAGE`，不得改 n8n 表。
- 备份账号 `user_backup` 只读。
- 不要手工 `DROP` n8n 表；升级前先备份 `db_mobobrain` 与 `n8n_data` 卷。

## 9. 常见查询

```sql
-- 今日新增文章
SELECT count(*) FROM intel.articles_vault WHERE fetched_at >= CURRENT_DATE;

-- 待推送高分文章
SELECT article_id, title, relevance_score
FROM intel.articles_vault
WHERE relevance_score >= 7 AND status = 'SCORED'
ORDER BY relevance_score DESC LIMIT 20;

-- 最近 7 天 LLM 成本
SELECT model, sum(cost_usd) AS usd, sum(prompt_tokens+completion_tokens) AS tokens
FROM intel.llm_usage
WHERE created_at >= NOW() - INTERVAL '7 days'
GROUP BY model ORDER BY usd DESC;

-- 失败运行
SELECT run_id, workflow_name, started_at, error_message
FROM intel.ingestion_runs
WHERE status = 'FAILED'
ORDER BY started_at DESC LIMIT 10;
```
