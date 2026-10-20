-- =============================================================================
-- 02-archive-schema.sql
-- 网站 B：个人数字档案核心表、索引、聚合视图
-- 目标库：db_archive；Schema：archive
-- =============================================================================

\set ON_ERROR_STOP on
\c db_archive

SET search_path TO archive, public;

-- -----------------------------------------------------------------------------
-- 1. 枚举类型（幂等）
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    CREATE TYPE archive.privacy_level AS ENUM ('PUBLIC', 'RESTRICTED', 'PRIVATE', 'VAULT');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    CREATE TYPE archive.storage_tier AS ENUM ('LOCAL_CACHE', 'OSS_STANDARD', 'OSS_IA', 'OSS_ARCHIVE');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    CREATE TYPE archive.life_domain AS ENUM (
        'CAREER_WORK', 'INVEST_TRADING', 'LEARNING_EXAM',
        'FITNESS_HEALTH', 'FAMILY_LIFE', 'SYSTEM_TECH'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- -----------------------------------------------------------------------------
-- 2. 数字资产总账（先建，供阅读/运动外键引用）
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS archive.archive_assets (
    asset_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_category    VARCHAR(32) NOT NULL,
    title             VARCHAR(255) NOT NULL,
    original_filename VARCHAR(512) NOT NULL,
    mime_type         VARCHAR(128) NOT NULL,
    file_size_bytes   BIGINT NOT NULL CHECK (file_size_bytes >= 0),
    sha256_hash       CHAR(64) NOT NULL UNIQUE CHECK (sha256_hash ~ '^[0-9a-f]{64}$'),
    oss_bucket        VARCHAR(128) NOT NULL,
    oss_object_key    VARCHAR(1024) NOT NULL,
    thumbnail_key     VARCHAR(1024),
    current_tier      archive.storage_tier NOT NULL DEFAULT 'OSS_STANDARD',
    is_encrypted      BOOLEAN NOT NULL DEFAULT FALSE,
    reference_count   INTEGER NOT NULL DEFAULT 1 CHECK (reference_count >= 0),
    captured_at       TIMESTAMPTZ,
    document_date     DATE,
    extracted_text    TEXT,
    search_vector     TSVECTOR,
    embedding         vector(1536),
    media_metadata    JSONB NOT NULL DEFAULT '{}'::jsonb,
    domain            archive.life_domain NOT NULL DEFAULT 'FAMILY_LIFE',
    tags              TEXT[] NOT NULL DEFAULT '{}',
    privacy           archive.privacy_level NOT NULL DEFAULT 'PRIVATE',
    deleted_at        TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_archive_asset_object UNIQUE (oss_bucket, oss_object_key)
);

COMMENT ON TABLE archive.archive_assets IS '个人数字资产/文档元数据总账；SHA-256 去重，对象存 OSS';
COMMENT ON COLUMN archive.archive_assets.reference_count IS '逻辑引用计数；由 CLI/应用维护，0 且软删除后可 GC';
COMMENT ON COLUMN archive.archive_assets.search_vector IS '由应用侧分词/写入；不要假设 simple 配置能处理中文';

-- -----------------------------------------------------------------------------
-- 3. 统一时间线 & 双向实体关联
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS archive.timeline_events (
    event_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title            VARCHAR(255) NOT NULL,
    summary          TEXT,
    domain           archive.life_domain NOT NULL,
    event_type       VARCHAR(64) NOT NULL,
    occurred_at      TIMESTAMPTZ NOT NULL,
    ended_at         TIMESTAMPTZ,
    time_span        TSTZRANGE GENERATED ALWAYS AS (
                         tstzrange(occurred_at, COALESCE(ended_at, occurred_at), '[]')
                     ) STORED,
    importance_score SMALLINT NOT NULL DEFAULT 5 CHECK (importance_score BETWEEN 1 AND 10),
    energy_impact    SMALLINT NOT NULL DEFAULT 0 CHECK (energy_impact BETWEEN -5 AND 5),
    duration_minutes INTEGER CHECK (duration_minutes >= 0),
    location_name    VARCHAR(128),
    geo_coords       POINT,
    source_table     VARCHAR(64),
    source_id        UUID,
    tags             TEXT[] NOT NULL DEFAULT '{}',
    metrics_payload  JSONB NOT NULL DEFAULT '{}'::jsonb,
    privacy          archive.privacy_level NOT NULL DEFAULT 'PRIVATE',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_timeline_source_entity UNIQUE (source_table, source_id),
    CONSTRAINT chk_timeline_time_order CHECK (ended_at IS NULL OR ended_at >= occurred_at)
);

COMMENT ON TABLE archive.timeline_events IS '统一时间线主表；业务表通过 source_table/source_id 幂等同步';

CREATE TABLE IF NOT EXISTS archive.entity_links (
    link_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_type     VARCHAR(64) NOT NULL,
    from_id       UUID NOT NULL,
    to_type       VARCHAR(64) NOT NULL,
    to_id         UUID NOT NULL,
    relation_type VARCHAR(64) NOT NULL DEFAULT 'RELATED_TO',
    note          TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_entity_link UNIQUE (from_type, from_id, to_type, to_id, relation_type)
);

COMMENT ON TABLE archive.entity_links IS '弱关联表：不加强制外键，由应用维护多态实体关系';

-- -----------------------------------------------------------------------------
-- 4. 阅读：书目 + 阅读日志/批注
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS archive.reading_items (
    item_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_type      VARCHAR(32) NOT NULL DEFAULT 'BOOK',
    title          VARCHAR(512) NOT NULL,
    subtitle       VARCHAR(512),
    authors        TEXT[] NOT NULL DEFAULT '{}',
    isbn_or_doi    VARCHAR(64),
    publisher      VARCHAR(128),
    publish_year   SMALLINT,
    language       VARCHAR(16) NOT NULL DEFAULT 'zh-CN',
    status         VARCHAR(32) NOT NULL DEFAULT 'WISHLIST'
                   CHECK (status IN ('WISHLIST', 'READING', 'COMPLETED', 'ABANDONED')),
    total_pages    INTEGER CHECK (total_pages > 0),
    current_page   INTEGER NOT NULL DEFAULT 0 CHECK (current_page >= 0),
    rating         NUMERIC(3, 1) CHECK (rating >= 0 AND rating <= 10.0),
    core_takeaways TEXT,
    domain         archive.life_domain NOT NULL DEFAULT 'LEARNING_EXAM',
    tags           TEXT[] NOT NULL DEFAULT '{}',
    file_asset_id  UUID REFERENCES archive.archive_assets(asset_id) ON DELETE SET NULL,
    cover_asset_id UUID REFERENCES archive.archive_assets(asset_id) ON DELETE SET NULL,
    started_at     DATE,
    finished_at    DATE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_reading_pages CHECK (
        total_pages IS NULL OR current_page <= total_pages
    ),
    CONSTRAINT chk_reading_dates CHECK (
        finished_at IS NULL OR started_at IS NULL OR finished_at >= started_at
    )
);

CREATE TABLE IF NOT EXISTS archive.reading_logs (
    log_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id          UUID NOT NULL REFERENCES archive.reading_items(item_id) ON DELETE CASCADE,
    log_type         VARCHAR(32) NOT NULL DEFAULT 'SESSION'
                     CHECK (log_type IN ('SESSION', 'HIGHLIGHT', 'THOUGHT', 'NOTE')),
    started_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    duration_minutes INTEGER NOT NULL DEFAULT 0 CHECK (duration_minutes >= 0),
    start_page       INTEGER CHECK (start_page IS NULL OR start_page >= 0),
    end_page         INTEGER CHECK (end_page IS NULL OR end_page >= 0),
    pages_read       INTEGER GENERATED ALWAYS AS (
                         GREATEST(0, COALESCE(end_page, 0) - COALESCE(start_page, 0))
                     ) STORED,
    chapter_title    VARCHAR(255),
    quote_text       TEXT,
    comment_markdown TEXT,
    embedding        vector(1536),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_reading_log_pages CHECK (
        start_page IS NULL OR end_page IS NULL OR end_page >= start_page
    )
);

-- -----------------------------------------------------------------------------
-- 5. 运动：训练记录 + 每日生理基线
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS archive.fitness_workouts (
    workout_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workout_type     VARCHAR(32) NOT NULL,
    title            VARCHAR(255),
    started_at       TIMESTAMPTZ NOT NULL,
    ended_at         TIMESTAMPTZ,
    duration_minutes INTEGER NOT NULL CHECK (duration_minutes > 0),
    calories_kcal    INTEGER CHECK (calories_kcal IS NULL OR calories_kcal >= 0),
    avg_heart_rate   SMALLINT CHECK (avg_heart_rate IS NULL OR avg_heart_rate BETWEEN 30 AND 250),
    max_heart_rate   SMALLINT CHECK (max_heart_rate IS NULL OR max_heart_rate BETWEEN 30 AND 250),
    rpe_score        NUMERIC(3, 1) CHECK (rpe_score BETWEEN 1.0 AND 10.0),
    training_load    INTEGER CHECK (training_load IS NULL OR training_load >= 0),
    distance_meters  INTEGER CHECK (distance_meters IS NULL OR distance_meters >= 0),
    avg_pace_sec_km  INTEGER CHECK (avg_pace_sec_km IS NULL OR avg_pace_sec_km > 0),
    avg_cadence      SMALLINT CHECK (avg_cadence IS NULL OR avg_cadence >= 0),
    elevation_gain_m NUMERIC(6, 1),
    total_volume_kg  NUMERIC(10, 2) CHECK (total_volume_kg IS NULL OR total_volume_kg >= 0),
    total_sets       SMALLINT CHECK (total_sets IS NULL OR total_sets >= 0),
    exercise_details JSONB NOT NULL DEFAULT '[]'::jsonb,
    route_asset_id   UUID REFERENCES archive.archive_assets(asset_id) ON DELETE SET NULL,
    tags             TEXT[] NOT NULL DEFAULT '{}',
    notes            TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_workout_time_order CHECK (ended_at IS NULL OR ended_at >= started_at)
);

CREATE TABLE IF NOT EXISTS archive.fitness_biometrics (
    record_date       DATE PRIMARY KEY,
    weight_kg         NUMERIC(5, 2) CHECK (weight_kg IS NULL OR weight_kg > 0),
    body_fat_pct      NUMERIC(4, 1) CHECK (body_fat_pct IS NULL OR body_fat_pct BETWEEN 0 AND 70),
    resting_hr        SMALLINT CHECK (resting_hr IS NULL OR resting_hr BETWEEN 25 AND 150),
    hrv_ms            SMALLINT CHECK (hrv_ms IS NULL OR hrv_ms >= 0),
    sleep_hours       NUMERIC(4, 2) CHECK (sleep_hours IS NULL OR sleep_hours BETWEEN 0 AND 24),
    deep_sleep_hours  NUMERIC(4, 2) CHECK (deep_sleep_hours IS NULL OR deep_sleep_hours BETWEEN 0 AND 24),
    steps_count       INTEGER CHECK (steps_count IS NULL OR steps_count >= 0),
    subjective_energy SMALLINT CHECK (subjective_energy IS NULL OR subjective_energy BETWEEN 1 AND 10),
    extra_metrics     JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 6. 结构化项目与周期复盘
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS archive.project_retrospectives (
    retro_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retro_type          VARCHAR(32) NOT NULL,
    domain              archive.life_domain NOT NULL,
    title               VARCHAR(255) NOT NULL,
    period_start        DATE NOT NULL,
    period_end          DATE NOT NULL,
    initial_hypothesis  TEXT,
    actual_execution    TEXT,
    root_cause_analysis TEXT,
    codified_principles TEXT,
    kpi_snapshot        JSONB NOT NULL DEFAULT '{}'::jsonb,
    action_items        JSONB NOT NULL DEFAULT '[]'::jsonb,
    execution_score     SMALLINT CHECK (execution_score BETWEEN 1 AND 10),
    outcome_score       SMALLINT CHECK (outcome_score BETWEEN 1 AND 10),
    tags                TEXT[] NOT NULL DEFAULT '{}',
    embedding           vector(1536),
    privacy             archive.privacy_level NOT NULL DEFAULT 'PRIVATE',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_retro_period CHECK (period_end >= period_start)
);

-- -----------------------------------------------------------------------------
-- 7. 基础索引（HNSW/trgm 在 05 中补充）
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_timeline_occurred
    ON archive.timeline_events (occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_timeline_span_gist
    ON archive.timeline_events USING GIST (time_span);
CREATE INDEX IF NOT EXISTS idx_timeline_domain_type
    ON archive.timeline_events (domain, event_type);
CREATE INDEX IF NOT EXISTS idx_timeline_tags_gin
    ON archive.timeline_events USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_timeline_payload_gin
    ON archive.timeline_events USING GIN (metrics_payload);
CREATE INDEX IF NOT EXISTS idx_timeline_source
    ON archive.timeline_events (source_table, source_id);
CREATE INDEX IF NOT EXISTS idx_timeline_privacy
    ON archive.timeline_events (privacy, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_entity_links_from
    ON archive.entity_links (from_type, from_id);
CREATE INDEX IF NOT EXISTS idx_entity_links_to
    ON archive.entity_links (to_type, to_id);

CREATE INDEX IF NOT EXISTS idx_reading_status
    ON archive.reading_items (status, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_reading_domain
    ON archive.reading_items (domain);
CREATE INDEX IF NOT EXISTS idx_reading_tags_gin
    ON archive.reading_items USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_reading_started
    ON archive.reading_items (started_at DESC);
CREATE INDEX IF NOT EXISTS idx_reading_finished
    ON archive.reading_items (finished_at DESC);

CREATE INDEX IF NOT EXISTS idx_reading_logs_item_started
    ON archive.reading_logs (item_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_reading_logs_type
    ON archive.reading_logs (log_type, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_workouts_started
    ON archive.fitness_workouts (started_at DESC);
CREATE INDEX IF NOT EXISTS idx_workouts_type
    ON archive.fitness_workouts (workout_type, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_biometrics_date
    ON archive.fitness_biometrics (record_date DESC);

CREATE INDEX IF NOT EXISTS idx_retro_period
    ON archive.project_retrospectives (period_end DESC);
CREATE INDEX IF NOT EXISTS idx_retro_domain
    ON archive.project_retrospectives (domain, retro_type);
CREATE INDEX IF NOT EXISTS idx_retro_tags_gin
    ON archive.project_retrospectives USING GIN (tags);

CREATE INDEX IF NOT EXISTS idx_assets_category
    ON archive.archive_assets (asset_category, captured_at DESC);
CREATE INDEX IF NOT EXISTS idx_assets_tier
    ON archive.archive_assets (current_tier, file_size_bytes DESC);
CREATE INDEX IF NOT EXISTS idx_assets_tags_gin
    ON archive.archive_assets USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_assets_media_gin
    ON archive.archive_assets USING GIN (media_metadata);
CREATE INDEX IF NOT EXISTS idx_assets_domain
    ON archive.archive_assets (domain, captured_at DESC);

-- -----------------------------------------------------------------------------
-- 8. Wolfram 式周度可计算生命看板
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW archive.v_weekly_life_analytics AS
WITH weeks AS (
    SELECT generate_series(
        date_trunc('week', NOW() - INTERVAL '1 year'),
        date_trunc('week', NOW()),
        INTERVAL '1 week'
    )::date AS week_start
),
reading_agg AS (
    SELECT date_trunc('week', started_at)::date AS week_start,
           SUM(duration_minutes) / 60.0 AS reading_hours,
           SUM(pages_read) AS total_pages_read
    FROM archive.reading_logs
    WHERE log_type = 'SESSION'
    GROUP BY 1
),
fitness_agg AS (
    SELECT date_trunc('week', started_at)::date AS week_start,
           COUNT(*) AS workout_sessions,
           SUM(duration_minutes) / 60.0 AS workout_hours,
           SUM(COALESCE(distance_meters, 0)) / 1000.0 AS running_km,
           SUM(COALESCE(total_volume_kg, 0)) / 1000.0 AS strength_tonnage
    FROM archive.fitness_workouts
    GROUP BY 1
),
biometrics_agg AS (
    SELECT date_trunc('week', record_date)::date AS week_start,
           ROUND(AVG(sleep_hours), 2) AS avg_sleep_hours,
           ROUND(AVG(resting_hr), 1) AS avg_resting_hr,
           ROUND(AVG(weight_kg), 2) AS avg_weight_kg
    FROM archive.fitness_biometrics
    GROUP BY 1
),
retro_agg AS (
    SELECT date_trunc('week', period_end)::date AS week_start,
           COUNT(*) AS retro_count,
           ROUND(AVG(execution_score), 1) AS avg_execution_score
    FROM archive.project_retrospectives
    GROUP BY 1
)
SELECT
    w.week_start,
    COALESCE(ROUND(r.reading_hours, 1), 0)     AS reading_hours,
    COALESCE(r.total_pages_read, 0)            AS pages_read,
    COALESCE(f.workout_sessions, 0)            AS workouts,
    COALESCE(ROUND(f.workout_hours, 1), 0)     AS workout_hours,
    COALESCE(ROUND(f.running_km, 1), 0)        AS running_km,
    COALESCE(ROUND(f.strength_tonnage, 2), 0)  AS strength_tonnage,
    b.avg_sleep_hours,
    b.avg_resting_hr,
    b.avg_weight_kg,
    COALESCE(rt.retro_count, 0)                AS retro_completed,
    rt.avg_execution_score
FROM weeks w
LEFT JOIN reading_agg r    ON w.week_start = r.week_start
LEFT JOIN fitness_agg f    ON w.week_start = f.week_start
LEFT JOIN biometrics_agg b ON w.week_start = b.week_start
LEFT JOIN retro_agg rt     ON w.week_start = rt.week_start
ORDER BY w.week_start DESC;

COMMENT ON VIEW archive.v_weekly_life_analytics IS '近 52 周阅读/运动/睡眠/复盘聚合；看板主数据源';

CREATE OR REPLACE VIEW archive.v_asset_storage_summary AS
SELECT
    current_tier,
    asset_category,
    COUNT(*) AS asset_count,
    SUM(file_size_bytes) AS total_bytes,
    pg_size_pretty(SUM(file_size_bytes)) AS total_pretty
FROM archive.archive_assets
WHERE deleted_at IS NULL
GROUP BY current_tier, asset_category
ORDER BY current_tier, total_bytes DESC;

COMMENT ON VIEW archive.v_asset_storage_summary IS '数字资产按存储层级/类别的容量汇总';

CREATE OR REPLACE VIEW archive.v_recent_timeline AS
SELECT
    event_id, title, domain, event_type, occurred_at, ended_at,
    importance_score, energy_impact, duration_minutes,
    source_table, source_id, tags, metrics_payload, privacy
FROM archive.timeline_events
WHERE occurred_at >= NOW() - INTERVAL '90 days'
ORDER BY occurred_at DESC;
