-- =============================================================================
-- smoke.sql
-- 数据库结构与触发器冒烟测试（非破坏性；触发器用事务回滚）
-- 运行：
--   docker compose cp tests/sql/smoke.sql postgres:/tmp/smoke.sql
--   docker compose exec -T postgres psql -U postgres -d db_archive \
--     -v ON_ERROR_STOP=1 -f /tmp/smoke.sql
-- =============================================================================
\set ON_ERROR_STOP on

\echo '[1/9] db_archive 表与视图'
\c db_archive

DO $$
DECLARE
    v_missing text[];
BEGIN
    SELECT array_agg(name) INTO v_missing
    FROM (VALUES
        ('archive.archive_assets'),
        ('archive.timeline_events'),
        ('archive.entity_links'),
        ('archive.reading_items'),
        ('archive.reading_logs'),
        ('archive.fitness_workouts'),
        ('archive.fitness_biometrics'),
        ('archive.project_retrospectives'),
        ('archive.v_weekly_life_analytics'),
        ('archive.v_asset_storage_summary'),
        ('archive.v_recent_timeline')
    ) AS t(name)
    WHERE to_regclass(name) IS NULL;

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '缺少对象: %', array_to_string(v_missing, ', ');
    END IF;
    RAISE NOTICE 'OK: archive 8 表 + 3 视图齐全';
END $$;

\echo '[2/9] 时间线触发器存在性'

DO $$
DECLARE
    v_missing text[];
BEGIN
    SELECT array_agg(expected) INTO v_missing
    FROM (VALUES
        ('trg_sync_reading_to_timeline'),
        ('trg_refresh_reading_timeline_stats'),
        ('trg_sync_workout_to_timeline'),
        ('trg_sync_retro_to_timeline')
    ) AS t(expected)
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = t.expected AND NOT tgisinternal
    );

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '缺少触发器: %', array_to_string(v_missing, ', ');
    END IF;
    RAISE NOTICE 'OK: 4 个时间线触发器存在';
END $$;

\echo '[3/9] 运动 → 时间线'

BEGIN;
INSERT INTO archive.fitness_workouts (
    workout_type, title, started_at, ended_at, duration_minutes, tags
) VALUES (
    'RUNNING', 'smoke-workout-' || gen_random_uuid()::text,
    NOW() - INTERVAL '1 hour', NOW() - INTERVAL '20 minutes', 40, ARRAY['smoke']
) RETURNING workout_id AS smoke_workout_id \gset

SELECT (count(*) = 1) AS smoke_ok
FROM archive.timeline_events
WHERE source_table = 'fitness_workouts' AND source_id = :'smoke_workout_id' \gset

\if :smoke_ok
\else
    \echo 'FAIL: 运动 → 时间线触发器未生效'
    \quit 1
\endif
ROLLBACK;
\echo 'OK: 运动 → 时间线触发器（已回滚）'

\echo '[4/9] 阅读完读 → 时间线'

BEGIN;
INSERT INTO archive.reading_items (
    title, status, domain, rating, started_at, finished_at
) VALUES (
    'smoke-reading-' || gen_random_uuid()::text,
    'COMPLETED', 'LEARNING_EXAM', 8.0, CURRENT_DATE - 7, CURRENT_DATE
) RETURNING item_id AS smoke_item_id \gset

SELECT (count(*) = 1) AS smoke_ok
FROM archive.timeline_events
WHERE source_table = 'reading_items' AND source_id = :'smoke_item_id' \gset

\if :smoke_ok
\else
    \echo 'FAIL: 阅读 → 时间线触发器未生效'
    \quit 1
\endif
ROLLBACK;
\echo 'OK: 阅读 → 时间线触发器（已回滚）'

\echo '[5/9] 复盘 → 时间线'

BEGIN;
INSERT INTO archive.project_retrospectives (
    retro_type, domain, title, period_start, period_end, execution_score
) VALUES (
    'WEEKLY', 'SYSTEM_TECH', 'smoke-retro-' || gen_random_uuid()::text,
    CURRENT_DATE - 7, CURRENT_DATE, 7
) RETURNING retro_id AS smoke_retro_id \gset

SELECT (count(*) = 1) AS smoke_ok
FROM archive.timeline_events
WHERE source_table = 'project_retrospectives' AND source_id = :'smoke_retro_id' \gset

\if :smoke_ok
\else
    \echo 'FAIL: 复盘 → 时间线触发器未生效'
    \quit 1
\endif
ROLLBACK;
\echo 'OK: 复盘 → 时间线触发器（已回滚）'

\echo '[6/9] 周视图与只读权限'

SELECT (count(*) BETWEEN 52 AND 54) AS smoke_ok
FROM archive.v_weekly_life_analytics \gset
\if :smoke_ok
\else
    \echo 'FAIL: v_weekly_life_analytics 行数不在 52–54'
    \quit 1
\endif

SELECT (
    has_table_privilege('user_dashboard_ro', 'archive.archive_assets', 'SELECT')
    AND NOT has_table_privilege('user_dashboard_ro', 'archive.archive_assets', 'INSERT')
) AS smoke_ok \gset
\if :smoke_ok
\else
    \echo 'FAIL: user_dashboard_ro 权限不是只读'
    \quit 1
\endif

SELECT has_table_privilege('user_backup', 'archive.archive_assets', 'SELECT') AS smoke_ok \gset
\if :smoke_ok
\else
    \echo 'FAIL: user_backup 无 SELECT 权限'
    \quit 1
\endif
\echo 'OK: 周视图 + 只读账号'

\echo '[7/9] db_mobobrain 结构与 n8n Schema'
\c db_mobobrain

DO $$
DECLARE
    v_missing text[];
BEGIN
    SELECT array_agg(name) INTO v_missing
    FROM (VALUES
        ('intel.sources'),
        ('intel.articles_vault'),
        ('intel.content_drafts'),
        ('intel.ingestion_runs'),
        ('intel.llm_usage'),
        ('intel.v_recent_high_value')
    ) AS t(name)
    WHERE to_regclass(name) IS NULL;

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '缺少对象: %', array_to_string(v_missing, ', ');
    END IF;
    RAISE NOTICE 'OK: intel 5 表 + 1 视图齐全';
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'n8n') THEN
        RAISE EXCEPTION '缺少 n8n Schema';
    END IF;
    RAISE NOTICE 'OK: n8n Schema 存在';
END $$;

\echo '[8/9] capital 投研域（莫伯资本）'

DO $$
DECLARE
    v_missing text[];
BEGIN
    SELECT array_agg(name) INTO v_missing
    FROM (VALUES
        ('capital.macro_theses'),
        ('capital.strategy_playbooks'),
        ('capital.trade_reviews'),
        ('capital.fund_incubation_milestones'),
        ('capital.fund_governance_docs'),
        ('capital.capital_publications'),
        ('capital.media_channel_metrics'),
        ('capital.portfolio_nav_ledger'),
        ('capital.macro_indicator_series'),
        ('capital.options_vol_surface_daily'),
        ('capital.v_strategy_performance_summary'),
        ('capital.v_media_conversion_funnel'),
        ('capital.v_latest_macro_indicators'),
        ('capital.v_latest_options_vol_surface')
    ) AS t(name)
    WHERE to_regclass(name) IS NULL;

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '缺少对象: %', array_to_string(v_missing, ', ');
    END IF;
    RAISE NOTICE 'OK: capital 10 表 + 4 视图齐全';
END $$;

-- NAV 回撤熔断触发器存在
SELECT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_auto_calc_nav_on_trade' AND NOT tgisinternal
) AS smoke_ok \gset
\if :smoke_ok
\else
    \echo 'FAIL: 缺少 trg_auto_calc_nav_on_trade（NAV 回撤熔断触发器）'
    \quit 1
\endif
\echo 'OK: NAV 触发器存在'

\echo '[9/9] 双库物理隔离'

DO $$
BEGIN
    IF has_database_privilege('user_mobobrain', 'db_archive', 'CONNECT') THEN
        RAISE EXCEPTION 'user_mobobrain 不应能连接 db_archive';
    END IF;
    IF NOT has_database_privilege('user_archive', 'db_archive', 'CONNECT') THEN
        RAISE EXCEPTION 'user_archive 缺少 db_archive 连接权限';
    END IF;
    RAISE NOTICE 'OK: 跨库访问已拒绝';
END $$;

\echo 'SMOKE TEST PASSED'
