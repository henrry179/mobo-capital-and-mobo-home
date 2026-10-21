-- ============================================================================
-- 文件路径: /opt/mobo-stack/init-scripts/02-archive-schema.sql
-- 目标数据库: db_archive (莫伯之家 MoBoHome.com 专属库)
-- 核心功能: 5 大生命档案核心模块表 + 周度聚合分析视图 v_weekly_life_analytics
-- ============================================================================

\connect db_archive user_archive;

-- 模块 1: 人生时间线与成长故事主表 (timeline_events) 及实体多对多关联表 (entity_links)
CREATE TABLE IF NOT EXISTS timeline_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_date DATE NOT NULL,
    event_timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    category VARCHAR(32) NOT NULL
        CHECK (category IN ('career', 'milestone', 'reading', 'fitness', 'reflection', 'project')),
    title VARCHAR(256) NOT NULL,
    summary TEXT,
    location_name VARCHAR(64) DEFAULT '武汉',
    importance SMALLINT DEFAULT 3 CHECK (importance BETWEEN 1 AND 5),
    mood_score SMALLINT CHECK (mood_score BETWEEN 1 AND 10),
    energy_score SMALLINT CHECK (energy_score BETWEEN 1 AND 10),
    tags TEXT[] DEFAULT '{}',
    metadata JSONB DEFAULT '{}'::jsonb,
    source_table VARCHAR(64),
    source_record_id UUID,
    is_sensitive BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (source_table, source_record_id)
);

CREATE INDEX idx_timeline_date ON timeline_events(event_date DESC, category);
CREATE INDEX idx_timeline_tags ON timeline_events USING gin(tags);

CREATE TABLE IF NOT EXISTS entity_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_type VARCHAR(32) NOT NULL,
    source_id UUID NOT NULL,
    target_type VARCHAR(32) NOT NULL,
    target_id UUID NOT NULL,
    relation_type VARCHAR(32) DEFAULT 'related_to',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (source_type, source_id, target_type, target_id, relation_type)
);

-- 模块 2: 百本跨学科藏书馆 (reading_items) 与阅读笔记 (reading_logs)
CREATE TABLE IF NOT EXISTS reading_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_type VARCHAR(20) DEFAULT 'BOOK' CHECK (item_type IN ('BOOK', 'PAPER', 'COURSE')),
    title VARCHAR(256) NOT NULL,
    author VARCHAR(128),
    category VARCHAR(32) NOT NULL DEFAULT 'FINANCE',
    status VARCHAR(20) DEFAULT 'IN_PROGRESS'
        CHECK (status IN ('WISHLIST', 'IN_PROGRESS', 'COMPLETED', 'RE_READING')),
    rating SMALLINT CHECK (rating BETWEEN 1 AND 5),
    started_date DATE,
    completed_date DATE,
    core_takeaway TEXT,
    tags TEXT[] DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS reading_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reading_item_id UUID NOT NULL REFERENCES reading_items(id) ON DELETE CASCADE,
    log_date DATE NOT NULL DEFAULT CURRENT_DATE,
    chapter_or_pages VARCHAR(64),
    duration_minutes INTEGER DEFAULT 30,
    notes_markdown TEXT NOT NULL,
    embedding vector(1536),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 模块 3: 体能自律训练表 (fitness_workouts) 与身体机能表 (fitness_biometrics)
CREATE TABLE IF NOT EXISTS fitness_workouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workout_date DATE NOT NULL DEFAULT CURRENT_DATE,
    workout_type VARCHAR(32) NOT NULL
        CHECK (workout_type IN ('running', 'strength', 'hiit', 'swimming', 'hiking')),
    duration_minutes INTEGER NOT NULL CHECK (duration_minutes > 0),
    distance_km NUMERIC(5,2),
    avg_heart_rate SMALLINT,
    rpe_score SMALLINT CHECK (rpe_score BETWEEN 1 AND 10),
    calories_burned INTEGER,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS fitness_biometrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    record_date DATE UNIQUE NOT NULL DEFAULT CURRENT_DATE,
    weight_kg NUMERIC(5,2),
    body_fat_pct NUMERIC(4,1),
    resting_hr SMALLINT,
    sleep_hours NUMERIC(4,2),
    sleep_quality_score SMALLINT CHECK (sleep_quality_score BETWEEN 1 AND 10),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 模块 4: 周期与项目复盘表 (project_retrospectives)
CREATE TABLE IF NOT EXISTS project_retrospectives (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    review_period VARCHAR(32) UNIQUE NOT NULL,
    period_type VARCHAR(20) NOT NULL
        CHECK (period_type IN ('weekly', 'monthly', 'quarterly', 'annual', 'project')),
    review_date DATE NOT NULL DEFAULT CURRENT_DATE,
    title VARCHAR(256) NOT NULL,
    achievements TEXT,
    bottlenecks TEXT,
    next_actions TEXT,
    content_markdown TEXT NOT NULL,
    embedding vector(1536),
    is_sensitive BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 模块 5: 多媒体数字资产归档表 (archive_assets - 对接 OSS 冷热分层)
CREATE TABLE IF NOT EXISTS archive_assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_type VARCHAR(24) NOT NULL
        CHECK (asset_type IN ('photo', 'video', 'scan_doc', 'audio', 'certificate')),
    title VARCHAR(256) NOT NULL,
    captured_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    oss_bucket VARCHAR(64) NOT NULL,
    oss_object_key TEXT NOT NULL,
    oss_thumbnail_key TEXT,
    file_sha256 CHAR(64) UNIQUE NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    mime_type VARCHAR(64),
    storage_class VARCHAR(24) DEFAULT 'Standard',
    extracted_text TEXT,
    exif_or_meta JSONB DEFAULT '{}'::jsonb,
    linked_event_id UUID REFERENCES timeline_events(id) ON DELETE SET NULL,
    is_sensitive BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_assets_type_date ON archive_assets(asset_type, captured_at DESC);

-- 聚合视图: 周度生命体征、运动里程与阅读时长分析视图 (v_weekly_life_analytics)
CREATE OR REPLACE VIEW v_weekly_life_analytics AS
WITH weeks AS (
    SELECT generate_series(
        date_trunc('week', CURRENT_DATE - INTERVAL '25 weeks'),
        date_trunc('week', CURRENT_DATE),
        INTERVAL '1 week'
    )::date AS week_start
)
SELECT 
    to_char(w.week_start, 'IYYY-"W"IW') AS iso_week,
    w.week_start,
    COALESCE(fw.workout_sessions, 0) AS workout_sessions,
    COALESCE(fw.total_workout_mins, 0) AS total_workout_mins,
    COALESCE(fw.running_km, 0.0) AS running_km,
    COALESCE(rl.reading_mins, 0) AS reading_mins,
    ROUND(te.avg_mood, 1) AS avg_mood_score,
    ROUND(te.avg_energy, 1) AS avg_energy_score,
    ROUND(fb.avg_sleep_hours, 2) AS avg_sleep_hours
FROM weeks w
LEFT JOIN (
    SELECT date_trunc('week', workout_date)::date AS wk,
           COUNT(*) AS workout_sessions,
           SUM(duration_minutes) AS total_workout_mins,
           SUM(COALESCE(distance_km, 0)) FILTER (WHERE workout_type = 'running') AS running_km
    FROM fitness_workouts
    GROUP BY 1
) fw ON w.week_start = fw.wk
LEFT JOIN (
    SELECT date_trunc('week', log_date)::date AS wk,
           SUM(duration_minutes) AS reading_mins
    FROM reading_logs
    GROUP BY 1
) rl ON w.week_start = rl.wk
LEFT JOIN (
    SELECT date_trunc('week', event_date)::date AS wk,
           AVG(mood_score) AS avg_mood,
           AVG(energy_score) AS avg_energy
    FROM timeline_events
    GROUP BY 1
) te ON w.week_start = te.wk
LEFT JOIN (
    SELECT date_trunc('week', record_date)::date AS wk,
           AVG(sleep_hours) AS avg_sleep_hours
    FROM fitness_biometrics
    GROUP BY 1
) fb ON w.week_start = fb.wk
ORDER BY w.week_start DESC;