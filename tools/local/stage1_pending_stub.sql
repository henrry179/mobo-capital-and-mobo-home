-- 本地阶段一桩：模拟 n8n 工作流 #3 阶段一落库（无 LLM / 不触发发布）
-- 用法：
--   docker exec -i mobo-postgres psql -U postgres -d db_mobobrain -v ON_ERROR_STOP=1 < tools/local/stage1_pending_stub.sql
-- 约束：publish_status 只能是 PENDING_REVIEW；禁止写成 PUBLISHED。

BEGIN;

INSERT INTO capital.capital_publications (
    slug, category, title, summary,
    web_markdown, wechat_html, xueqiu_markdown, x_thread_json,
    tags, visibility, publish_status
) VALUES (
    'local-stage1-stub-20261024',
    'MACRO',
    '本地阶段一桩 · 宏观周期定位待审稿',
    '无 LLM 时的本地落库验证：四端同源草稿，状态 PENDING_REVIEW。',
    $md$# 本地阶段一桩 · 宏观周期定位

核心命题：本地联调验证 HITL 闸门。公域只陈述机制，不给出买卖点。

监测：FedWatch、社融脉冲、期权偏度分位。

状态：PENDING_REVIEW · 待人工终审。
$md$,
    $html$<p>【免责声明】本文仅供研究交流，不构成投资建议。</p><p>本地桩内容：境内版已脱敏具体点位，并保留风控与合规声明占位。</p>$html$,
    $xq$【研究笔记·本地桩】周期定位验证稿。机制先于方向；不含具体买卖指令。
$沪深300$ 仅作语境提及。$xq$,
    '["1/4 Local stub: HITL gate check only.","2/4 No live LLM; draft stays PENDING_REVIEW.","3/4 Publish nodes remain disabled.","4/4 Full memo after human approve."]'::jsonb,
    ARRAY['local-stub', 'PENDING_REVIEW', 'HITL'],
    'PUBLIC',
    'PENDING_REVIEW'
)
ON CONFLICT (slug) DO UPDATE SET
    title = EXCLUDED.title,
    summary = EXCLUDED.summary,
    web_markdown = EXCLUDED.web_markdown,
    wechat_html = EXCLUDED.wechat_html,
    xueqiu_markdown = EXCLUDED.xueqiu_markdown,
    x_thread_json = EXCLUDED.x_thread_json,
    tags = EXCLUDED.tags,
    publish_status = 'PENDING_REVIEW',
    published_at = NULL;

INSERT INTO intel.ingestion_runs (
    workflow_name, trigger_type, status,
    items_fetched, items_new, items_scored, items_synced,
    finished_at, stats
) VALUES (
    '03-mobocapital-1plus3-stage1-stub',
    'MANUAL',
    'SUCCESS',
    1, 1, 0, 1,
    NOW(),
    '{"slug":"local-stage1-stub-20261024","publish_status":"PENDING_REVIEW","note":"LLM-less local stub"}'::jsonb
);

COMMIT;

SELECT slug, publish_status, length(web_markdown) AS w, length(wechat_html) AS c
FROM capital.capital_publications
WHERE slug = 'local-stage1-stub-20261024';
