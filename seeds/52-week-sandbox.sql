-- =============================================================================
-- 52-week-sandbox.sql
-- 仅用于本地开发/演示；不要在生产库执行。
-- 内容：365 天生理基线、52 周训练、52 周复盘、12 本书与阅读日志。
-- 幂等：ON CONFLICT / NOT EXISTS。
-- =============================================================================
\set ON_ERROR_STOP on
\c db_archive

BEGIN;

-- 1) 365 天生理基线
INSERT INTO archive.fitness_biometrics (
    record_date, weight_kg, body_fat_pct, resting_hr, hrv_ms,
    sleep_hours, deep_sleep_hours, steps_count, subjective_energy, extra_metrics
)
SELECT
    d::date,
    ROUND((70.0 + 0.8 * sin(extract(doy FROM d) / 365.0 * 2 * pi()) + (random() - 0.5) * 0.4)::numeric, 2),
    ROUND((18.0 + 0.6 * sin(extract(doy FROM d) / 365.0 * 2 * pi()) + (random() - 0.5) * 0.3)::numeric, 1),
    (56 + (random() * 6))::int,
    (45 + (random() * 20))::int,
    ROUND((7.2 + 0.3 * sin(extract(doy FROM d) / 365.0 * 2 * pi()) + (random() - 0.5) * 0.5)::numeric, 2),
    ROUND((1.6 + (random() * 0.8))::numeric, 2),
    (7000 + (random() * 5000))::int,
    (6 + (random() * 4))::int,
    '{"source":"sandbox"}'::jsonb
FROM generate_series(CURRENT_DATE - INTERVAL '364 days', CURRENT_DATE, INTERVAL '1 day') AS d
ON CONFLICT (record_date) DO NOTHING;

-- 2) 52 周跑步（全部在过去，避免未来事件）
INSERT INTO archive.fitness_workouts (
    workout_type, title, started_at, ended_at, duration_minutes,
    calories_kcal, avg_heart_rate, max_heart_rate, rpe_score,
    distance_meters, avg_pace_sec_km, tags, notes
)
SELECT
    'RUNNING',
    '沙盒跑步 ' || i,
    date_trunc('week', CURRENT_DATE) - INTERVAL '7 days' - (i || ' weeks')::interval + INTERVAL '2 days 7 hours',
    date_trunc('week', CURRENT_DATE) - INTERVAL '7 days' - (i || ' weeks')::interval + INTERVAL '2 days 7 hours 50 minutes',
    50,
    (450 + i * 3)::int,
    148,
    172,
    ROUND((5.5 + (i % 3) * 0.7)::numeric, 1),
    8000 + (i % 3) * 1000,
    330 + (i % 5) * 5,
    ARRAY['sandbox', 'running'],
    '沙盒训练数据'
FROM generate_series(0, 51) AS i
WHERE NOT EXISTS (
    SELECT 1 FROM archive.fitness_workouts w WHERE w.title = '沙盒跑步 ' || i
);

-- 3) 52 周复盘
WITH weeks AS (
    SELECT generate_series(
        date_trunc('week', CURRENT_DATE) - INTERVAL '52 weeks',
        date_trunc('week', CURRENT_DATE) - INTERVAL '1 week',
        INTERVAL '1 week'
    )::date AS week_start
)
INSERT INTO archive.project_retrospectives (
    retro_type, domain, title, period_start, period_end,
    initial_hypothesis, actual_execution, root_cause_analysis,
    codified_principles, kpi_snapshot, action_items,
    execution_score, outcome_score, tags, privacy
)
SELECT
    'WEEKLY',
    'SYSTEM_TECH',
    '沙盒周复盘 ' || to_char(week_start, 'IYYY-IW'),
    week_start,
    week_start + 6,
    '本周优先保证阅读与训练。',
    '完成部分计划；出差/临时任务造成中断。',
    '未预留缓冲，导致晚间计划被挤压。',
    '每周日晚上做下周排期，并预留两个空档。',
    jsonb_build_object('阅读小时', 5.5, '训练次数', 3, '睡眠', 7.1),
    '[{"text":"周日晚排期","owner":"我"}]'::jsonb,
    7,
    6,
    ARRAY['sandbox', 'weekly'],
    'PRIVATE'
FROM weeks w
WHERE NOT EXISTS (
    SELECT 1 FROM archive.project_retrospectives r
    WHERE r.title = '沙盒周复盘 ' || to_char(w.week_start, 'IYYY-IW')
);

-- 4) 12 本书（COMPLETED 会触发时间线）
WITH books AS (
    SELECT * FROM (VALUES
        ('沙盒阅读 01', '作者 A'), ('沙盒阅读 02', '作者 B'),
        ('沙盒阅读 03', '作者 C'), ('沙盒阅读 04', '作者 D'),
        ('沙盒阅读 05', '作者 E'), ('沙盒阅读 06', '作者 F'),
        ('沙盒阅读 07', '作者 G'), ('沙盒阅读 08', '作者 H'),
        ('沙盒阅读 09', '作者 I'), ('沙盒阅读 10', '作者 J'),
        ('沙盒阅读 11', '作者 K'), ('沙盒阅读 12', '作者 L')
    ) AS t(title, author)
)
INSERT INTO archive.reading_items (
    title, authors, status, total_pages, current_page, rating,
    core_takeaways, domain, tags, started_at, finished_at
)
SELECT
    title,
    ARRAY[author],
    'COMPLETED',
    300,
    300,
    8.0,
    '沙盒数据：用于看板与触发器演示。',
    'LEARNING_EXAM',
    ARRAY['sandbox', 'reading'],
    CURRENT_DATE - (row_number() OVER (ORDER BY title) * 7 + 30),
    CURRENT_DATE - (row_number() OVER (ORDER BY title) * 7)
FROM books b
WHERE NOT EXISTS (
    SELECT 1 FROM archive.reading_items r WHERE r.title = b.title
);

-- 5) 阅读日志（刷新完读时间线的时长）
INSERT INTO archive.reading_logs (
    item_id, log_type, duration_minutes, start_page, end_page, comment_markdown
)
SELECT r.item_id, 'SESSION', 90, 1, 300, '沙盒阅读日志'
FROM archive.reading_items r
WHERE r.title LIKE '沙盒阅读 %'
  AND NOT EXISTS (
      SELECT 1 FROM archive.reading_logs l WHERE l.item_id = r.item_id
  );

COMMIT;

-- 对账
SELECT 'biometrics' AS t, count(*) FROM archive.fitness_biometrics
UNION ALL SELECT 'workouts', count(*) FROM archive.fitness_workouts
UNION ALL SELECT 'retros', count(*) FROM archive.project_retrospectives
UNION ALL SELECT 'reading', count(*) FROM archive.reading_items
UNION ALL SELECT 'timeline', count(*) FROM archive.timeline_events;
