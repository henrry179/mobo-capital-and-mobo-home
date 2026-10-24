-- 将资本站页面中的三份治理文稿迁入 fund_governance_docs（无附件 OSS Key）
-- docker exec -i mobo-postgres psql -U postgres -d db_mobobrain -v ON_ERROR_STOP=1 < tools/local/seed_governance_docs.sql

BEGIN;

INSERT INTO capital.fund_governance_docs (
    doc_slug, doc_type, title, version, summary, content_md, visibility
) VALUES
(
    'investor-letter-why-not-lose-big',
    'INVESTOR_LETTER',
    '《致莫伯资本未来合伙人备忘录：为什么把“不亏大钱”置于首位》',
    'v2.1',
    '公开备忘录：风险隔离优先于规模扩张。',
    $md$# 致未来合伙人

把「不亏大钱」放在首位，不是保守，而是可审计的生存约束。

本备忘录只陈述原则与监测框架，不构成任何证券投资建议。
$md$,
    'PUBLIC'
),
(
    'risk-sop-hwm-drawdown',
    'RISK_SOP',
    '《莫伯资本投委会风控章程：单笔止损与净值预警清盘制度》',
    'v1.4',
    'LP 可见：单笔止损、净值黄红区与清盘闸门。',
    $md$# 投委会风控章程

- 单笔初始风险硬顶
- 净值回撤黄区 / 红区动作
- 高水位法与业绩报酬计提边界

详细数字与附件仅内网可见。
$md$,
    'LP_PROSPECT'
),
(
    'nav-hwm-accounting-spec',
    'NAV_ACCOUNTING',
    '《基金份额净值（NAV）会计核算与高水位法业绩报酬计提规范》',
    'v1.2',
    'LP 可见：NAV 与 HWM 计提口径。',
    $md$# NAV 与高水位法

定义毛净值、净净值、高水位与回撤口径；公开页只展示已脱敏摘要。
$md$,
    'LP_PROSPECT'
)
ON CONFLICT (doc_slug) DO UPDATE SET
    doc_type = EXCLUDED.doc_type,
    title = EXCLUDED.title,
    version = EXCLUDED.version,
    summary = EXCLUDED.summary,
    content_md = EXCLUDED.content_md,
    visibility = EXCLUDED.visibility;

COMMIT;

SELECT doc_slug, doc_type, version, visibility FROM capital.fund_governance_docs ORDER BY doc_type;
