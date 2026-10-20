-- =============================================================================
-- 04-mobobrain-schema.sql
-- 网站 A：情报源、文章库、草稿箱、采集运行、LLM 用量
-- 目标库：db_mobobrain；Schema：intel
-- =============================================================================

\set ON_ERROR_STOP on
\c db_mobobrain

SET search_path TO intel, public;

-- -----------------------------------------------------------------------------
-- 1. 情报源
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS intel.sources (
    source_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                  VARCHAR(255) NOT NULL,
    feed_url              TEXT NOT NULL UNIQUE,
    source_type           VARCHAR(32) NOT NULL DEFAULT 'RSS'
                          CHECK (source_type IN ('RSS', 'URL', 'MANUAL', 'NEWSLETTER')),
    category              VARCHAR(64),
    enabled               BOOLEAN NOT NULL DEFAULT TRUE,
    fetch_interval_minutes INTEGER NOT NULL DEFAULT 240 CHECK (fetch_interval_minutes >= 15),
    last_fetched_at       TIMESTAMPTZ,
    metadata              JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE intel.sources IS 'RSS/URL/手工来源；feed_url 唯一';

-- -----------------------------------------------------------------------------
-- 2. 文章库（情报金库）
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS intel.articles_vault (
    article_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id        UUID REFERENCES intel.sources(source_id) ON DELETE SET NULL,
    source_url       TEXT NOT NULL,
    url_hash         CHAR(64) NOT NULL UNIQUE CHECK (url_hash ~ '^[0-9a-f]{64}$'),
    title            TEXT NOT NULL,
    author           TEXT,
    published_at     TIMESTAMPTZ,
    fetched_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    language         VARCHAR(16) NOT NULL DEFAULT 'zh-CN',
    raw_html         TEXT,
    cleaned_text     TEXT,
    summary          TEXT,
    core_thesis      TEXT,
    key_points       JSONB NOT NULL DEFAULT '[]'::jsonb,
    second_order     TEXT,
    sentiment_score  NUMERIC(4, 3) CHECK (sentiment_score BETWEEN -1.000 AND 1.000),
    relevance_score  SMALLINT CHECK (relevance_score BETWEEN 1 AND 10),
    tags             TEXT[] NOT NULL DEFAULT '{}',
    embedding        vector(1536),
    search_vector    TSVECTOR,
    siyuan_doc_id    TEXT,
    status           VARCHAR(32) NOT NULL DEFAULT 'NEW'
                     CHECK (status IN ('NEW', 'SCORED', 'SYNCED', 'REJECTED', 'FAILED', 'NEEDS_MANUAL')),
    metadata         JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE intel.articles_vault IS '采集文章主库；url_hash 去重；高分文章推送思源';
COMMENT ON COLUMN intel.articles_vault.search_vector IS '由 n8n/CLI 分词后写入；中文不要依赖 simple 配置';

-- -----------------------------------------------------------------------------
-- 3. 多平台草稿箱
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS intel.content_drafts (
    draft_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id          UUID NOT NULL DEFAULT gen_random_uuid(),
    platform          VARCHAR(32) NOT NULL
                      CHECK (platform IN ('WECHAT', 'XUEQIU', 'X')),
    title             TEXT,
    body_markdown     TEXT NOT NULL,
    meta              JSONB NOT NULL DEFAULT '{}'::jsonb,
    source_article_ids UUID[] NOT NULL DEFAULT '{}',
    status            VARCHAR(32) NOT NULL DEFAULT 'DRAFT'
                      CHECK (status IN ('DRAFT', 'APPROVED', 'PUBLISHED', 'ARCHIVED')),
    model             VARCHAR(128),
    prompt_tokens     INTEGER CHECK (prompt_tokens IS NULL OR prompt_tokens >= 0),
    completion_tokens INTEGER CHECK (completion_tokens IS NULL OR completion_tokens >= 0),
    cost_usd          NUMERIC(10, 6) CHECK (cost_usd IS NULL OR cost_usd >= 0),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE intel.content_drafts IS '工作流 #2 产物；人工审核后发布，不做自动发布';

-- -----------------------------------------------------------------------------
-- 4. 采集运行记录
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS intel.ingestion_runs (
    run_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_name   VARCHAR(128) NOT NULL,
    trigger_type    VARCHAR(32) NOT NULL DEFAULT 'SCHEDULE'
                    CHECK (trigger_type IN ('SCHEDULE', 'MANUAL', 'WEBHOOK', 'RETRY')),
    started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at     TIMESTAMPTZ,
    status          VARCHAR(32) NOT NULL DEFAULT 'RUNNING'
                    CHECK (status IN ('RUNNING', 'SUCCESS', 'PARTIAL', 'FAILED')),
    items_fetched   INTEGER NOT NULL DEFAULT 0 CHECK (items_fetched >= 0),
    items_new       INTEGER NOT NULL DEFAULT 0 CHECK (items_new >= 0),
    items_scored    INTEGER NOT NULL DEFAULT 0 CHECK (items_scored >= 0),
    items_synced    INTEGER NOT NULL DEFAULT 0 CHECK (items_synced >= 0),
    error_message   TEXT,
    stats           JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 5. LLM 用量/成本
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS intel.llm_usage (
    usage_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_name     VARCHAR(128) NOT NULL,
    model             VARCHAR(128) NOT NULL,
    article_id        UUID REFERENCES intel.articles_vault(article_id) ON DELETE SET NULL,
    prompt_tokens     INTEGER NOT NULL DEFAULT 0 CHECK (prompt_tokens >= 0),
    completion_tokens INTEGER NOT NULL DEFAULT 0 CHECK (completion_tokens >= 0),
    cost_usd          NUMERIC(10, 6) NOT NULL DEFAULT 0 CHECK (cost_usd >= 0),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 6. 索引（HNSW/trgm 在 05 中补充）
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_sources_enabled
    ON intel.sources (enabled, last_fetched_at);
CREATE INDEX IF NOT EXISTS idx_sources_category
    ON intel.sources (category);

CREATE INDEX IF NOT EXISTS idx_articles_status
    ON intel.articles_vault (status, fetched_at DESC);
CREATE INDEX IF NOT EXISTS idx_articles_score
    ON intel.articles_vault (relevance_score DESC, published_at DESC);
CREATE INDEX IF NOT EXISTS idx_articles_published
    ON intel.articles_vault (published_at DESC);
CREATE INDEX IF NOT EXISTS idx_articles_source
    ON intel.articles_vault (source_id, fetched_at DESC);
CREATE INDEX IF NOT EXISTS idx_articles_tags_gin
    ON intel.articles_vault USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_articles_keypoints_gin
    ON intel.articles_vault USING GIN (key_points);
CREATE INDEX IF NOT EXISTS idx_articles_metadata_gin
    ON intel.articles_vault USING GIN (metadata);

CREATE INDEX IF NOT EXISTS idx_drafts_platform
    ON intel.content_drafts (platform, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_drafts_status
    ON intel.content_drafts (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_drafts_batch
    ON intel.content_drafts (batch_id);

CREATE INDEX IF NOT EXISTS idx_runs_started
    ON intel.ingestion_runs (started_at DESC);
CREATE INDEX IF NOT EXISTS idx_runs_status
    ON intel.ingestion_runs (status, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_llm_usage_created
    ON intel.llm_usage (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_llm_usage_model
    ON intel.llm_usage (model, created_at DESC);

-- -----------------------------------------------------------------------------
-- 7. 高分文章视图
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW intel.v_recent_high_value AS
SELECT
    article_id, source_url, title, author, published_at, fetched_at,
    summary, core_thesis, key_points, second_order,
    sentiment_score, relevance_score, tags, siyuan_doc_id, status
FROM intel.articles_vault
WHERE relevance_score >= 7
  AND status IN ('SCORED', 'SYNCED')
ORDER BY relevance_score DESC, published_at DESC NULLS LAST;

COMMENT ON VIEW intel.v_recent_high_value IS '工作流 #1 推送思源的候选集';
