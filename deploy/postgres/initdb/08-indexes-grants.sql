-- =============================================================================
-- 08-indexes-grants.sql
-- 网站 B / 网站 A：HNSW、trgm、全文索引、只读/备份权限
-- 目标：db_archive + db_mobobrain（intel 采集域 + capital 投研域 + n8n 自动化域）
-- =============================================================================

\set ON_ERROR_STOP on

-- =============================================================================
-- A. db_archive
-- =============================================================================
\c db_archive

SET search_path TO archive, public;

-- 语义检索：HNSW cosine
CREATE INDEX IF NOT EXISTS idx_assets_embedding_hnsw
    ON archive.archive_assets USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

CREATE INDEX IF NOT EXISTS idx_reading_logs_embedding_hnsw
    ON archive.reading_logs USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

CREATE INDEX IF NOT EXISTS idx_retro_embedding_hnsw
    ON archive.project_retrospectives USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- 中文标题/摘要降级检索：trgm
CREATE INDEX IF NOT EXISTS idx_assets_title_trgm
    ON archive.archive_assets USING GIN (title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_reading_title_trgm
    ON archive.reading_items USING GIN (title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_retro_title_trgm
    ON archive.project_retrospectives USING GIN (title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_timeline_title_trgm
    ON archive.timeline_events USING GIN (title gin_trgm_ops);

-- 应用侧分词后的全文
CREATE INDEX IF NOT EXISTS idx_assets_search_vector_gin
    ON archive.archive_assets USING GIN (search_vector);

-- 看板只读权限
GRANT SELECT ON ALL TABLES IN SCHEMA archive TO user_dashboard_ro;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA archive TO user_dashboard_ro;
GRANT SELECT ON archive.v_weekly_life_analytics TO user_dashboard_ro;
GRANT SELECT ON archive.v_asset_storage_summary TO user_dashboard_ro;
GRANT SELECT ON archive.v_recent_timeline TO user_dashboard_ro;

ALTER DEFAULT PRIVILEGES FOR ROLE user_archive IN SCHEMA archive
    GRANT SELECT ON TABLES TO user_dashboard_ro;
ALTER DEFAULT PRIVILEGES FOR ROLE user_archive IN SCHEMA archive
    GRANT SELECT ON SEQUENCES TO user_dashboard_ro;

-- 备份账号显式权限（pg_read_all_data 已覆盖，显式更清晰）
GRANT USAGE ON SCHEMA archive TO user_backup;
GRANT SELECT ON ALL TABLES IN SCHEMA archive TO user_backup;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA archive TO user_backup;
ALTER DEFAULT PRIVILEGES FOR ROLE user_archive IN SCHEMA archive
    GRANT SELECT ON TABLES TO user_backup;
ALTER DEFAULT PRIVILEGES FOR ROLE user_archive IN SCHEMA archive
    GRANT SELECT ON SEQUENCES TO user_backup;

-- =============================================================================
-- B. db_mobobrain
-- =============================================================================
\c db_mobobrain

SET search_path TO intel, public;

-- 语义检索：HNSW cosine
CREATE INDEX IF NOT EXISTS idx_articles_embedding_hnsw
    ON intel.articles_vault USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- 中文标题/摘要降级检索
CREATE INDEX IF NOT EXISTS idx_articles_title_trgm
    ON intel.articles_vault USING GIN (title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_drafts_title_trgm
    ON intel.content_drafts USING GIN (title gin_trgm_ops);

-- 应用侧分词后的全文
CREATE INDEX IF NOT EXISTS idx_articles_search_vector_gin
    ON intel.articles_vault USING GIN (search_vector);

-- n8n 业务读取权限（n8n 通过 intel Schema 读写文章/草稿）
GRANT USAGE ON SCHEMA intel TO user_n8n;
GRANT SELECT, INSERT, UPDATE ON intel.sources TO user_n8n;
GRANT SELECT, INSERT, UPDATE ON intel.articles_vault TO user_n8n;
GRANT SELECT, INSERT, UPDATE ON intel.content_drafts TO user_n8n;
GRANT SELECT, INSERT, UPDATE ON intel.ingestion_runs TO user_n8n;
GRANT SELECT, INSERT ON intel.llm_usage TO user_n8n;

-- 备份账号
GRANT USAGE ON SCHEMA intel TO user_backup;
GRANT USAGE ON SCHEMA n8n TO user_backup;
GRANT SELECT ON ALL TABLES IN SCHEMA intel TO user_backup;
GRANT SELECT ON ALL TABLES IN SCHEMA n8n TO user_backup;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA intel TO user_backup;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA n8n TO user_backup;

ALTER DEFAULT PRIVILEGES FOR ROLE user_mobobrain IN SCHEMA intel
    GRANT SELECT ON TABLES TO user_backup;
ALTER DEFAULT PRIVILEGES FOR ROLE user_mobobrain IN SCHEMA intel
    GRANT SELECT ON SEQUENCES TO user_backup;

-- n8n 需要在自己的 Schema 中建表/迁移
GRANT USAGE, CREATE ON SCHEMA n8n TO user_n8n;
ALTER DEFAULT PRIVILEGES FOR ROLE user_n8n IN SCHEMA n8n
    GRANT SELECT ON TABLES TO user_backup;

-- =============================================================================
-- B2. db_mobobrain · capital 投研域（莫伯资本）
-- =============================================================================
SET search_path TO capital, public;

-- 中文标题降级检索：trgm（trgm 用于短标题，不用于长正文）
CREATE INDEX IF NOT EXISTS idx_capital_theses_title_trgm
    ON capital.macro_theses USING GIN (title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_capital_playbooks_name_trgm
    ON capital.strategy_playbooks USING GIN (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_capital_publications_title_trgm
    ON capital.capital_publications USING GIN (title gin_trgm_ops);

-- 发布流水按可见性过滤（公私域导出的高频查询）
CREATE INDEX IF NOT EXISTS idx_capital_publications_visibility
    ON capital.capital_publications(visibility, publish_status, created_at DESC);

-- 工作流 #2 需要把四端合成结果写入 capital_publications
GRANT USAGE ON SCHEMA capital TO user_n8n;
GRANT SELECT, INSERT, UPDATE ON capital.capital_publications TO user_n8n;
GRANT SELECT ON capital.macro_theses TO user_n8n;
GRANT SELECT ON capital.strategy_playbooks TO user_n8n;
GRANT SELECT ON capital.trade_reviews TO user_n8n;
GRANT SELECT ON capital.media_channel_metrics TO user_n8n;
GRANT SELECT ON capital.v_strategy_performance_summary TO user_n8n;
GRANT SELECT ON capital.v_media_conversion_funnel TO user_n8n;
GRANT SELECT ON capital.v_latest_macro_indicators TO user_n8n;
GRANT SELECT ON capital.v_latest_options_vol_surface TO user_n8n;

-- 备份账号：capital 域只读
GRANT SELECT ON ALL TABLES IN SCHEMA capital TO user_backup;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA capital TO user_backup;
ALTER DEFAULT PRIVILEGES FOR ROLE user_mobobrain IN SCHEMA capital
    GRANT SELECT ON TABLES TO user_backup;
ALTER DEFAULT PRIVILEGES FOR ROLE user_mobobrain IN SCHEMA capital
    GRANT SELECT ON SEQUENCES TO user_backup;

-- =============================================================================
-- C. 说明
-- =============================================================================
-- 1) HNSW 索引在空表上创建很快；有数据后建索引需要内存/时间。
-- 2) trgm 适合标题/短摘要；不要对超长正文建 trgm。
-- 3) n8n 不应直接写 archive 库；网站 B 只由 CLI/看板写。
-- 4) 生产变更走 migrations/，不要重复执行本文件的可变部分。
