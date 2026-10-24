-- =============================================================================
-- 看板四模块「真实数据库」校验
--
-- 用途：质量门 Q17。确认 Streamlit 看板（services/archive-dashboard）的四个模块
--       —— 周度节律/Z-Score、Lead-Lag、时间线、资产总账 —— 的数据源在 db_archive
--       里确实有可渲染的行，而不是全部落到内存合成沙盒。
--
-- 输出：先打四行明细，再打一行结论（DASHBOARD REAL DATA OK / MISSING）。
-- =============================================================================
\pset pager off
\pset tuples_only off

WITH modules AS (
    SELECT
        '周度节律 / Lead-Lag'::text AS module,
        'archive.v_weekly_life_analytics'::text AS source,
        (SELECT count(*) FROM archive.v_weekly_life_analytics)::bigint AS rows,
        (SELECT count(*) FROM archive.v_weekly_life_analytics
          WHERE reading_hours IS NOT NULL
             OR avg_sleep_hours IS NOT NULL
             OR workouts > 0
             OR retro_completed > 0)::bigint AS meaningful
    UNION ALL
    SELECT
        '时间线',
        'archive.timeline_events',
        (SELECT count(*) FROM archive.timeline_events),
        (SELECT count(*) FROM archive.timeline_events
          WHERE occurred_at >= NOW() - INTERVAL '90 days')
    UNION ALL
    SELECT
        '资产总账',
        'archive.archive_assets',
        (SELECT count(*) FROM archive.archive_assets),
        (SELECT count(*) FROM archive.archive_assets WHERE deleted_at IS NULL)
)
SELECT '  ' || module || ' → ' || source || '：总行数=' || rows || '，可渲染行数=' || meaningful
FROM modules;

WITH modules AS (
    SELECT
        (SELECT count(*) FROM archive.v_weekly_life_analytics
          WHERE reading_hours IS NOT NULL
             OR avg_sleep_hours IS NOT NULL
             OR workouts > 0
             OR retro_completed > 0)::bigint AS weekly,
        (SELECT count(*) FROM archive.timeline_events
          WHERE occurred_at >= NOW() - INTERVAL '90 days')::bigint AS timeline,
        (SELECT count(*) FROM archive.archive_assets
          WHERE deleted_at IS NULL)::bigint AS assets
)
SELECT CASE
           WHEN weekly > 0 AND timeline > 0 AND assets > 0
           THEN 'DASHBOARD REAL DATA OK'
           ELSE 'DASHBOARD REAL DATA MISSING'
       END
FROM modules;
