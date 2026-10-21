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
    CURRENT_DATE - ((row_number() OVER (ORDER BY title) * 7 + 30)::int),
    CURRENT_DATE - ((row_number() OVER (ORDER BY title) * 7)::int)
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

-- 6. 沙盒影像资产（用于画廊演示；公域可见性显式标为 RESTRICTED）
INSERT INTO archive.archive_assets (
    asset_category, title, original_filename, mime_type, file_size_bytes,
    sha256_hash, oss_bucket, oss_object_key, thumbnail_key, current_tier,
    captured_at, media_metadata, domain, tags, privacy
)
SELECT
    'PHOTO',
    '沙盒影像 ' || n,
    'sandbox-' || n || '.jpg',
    'image/jpeg',
    1024 * (100 + n),
    repeat('a', 56) || lpad(n::text, 8, '0'),
    'sandbox-local',
    'photo/sandbox/' || n || '.jpg',
    'thumbnails/sandbox/' || n || '.webp',
    'LOCAL_CACHE',
    CURRENT_DATE - (n * 11),
    jsonb_build_object('public_thumb_url', '/assets/placeholder.svg', 'sandbox', true),
    'FAMILY_LIFE',
    ARRAY['sandbox', 'gallery'],
    'RESTRICTED'
FROM generate_series(1, 6) AS n
WHERE NOT EXISTS (
    SELECT 1 FROM archive.archive_assets a WHERE a.sha256_hash = repeat('a', 56) || lpad(n::text, 8, '0')
);

-- 7. 沙盒数据标记为"可用于公域演示"（真实数据的默认 PRIVATE 不会被导出）
UPDATE archive.timeline_events
SET privacy = 'RESTRICTED'
WHERE title LIKE '沙盒%';

UPDATE archive.project_retrospectives
SET privacy = 'RESTRICTED'
WHERE title LIKE '沙盒%';

COMMIT;

-- 对账
SELECT 'biometrics' AS t, count(*) FROM archive.fitness_biometrics
UNION ALL SELECT 'workouts', count(*) FROM archive.fitness_workouts
UNION ALL SELECT 'retros', count(*) FROM archive.project_retrospectives
UNION ALL SELECT 'reading', count(*) FROM archive.reading_items
UNION ALL SELECT 'timeline', count(*) FROM archive.timeline_events;

-- =============================================================================
-- 莫伯资本侧沙盒（量化终端 + 发布队列 + 渠道指标）
-- =============================================================================
\c db_mobobrain
SET search_path TO capital, public;

BEGIN;

-- 宏观先行指标序列（12 个指标 × 26 周）
INSERT INTO capital.macro_indicator_series (
    indicator_code, indicator_name, region, frequency, obs_date,
    raw_value, prev_value, change_val, z_score, regime_tag
)
SELECT
    code, name, region, freq,
    (CURRENT_DATE - (w * 7))::date,
    round((base + sin(w / 3.0) * amp + (w % 5) * 0.11)::numeric, 4),
    round((base + sin((w - 1) / 3.0) * amp)::numeric, 4),
    round((sin(w / 3.0) * amp * 0.4)::numeric, 4),
    round((sin(w / 3.0) * 1.35)::numeric, 2),
    CASE
        WHEN sin(w / 3.0) > 0.55 THEN 'EXPANSION'
        WHEN sin(w / 3.0) > 0.15 THEN 'IMPROVING'
        WHEN sin(w / 3.0) < -0.55 THEN 'CONTRACTION'
        WHEN sin(w / 3.0) < -0.15 THEN 'BOTTOMING'
        ELSE 'NEUTRAL'
    END
FROM (
    SELECT
        w,
        code, name, region, freq, base, amp
    FROM generate_series(0, 25) AS w
    CROSS JOIN (VALUES
        ('CN_PMI_NEW_ORDERS', '中国制造业 PMI 新订单', 'CN', 'MONTHLY', 51.2::numeric, 1.6::numeric),
        ('CN_PMI_PRICE',      '中国制造业 PMI 出厂价格', 'CN', 'MONTHLY', 47.4::numeric, 1.2::numeric),
        ('US_ISM_NEW_ORDERS', '美国 ISM 制造业新订单', 'US', 'MONTHLY', 49.1::numeric, 1.1::numeric),
        ('US10Y_YIELD',       '美债 10 年期收益率', 'US', 'DAILY', 4.16::numeric, 0.28::numeric),
        ('CN_SOCIAL_FINANCE', '社会融资规模存量同比', 'CN', 'MONTHLY', 8.3::numeric, 0.4::numeric),
        ('EU_PMI_MFG',        '欧元区制造业 PMI', 'EU', 'MONTHLY', 46.8::numeric, 0.9::numeric),
        ('VIX',               'VIX 恐慌指数', 'US', 'DAILY', 16.2::numeric, 2.4::numeric),
        ('GOLD_USD',          '伦敦金（美元/盎司）', 'GLOBAL', 'DAILY', 2660.0::numeric, 42.0::numeric),
        ('BRENT',             '布伦特原油', 'GLOBAL', 'DAILY', 74.8::numeric, 3.6::numeric),
        ('USD_CNH',           '美元兑离岸人民币', 'GLOBAL', 'DAILY', 7.12::numeric, 0.05::numeric),
        ('CN_SOCIAL_RETAIL',  '中国社会消费品零售同比', 'CN', 'MONTHLY', 3.9::numeric, 0.7::numeric),
        ('US_PAYROLL',        '美国非农就业新增', 'US', 'MONTHLY', 168.0::numeric, 22.0::numeric)
    ) AS t(code, name, region, freq, base, amp)
) AS src
ON CONFLICT (indicator_code, obs_date) DO NOTHING;

-- 期权波动率曲面日频快照
INSERT INTO capital.options_vol_surface_daily (
    underlying_ticker, asset_name, trade_date, spot_price, daily_change_pct,
    iv_30d, hv_30d, vrp_spread, iv_rank_1y, iv_percentile_1y, skew_25d,
    recommended_structure
)
SELECT
    ticker, name, (CURRENT_DATE - (d * 7))::date,
    round((spot + d * 0.12)::numeric, 4),
    round((sin(d / 2.0) * 0.8)::numeric, 2),
    round((iv + sin(d / 3.0) * 1.2)::numeric, 2),
    round((hv + sin(d / 3.0) * 0.9)::numeric, 2),
    round((iv - hv + sin(d / 3.0) * 0.6)::numeric, 2),
    round((rank + sin(d / 4.0) * 6)::numeric, 2),
    round((rank + sin(d / 4.0) * 6)::numeric, 2),
    round((skew + sin(d / 5.0) * 0.8)::numeric, 2),
    CASE
        WHEN rank < 35 THEN '低 IV + 正偏度：1x2 Ratio Spread / Calendar'
        WHEN rank > 70 THEN '高 IV：短波动率 / 卖方收割'
        ELSE '中性偏度：45DTE Debit Spread'
    END
FROM (
    SELECT
        d, ticker, name, spot, iv, hv, rank, skew
    FROM generate_series(0, 25) AS d
    CROSS JOIN (VALUES
        ('510300.SH', '沪深300ETF期权', 3.98::numeric, 19.8::numeric, 21.6::numeric, 28.4::numeric, 4.6::numeric),
        ('SPY',       'SPDR 标普500 ETF', 684.2::numeric, 16.4::numeric, 15.1::numeric, 42.7::numeric, 3.1::numeric),
        ('GLD',       'SPDR 黄金 ETF',   312.7::numeric, 14.2::numeric, 13.5::numeric, 33.1::numeric, 2.4::numeric),
        ('159915.SZ', '创业板 ETF 期权', 2.06::numeric, 24.6::numeric, 26.2::numeric, 55.8::numeric, 5.2::numeric)
    ) AS t(ticker, name, spot, iv, hv, rank, skew)
) AS src
ON CONFLICT (underlying_ticker, trade_date) DO NOTHING;

-- 发布队列（阶段一产出，待人工终审）
INSERT INTO capital.capital_publications (
    slug, category, title, summary, web_markdown, wechat_html,
    xueqiu_markdown, x_thread_json, tags, visibility, publish_status, published_at
)
SELECT * FROM (VALUES
    ('macro-pmi-divergence-vol-mispricing', 'MACRO',
     'PMI 分歧期的波动率错配：跨式与偏度的赔率结构',
     '价格分项与新订单背离，隐含波动率仍处低分位，本文拆解跨式与偏度结构的赔率差异。',
     '---
title: PMI 分歧期的波动率错配
date: 2026-10-12
category: MACRO
tags: [宏观, 波动率]
---

## 核心结论
制造业价格分项持续走弱而新订单温和回升，波动率曲面因此呈现"隐含下行、尾部偏度抬升"的错配结构。',
     '<p style="font-size:15px;line-height:1.8;color:#2c3e50;margin-bottom:16px;">制造业价格分项持续走弱而新订单温和回升，波动率曲面因此呈现"隐含下行、尾部偏度抬升"的错配结构。</p><p style="font-size:13px;color:#94a3b8;">【风控与合规声明】本文系莫伯个人宏观与量化交易体系的学术复盘笔记，首发于 MoBoCapital.com，不构成任何证券投资建议或收益承诺。市场有风险，决策需独立。</p>',
     '结论先行：当价格分项与新订单背离，隐含波动率的错配往往先于方向兑现。$沪深300(SH000300)$ 的 30D IV 仍在低分位区间。',
     '["1/6  Vol is cheap, positioning is not. A divergence between PMI new orders and prices is the classic setup for a volatility mispricing.","2/6  When implied vol sits in the bottom decile but skew keeps rising, smart money is paying for protection.","3/6  The trade: own convexity, cap the tail. 1x2 ratio spreads over 45DTE.","4/6  Risk: if the divergence closes through demand, the spread flattens fast. Size accordingly.","5/6  Discipline: max 1.25% NAV per structure, no exceptions.","6/6  Full framework and the invalidation criteria: https://mobocapital.com/memo/macro-pmi-divergence-vol-mispricing"]'::jsonb,
     ARRAY['宏观','波动率'], 'PUBLIC', 'PUBLISHED', '2026-10-12T09:30:00+08'::timestamptz),
    ('playbook-iv-skew-01', 'STRATEGY',
     '策略手册 01：波动率偏度策略的进出场铁律',
     '把 IV Rank、25D Skew 与宏观催化剂写成可执行 checklist，附风控熔断规则。',
     '---
title: 策略手册 01
date: 2026-10-05
---

## 进场规则
IV Rank < 30% 或 > 70%，且宏观催化剂窗口确认。',
     '<p style="font-size:15px;line-height:1.8;color:#2c3e50;margin-bottom:16px;">把 IV Rank、25D Skew 与宏观催化剂写成可执行 checklist，附风控熔断规则。</p><p style="font-size:13px;color:#94a3b8;">【风控与合规声明】本文系莫伯个人宏观与量化交易体系的学术复盘笔记，首发于 MoBoCapital.com，不构成任何证券投资建议或收益承诺。市场有风险，决策需独立。</p>',
     '一套可执行清单：IV Rank 阈值、偏度分位、催化剂窗口与失效条件。',
     '["1/5  A playbook is only useful if it says when to walk away. Here is the checklist we actually use.","2/5  Entry: IV rank below 30 or above 70, catalyst confirmed, skew aligned.","3/5  Structure: ratio spreads for cheap vol, calendars for neutral, short vol only when rich.","4/5  Sizing: max 1.25% NAV per structure, 25% sector cap.","5/5  Exit: 7 days before expiry, or the invalidation trigger, whichever comes first."]'::jsonb,
     ARRAY['策略手册'], 'PUBLIC', 'PUBLISHED', '2026-10-05T20:10:00+08'::timestamptz),
    ('fund-blueprint-phase-1', 'FUND_VISION',
     '基金孵化蓝图 · 第一阶段：自营交易与体系化筑基',
     '以可审计的实盘曲线、纪律评分与五维里程碑推进个人对冲基金的三阶段路线。',
     '---
title: 基金孵化蓝图 · Phase 1
---

## 五维里程碑
业绩、纪律、合规、基建、品牌。',
     '<p style="font-size:15px;line-height:1.8;color:#2c3e50;margin-bottom:16px;">以可审计的实盘曲线、纪律评分与五维里程碑推进三阶段路线。</p>',
     '个人投研体系的三阶段路线：先做出可审计的曲线，再谈规模。',
     '["1/4  Track record first, scale later. Three phases, five dimensions, one rule: no leverage without evidence."]'::jsonb,
     ARRAY['基金孵化'], 'LP_PROSPECT', 'PENDING_REVIEW', NULL::timestamptz)
) AS t(slug, category, title, summary, web_markdown, wechat_html, xueqiu_markdown, x_thread_json, tags, visibility, publish_status, published_at)
ON CONFLICT (slug) DO NOTHING;

-- 渠道运营指标（近 14 天）
INSERT INTO capital.media_channel_metrics (
    publication_id, channel, snapshot_date, impressions, views_or_reads,
    likes_and_bookmarks, comments_and_shares, net_new_followers, referral_clicks_to_web
)
SELECT
    p.id, ch.channel, (CURRENT_DATE - (d * 1))::date,
    (900 + d * 47)::int, (420 + d * 21)::int,
    (60 + d * 4)::int, (14 + d)::int, (9 + d)::int, (26 + d * 2)::int
FROM capital.capital_publications p
CROSS JOIN (VALUES ('WECHAT'), ('XUEQIU'), ('X_TWITTER'), ('MOBOCAPITAL_WEB')) AS ch(channel)
CROSS JOIN generate_series(0, 13) AS d
WHERE p.slug = 'macro-pmi-divergence-vol-mispricing'
  AND NOT EXISTS (
      SELECT 1 FROM capital.media_channel_metrics m
      WHERE m.publication_id = p.id AND m.channel = ch.channel AND m.snapshot_date = (CURRENT_DATE - d)::date
  );

COMMIT;

-- 对账（capital 侧）
SELECT 'macro_indicators' AS t, count(*) FROM capital.macro_indicator_series
UNION ALL SELECT 'vol_surface', count(*) FROM capital.options_vol_surface_daily
UNION ALL SELECT 'publications', count(*) FROM capital.capital_publications
UNION ALL SELECT 'media_metrics', count(*) FROM capital.media_channel_metrics;
