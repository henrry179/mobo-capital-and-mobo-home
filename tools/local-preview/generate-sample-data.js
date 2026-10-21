#!/usr/bin/env node
/**
 * 本地预览样例数据生成器（零依赖）
 *
 * 作用：在没有 Docker / PostgreSQL 的机器上，为两个静态门户生成与生产同构的
 *       JSON 数据包，让 `sites/` 能被本地网关直接分发、页面真正渲染出内容。
 *
 * 与生产的一致性：
 *   - 字段名与 `deploy/postgres/initdb/02,04~07` 的列一致；
 *   - 公域包的裁剪规则与 `services/mobo-cli/mobo_cli/exporters.py` 一致：
 *       物理删除 private_blotter_oss_key / signed_blotter_url / oss_object_key 等；
 *       物理剔除 visibility='INTERNAL'（莫伯资本）与 is_sensitive=true（莫伯之家）；
 *   - 产出后自动做一次审计（等价于 exporters.audit_payload）。
 *
 * 用法：
 *   node tools/local-preview/generate-sample-data.js [--out <项目根>]
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(process.argv.includes('--out')
  ? process.argv[process.argv.indexOf('--out') + 1]
  : path.resolve(__dirname, '..', '..'));

// ---------------------------------------------------------------------------
// 确定性随机（保证多次生成结果一致，便于截图与回归对比）
// ---------------------------------------------------------------------------
function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rnd = mulberry32(20261021);
const pick = arr => arr[Math.floor(rnd() * arr.length)];
const round = (v, d = 2) => Number(v.toFixed(d));

// ---------------------------------------------------------------------------
// 与 exporters.PRIVATE_FIELDS 对齐
// ---------------------------------------------------------------------------
const PRIVATE_FIELDS = new Set([
  'private_blotter_oss_key', 'signed_blotter_url', 'private_attachment_oss_key',
  'oss_object_key', 'oss_thumbnail_key', 'signed_url',
  'access_key_id', 'access_key_secret', 'password', 'secret',
]);

function stripPrivate(node) {
  if (Array.isArray(node)) return node.map(stripPrivate);
  if (node && typeof node === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(node)) {
      if (PRIVATE_FIELDS.has(k)) continue;
      out[k] = stripPrivate(v);
    }
    return out;
  }
  return node;
}
const filterVisibility = rows => rows
  .filter(r => String(r.visibility || 'PUBLIC').toUpperCase() !== 'INTERNAL')
  .map(stripPrivate);
const filterSensitive = rows => rows.filter(r => !r.is_sensitive).map(stripPrivate);

function audit(payload) {
  const violations = [];
  const internal = [];
  (function walk(node, p) {
    if (Array.isArray(node)) return node.forEach((v, i) => walk(v, `${p}[${i}]`));
    if (node && typeof node === 'object') {
      for (const [k, v] of Object.entries(node)) {
        if (PRIVATE_FIELDS.has(k)) violations.push(`${p}.${k}`);
        if (typeof v === 'string' && v.trim().toUpperCase() === 'INTERNAL') internal.push(`${p}.${k}`);
        walk(v, p ? `${p}.${k}` : k);
      }
    }
  })(payload, '');
  return { ok: !violations.length && !internal.length, private_field_violations: violations, internal_markers: internal };
}

function writeJson(rel, payload) {
  const p = path.join(ROOT, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, JSON.stringify(payload, null, 2), 'utf8');
  return p;
}

// ===========================================================================
// 莫伯资本（db_mobobrain.capital）
// ===========================================================================
const theses = [
  {
    thesis_code: 'THESIS-2026Q4-CN-RETAIL', title: '中国必选消费与生鲜冷链供应链：高周转率企业的自由现金流重估',
    region: 'CN', asset_class: 'MULTI', time_horizon: '3_6_MONTHS', directional_bias: 'BULLISH', conviction_score: 8,
    leading_indicators: { PMI_NewOrders: 51.4, Inventory_Turnover_Days: '-14%', '300ETF_IV_Rank': '28%' },
    core_logic_md: '高频渠道与供应链数据显示，具备数字化仓配能力的生鲜零售企业已越过资本开支高峰，库存周转天数缩短，而期权隐含波动率仍处于 28% 低分位。',
    invalidation_criteria: '若社零餐饮分项连续两个月环比回落超 1.5%，无条件平仓全部多头期权头寸。',
    status: 'ACTIVE', visibility: 'PUBLIC',
  },
  {
    thesis_code: 'THESIS-2026Q4-US-VOL-SKEW', title: '美债期限溢价回升背景下的美股科技股波动率偏度均值回归',
    region: 'US', asset_class: 'EQUITY', time_horizon: '1_3_MONTHS', directional_bias: 'VOL_LONG', conviction_score: 9,
    leading_indicators: { US10Y_Yield: '4.18%', SPY_25D_Skew_Pct: '92%', ISM_NewOrders: 48.9 },
    core_logic_md: '美股内部宽度收窄且机构尾部保护需求推高 Put-Call Skew 至 92% 分位，适合通过认沽比例价差博弈波动率中枢上移。',
    invalidation_criteria: '若 VIX 跌破 13.5 且 ISM 新订单超预期跃升至 53 以上，立即止损平仓。',
    status: 'ACTIVE', visibility: 'PUBLIC',
  },
  {
    thesis_code: 'THESIS-2027Q1-EU-ENERGY', title: '欧洲能源再平衡与工业品需求弹性',
    region: 'EU', asset_class: 'MACRO', time_horizon: '6_12_MONTHS', directional_bias: 'NEUTRAL', conviction_score: 5,
    leading_indicators: { TTF_Gas_EUR: 31.4, 'EU_PMI_Manufacturing': 46.2 },
    core_logic_md: '能源价格回落释放工业成本空间，但制造业 PMI 仍在荣枯线下，需求弹性尚未确认。',
    invalidation_criteria: '若制造业 PMI 连续两月站上 50，转为偏多。',
    status: 'ACTIVE', visibility: 'LP_PROSPECT',
  },
  {
    thesis_code: 'THESIS-INTERNAL-LIQUIDITY', title: '内部：流动性与头寸的内部风险隔离口径（不对外披露）',
    region: 'GLOBAL', asset_class: 'MULTI', time_horizon: '1_3_MONTHS', directional_bias: 'NEUTRAL', conviction_score: 7,
    leading_indicators: { gross_exposure_pct: 62, net_exposure_pct: 18 },
    core_logic_md: '内部驾驶舱：总敞口 62%、净敞口 18%，单一标的上限 15%，现金垫 22%。',
    invalidation_criteria: '总敞口 > 80% 或净敞口 > 35% 即刻降杠杆。',
    status: 'ACTIVE', visibility: 'INTERNAL',
  },
];

const playbooks = [
  {
    strategy_code: 'OPT-VOL-SKEW-01', name: '期权波动率偏度与跨式非对称策略', strategy_family: 'OPTIONS_VOL',
    holding_period: '2-6 Weeks', target_sharpe: 1.95, target_win_rate_pct: 65, target_rr_ratio: 2.8,
    max_risk_per_trade_pct: 1.25, max_sector_exposure_pct: 25,
    entry_rules_md: '1. 宏观或行业催化剂明确且先行指标 Z-Score 大于 +1.0σ；2. 标的 30D IV Rank 处于 30% 分位以下或 80% 分位以上。',
    option_structure_guide: '低 IV 买方向使用 Bull Call / Bear Put Spread (45DTE)；高 Skew 环境使用 1x2 Ratio Spread 或 Calendar Spread。',
    exit_and_stop_rules_md: '单笔权利金最大亏损严格锁死在 1.25% NAV；到期前 7 天无条件移仓或平仓规避尾部 Gamma 风险。',
    visibility: 'PUBLIC',
  },
  {
    strategy_code: 'ITPM-LS-EQUITY', name: 'ITPM 基本面多空配对股票策略 (L/S Equity)', strategy_family: 'LONG_SHORT_EQUITY',
    holding_period: '1-3 Months', target_sharpe: 1.75, target_win_rate_pct: 60, target_rr_ratio: 2.5,
    max_risk_per_trade_pct: 1.5, max_sector_exposure_pct: 30,
    entry_rules_md: '结合自上而下 PMI/社融先行指标与零售/供应链微观周转率印证，做多自由现金流拐点龙头，同时配对做空基本面恶化同业标的。',
    option_structure_guide: '以现货配对为主，辅以卖出虚值 Covered Call 增厚持仓收益。',
    exit_and_stop_rules_md: '配对组合触及 -1.0R（即 1.50% NAV）或基本面证伪条件触发时，双腿同步无条件平仓。',
    visibility: 'PUBLIC',
  },
  {
    strategy_code: 'MACRO-CROSS-ASSET', name: '全球宏观跨资产趋势与利差对冲策略', strategy_family: 'MACRO_DIRECTIONAL',
    holding_period: '1-6 Months', target_sharpe: 1.6, target_win_rate_pct: 55, target_rr_ratio: 3.0,
    max_risk_per_trade_pct: 1.0, max_sector_exposure_pct: 25,
    entry_rules_md: '围绕中美欧货币政策周期错位、M1-M2 剪刀差与实际利差变化，在宽基股指 ETF、国债 ETF 与黄金期权之间构建低相关性宏观头寸。',
    option_structure_guide: '优先采用对角价差 (Diagonal Spread) 或远期合成头寸控制资金占用。',
    exit_and_stop_rules_md: '宏观先行指标连续两个月逆转或触及预设证伪点位时立即止损离场。',
    visibility: 'PUBLIC',
  },
  {
    strategy_code: 'TAIL-RISK-SHIELD', name: '尾部风险保护伞与系统性熔断对冲', strategy_family: 'EVENT_DRIVEN',
    holding_period: 'Continuous', target_sharpe: 1.4, target_win_rate_pct: 40, target_rr_ratio: 5.0,
    max_risk_per_trade_pct: 0.5, max_sector_exposure_pct: 15,
    entry_rules_md: '当全市场 VIX 或 300ETF 隐含波动率跌入历史 15% 极低分位且情绪极度乐观时，定投远月深度虚值 Put 作为组合保险。',
    option_structure_guide: '60-90DTE 10-Delta 至 15-Delta 虚值 Put 或 Put Backspread。',
    exit_and_stop_rules_md: 'Vega 脉冲式飙升超过 4R 时分批止盈兑现，将现金反哺低估核心资产。',
    visibility: 'LP_PROSPECT',
  },
];

const tradeRows = [
  ['T-2026-001', '300ETF', '沪深300ETF', '45DTE Bull Call Spread', 'OPT-VOL-SKEW-01', 'LONG', '2026-08-14', '2026-09-04', 1.2, 1.85, 220, 9, 'PUBLIC'],
  ['T-2026-002', '600519', '贵州茅台', 'L/S 配对（多 300ETF / 空 消费龙头）', 'ITPM-LS-EQUITY', 'RELATIVE_VALUE', '2026-08-21', '2026-10-09', 1.5, -0.42, -160, 8, 'PUBLIC'],
  ['T-2026-003', 'GLD', 'SPDR 黄金 ETF', 'Calendar Spread 1-2M', 'MACRO-CROSS-ASSET', 'LONG', '2026-09-02', '2026-10-16', 1.0, 0.76, 95, 7, 'PUBLIC'],
  ['T-2026-004', 'SPY', 'SPDR 标普500', '45DTE Bear Put Spread', 'OPT-VOL-SKEW-01', 'SHORT', '2026-09-18', '2026-10-02', 1.25, 2.35, 280, 10, 'LP_PROSPECT'],
  ['T-2026-005', '510300', '沪深300ETF期权', '10D 虚值 Put（尾部保险）', 'TAIL-RISK-SHIELD', 'LONG', '2026-10-08', null, 0.5, null, null, 9, 'INTERNAL'],
  ['T-2026-006', '159919', '沪深300ETF（场内）', 'Delta Neutral 组合', 'ITPM-LS-EQUITY', 'DELTA_NEUTRAL', '2026-10-10', null, 1.0, null, null, 8, 'INTERNAL'],
];

const trades = tradeRows.map(([code, ticker, name, structure, strategy, direction, entry, exit, risk, r, bps, disc, vis]) => ({
  trade_code: code, underlying_ticker: ticker, asset_name: name, instrument_structure: structure,
  strategy_code: strategy, direction, entry_date: entry, exit_date: exit,
  trade_status: exit ? 'CLOSED' : 'OPEN',
  initial_risk_pct: risk, realized_r_multiple: r, realized_return_pct: r === null ? null : round(r * risk * 1.6, 2),
  portfolio_impact_bps: bps, discipline_score: disc, emotional_state_tag: pick(['CALM', 'FOCUSED', 'IMPATIENT']),
  pre_trade_thesis_md: '按 ITPM 框架确认先行指标方向，等待波动率分位进入目标区间后按计划建仓。',
  execution_review_md: exit ? '按预设结构执行，未做 discretionary 加仓。' : null,
  lessons_learned_md: exit ? '入场时点略早于催化剂兑现，但结构选择正确。' : null,
  private_blotter_oss_key: vis === 'INTERNAL' ? `blotters/2026/${code}-signed.pdf` : null,
  public_chart_oss_url: null,
  visibility: vis,
  embedding: null,
}));

const publications = [
  {
    slug: 'macro-pmi-divergence-options-straddle', category: 'MACRO',
    title: 'PMI 分歧期的波动率错配：跨式与偏度的赔率结构',
    summary: '制造业新订单与价格分项背离，隐含波动率仍处低分位，本文拆解跨式与偏度结构的赔率差异。',
    web_markdown: '---\ntitle: PMI 分歧期的波动率错配\ndate: 2026-10-12\ncategory: MACRO\ntags: [宏观, 波动率, PMI]\n---\n\n## 核心结论\n…',
    wechat_html: '<p style="font-size:15px;line-height:1.8;color:#2c3e50;margin-bottom:16px;">…</p>',
    xueqiu_markdown: '结论先行：当价格分项与新订单背离，隐含波动率的错配往往先于方向兑现。$沪深300(SH000300)$ 的 30D IV 仍在低分位区间。',
    x_thread_json: ['1/6  Vol is cheap, positioning is not. A divergence between PMI new orders and prices is the classic setup for a volatility mispricing.', '2/6  When implied vol sits in the bottom decile but skew keeps rising, smart money is paying for protection.'],
    cover_oss_url: null, tags: ['宏观', '波动率'], visibility: 'PUBLIC', publish_status: 'PUBLISHED',
    wechat_draft_media_id: null, xueqiu_post_url: null, x_root_tweet_id: null, embedding: null,
    published_at: '2026-10-12T09:30:00+08:00',
  },
  {
    slug: 'strategy-playbook-iv-skew-01', category: 'STRATEGY',
    title: '策略手册 01：波动率偏度策略的进出场铁律',
    summary: '把 IV Rank、25D Skew 与宏观催化剂写成可执行的 checklist，附风控熔断规则。',
    web_markdown: '---\ntitle: 策略手册 01\ndate: 2026-10-05\n---\n\n## 进场规则\n…',
    wechat_html: '<p style="font-size:15px;line-height:1.8;color:#2c3e50;margin-bottom:16px;">…</p>',
    xueqiu_markdown: '一套可执行清单：IV Rank 阈值、偏度分位、催化剂窗口与失效条件。',
    x_thread_json: ['1/5  A playbook is only useful if it says when to walk away. Here is the checklist we actually use.'],
    cover_oss_url: null, tags: ['策略手册'], visibility: 'PUBLIC', publish_status: 'PUBLISHED',
    published_at: '2026-10-05T20:10:00+08:00',
  },
  {
    slug: 'fund-blueprint-phase-1', category: 'FUND_VISION',
    title: '基金孵化蓝图 · 第一阶段：自营交易与体系化筑基',
    summary: '以可审计的实盘曲线、纪律评分与五维里程碑推进个人对冲基金的三阶段路线。',
    web_markdown: '---\ntitle: 基金孵化蓝图 · Phase 1\n---\n\n## 五维里程碑\n…',
    wechat_html: '<p style="font-size:15px;line-height:1.8;color:#2c3e50;margin-bottom:16px;">…</p>',
    xueqiu_markdown: '个人投研体系的三阶段路线：先做出可审计的曲线，再谈规模。',
    x_thread_json: ['1/4  Track record first, scale later. Three phases, five dimensions, one rule: no leverage without evidence.'],
    cover_oss_url: null, tags: ['基金孵化'], visibility: 'LP_PROSPECT', publish_status: 'PENDING_REVIEW',
    published_at: null,
  },
];

const mediaMetrics = [
  { publication_id: null, channel: 'MOBOCAPITAL_WEB', snapshot_date: '2026-10-20', impressions: 1280, views_or_reads: 640, likes_and_bookmarks: 96, comments_and_shares: 18, net_new_followers: 12, referral_clicks_to_web: 74 },
  { publication_id: null, channel: 'WECHAT', snapshot_date: '2026-10-20', impressions: 5400, views_or_reads: 2100, likes_and_bookmarks: 310, comments_and_shares: 62, net_new_followers: 88, referral_clicks_to_web: 120 },
  { publication_id: null, channel: 'XUEQIU', snapshot_date: '2026-10-20', impressions: 3100, views_or_reads: 1500, likes_and_bookmarks: 140, comments_and_shares: 41, net_new_followers: 35, referral_clicks_to_web: 58 },
];

const macroIndicators = [
  { indicator_code: 'CN_PMI_NEW_ORDERS', indicator_name: '中国制造业 PMI 新订单', region: 'CN', frequency: 'MONTHLY', obs_date: '2026-09-30', raw_value: 51.4, prev_value: 50.6, change_val: 0.8, z_score: 0.85, regime_tag: 'IMPROVING' },
  { indicator_code: 'CN_PMI_PRICE', indicator_name: '中国制造业 PMI 出厂价格', region: 'CN', frequency: 'MONTHLY', obs_date: '2026-09-30', raw_value: 47.2, prev_value: 48.9, change_val: -1.7, z_score: -1.12, regime_tag: 'CONTRACTION' },
  { indicator_code: 'US_ISM_NEW_ORDERS', indicator_name: '美国 ISM 制造业新订单', region: 'US', frequency: 'MONTHLY', obs_date: '2026-09-30', raw_value: 48.9, prev_value: 50.2, change_val: -1.3, z_score: -0.64, regime_tag: 'NEUTRAL' },
  { indicator_code: 'US10Y_YIELD', indicator_name: '美债 10 年期收益率', region: 'US', frequency: 'DAILY', obs_date: '2026-10-20', raw_value: 4.18, prev_value: 4.09, change_val: 0.09, z_score: 0.42, regime_tag: 'NEUTRAL' },
  { indicator_code: 'CN_SOCIAL_FINANCE', indicator_name: '社会融资规模存量同比', region: 'CN', frequency: 'MONTHLY', obs_date: '2026-09-30', raw_value: 8.3, prev_value: 8.1, change_val: 0.2, z_score: 0.31, regime_tag: 'NEUTRAL' },
];

const volSurface = [
  { underlying_ticker: '510300.SH', asset_name: '沪深300ETF期权', trade_date: '2026-10-20', spot_price: 3.982, daily_change_pct: -0.42, iv_30d: 19.8, hv_30d: 21.6, vrp_spread: -1.8, iv_rank_1y: 28.4, iv_percentile_1y: 27.9, skew_25d: 4.6, recommended_structure: '低 IV + 正偏度：1x2 Ratio Spread / Calendar' },
  { underlying_ticker: 'SPY', asset_name: 'SPDR 标普500 ETF', trade_date: '2026-10-20', spot_price: 684.2, daily_change_pct: 0.31, iv_30d: 16.4, hv_30d: 15.1, vrp_spread: 1.3, iv_rank_1y: 42.7, iv_percentile_1y: 38.2, skew_25d: 3.1, recommended_structure: '中性偏度：45DTE Debit Spread' },
  { underlying_ticker: 'GLD', asset_name: 'SPDR 黄金 ETF', trade_date: '2026-10-20', spot_price: 312.7, daily_change_pct: 0.85, iv_30d: 14.2, hv_30d: 13.5, vrp_spread: 0.7, iv_rank_1y: 33.1, iv_percentile_1y: 30.5, skew_25d: 2.4, recommended_structure: '趋势跟随：Call Spread' },
];

const nav = {
  valuation_date: '2026-10-20', trigger_trade_code: 'T-2026-004',
  gross_nav: 1.1042, high_water_mark: 1.1042, accrued_perf_fee_nav: 0.0208, net_nav: 1.0834,
  current_drawdown_pct: 0.0, cumulative_r_multiple: 3.52, risk_regime_status: 'NORMAL',
  risk_action_note: '组合净值运行稳健，维持标准风险预算（单笔不超过 1.50% NAV）。',
};

// ===========================================================================
// 莫伯之家（db_archive.archive）
// ===========================================================================
const timelineStories = [
  {
    id: '1', event_date: '2026-02-15', category: 'milestone',
    title: '从北上深一线数据战场到归航武汉：慢就是快的人生仓位重构',
    summary: '历经深圳、北京、上海十余年零售与生鲜供应链数据深耕，选择回到湖北建立长期稳固的家庭与投研根据地。',
    location_name: '武汉', importance: 5, mood_score: 9, energy_score: 9,
    tags: ['人生复盘', '慢就是快', '武汉定居', '段永平哲学'],
    metadata: {
      life_chapter: '湖北·归航与长期筑基',
      content_markdown: '## 一、一线城市的十年基本面沉淀\n从 2014 年大学毕业南下深圳，到北京美菜、上海钱大妈与肉类供应链，十余年的零售与供应链数据分析和战略咨询生涯，让我看清了商业的底层现金流本质。\n\n## 二、为什么选择归航武汉？\n用交易员的风险隔离模型审视人生，真正的复利需要稳定的底仓与和谐的家庭基础。',
    },
    attached_media: [{ asset_type: 'photo', title: '武汉长江大桥落日纪事', public_thumb_url: 'https://images.unsplash.com/photo-1477414348463-c0eb7f1359b6?auto=format&fit=crop&w=800&q=80' }],
  },
  {
    id: '2', event_date: '2024-10-10', category: 'career',
    title: '上海深耕期：生鲜供应链周转率优化与多仓协同战役',
    summary: '在上海钱大妈与康信肉类供应链期间，主导全国多温区仓储网络数字化重构与呆滞库存损耗压降。',
    location_name: '上海', importance: 4, mood_score: 8, energy_score: 8,
    tags: ['供应链', '数据分析', '上海深耕'],
    metadata: {
      life_chapter: '上海·供应链深耕',
      content_markdown: '生鲜供应链的核心在于"鲜"与"转"。通过精细化 SKU 周转预测模型与动态补货算法，成功将核心生鲜品类的呆滞率降低了 18%。',
    },
    attached_media: [],
  },
  {
    id: '3', event_date: '2018-05-20', category: 'career',
    title: '北上深历练期：从深圳跨越速运到北京美菜网的物流数据基建',
    summary: '深度参与公路干线物流网络调度与生鲜 B2B 电商大仓运营，完成从传统 BI 分析师向业务战略操盘手的蜕变。',
    location_name: '北京 / 深圳', importance: 4, mood_score: 8, energy_score: 9,
    tags: ['跨越速运', '美菜网', '物流与数仓'],
    metadata: {
      life_chapter: '北上深·历练期',
      content_markdown: '在高强度作战中深刻理解规模效应与边际成本的残酷规律，这段经历奠定了后来对全球宏观周期与企业基本面深度复盘的思维底座。',
    },
    attached_media: [],
  },
  {
    id: '4', event_date: '2026-10-12', category: 'habit',
    title: '东湖晨跑 10km：把自律变成可计算的底仓',
    summary: '晨跑 51 分钟、配速 5:05/公里、心率均值 152——第 41 周的连续训练记录已同步进体征看板。',
    location_name: '武汉·东湖', importance: 3, mood_score: 8, energy_score: 8,
    tags: ['跑步', '自律', '体征'],
    metadata: { life_chapter: '日常自律', content_markdown: '慢就是快：把每一次训练都写成可回测的数据点。' },
    attached_media: [{ asset_type: 'photo', title: '东湖晨跑', public_thumb_url: 'https://images.unsplash.com/photo-1517838277536-f5f99be501cd?auto=format&fit=crop&w=800&q=80' }],
  },
  {
    id: '9', event_date: '2026-09-20', category: 'private',
    title: '（内部）家庭影像与体检归档',
    summary: '仅内网可见的私密记录，用于验证脱敏链路。',
    location_name: '武汉', importance: 2, mood_score: 7, energy_score: 7,
    tags: ['私密'],
    metadata: { life_chapter: '内部', content_markdown: '此条记录在公域包中应被剔除。' },
    attached_media: [],
    is_sensitive: true,
  },
];

const galleryAssets = [
  { id: 'g1', asset_type: 'photo', title: '武汉东湖晨跑与体能训练', captured_at: '2026-10-12', public_thumb_url: 'https://images.unsplash.com/photo-1517838277536-f5f99be501cd?auto=format&fit=crop&w=800&q=80' },
  { id: 'g2', asset_type: 'photo', title: '莫伯之家书房与投研资料库', captured_at: '2026-09-28', public_thumb_url: 'https://images.unsplash.com/photo-1497633762265-9d179a990aa6?auto=format&fit=crop&w=800&q=80' },
  { id: 'g3', asset_type: 'photo', title: '长江岸线宏观思考散步时刻', captured_at: '2026-08-15', public_thumb_url: 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=800&q=80' },
  { id: 'g4', asset_type: 'video', title: '2026 秋季力量训练突破日', captured_at: '2026-10-01', public_thumb_url: 'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?auto=format&fit=crop&w=800&q=80' },
  { id: 'g5', asset_type: 'photo', title: '（内部）家庭影像归档', captured_at: '2026-09-20', public_thumb_url: 'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?auto=format&fit=crop&w=800&q=80', is_sensitive: true },
];

const readingLibrary = [
  { id: 'b1', title: 'The Road to Reality (现实的道路)', author: 'Roger Penrose', category: 'PHYSICS', status: 'COMPLETED', rating: 5, core_takeaway: '宇宙底层物理定律与数学几何结构的深刻统一，对理解复杂系统与金融非线性波动率有极高启发。' },
  { id: 'b2', title: '孙子兵法与战略思维', author: '孙武', category: 'STRATEGY', status: 'COMPLETED', rating: 5, core_takeaway: '"先胜而后求战"——这正是风险隔离与资本管理的核心铁律。' },
  { id: 'b3', title: '穷查理宝典 (Poor Charlie\'s Almanack)', author: 'Charlie Munger', category: 'FINANCE', status: 'COMPLETED', rating: 5, core_takeaway: '多元思维模型、逆向思考与长期复利，慢就是快。' },
  { id: 'b4', title: 'Python Machine Learning & Quantitative Systems', author: '吴军 / 综合技术', category: 'FINANCE', status: 'IN_PROGRESS', rating: 4, core_takeaway: '将自动化流水线、pgvector 与本地 AI 智能体框架打通，构建高效的个人数字大脑。' },
  { id: 'b5', title: '华为的研发与数字化转型', author: 'several', category: 'BUSINESS', status: 'COMPLETED', rating: 4, core_takeaway: '从流程数字化到能力平台化：企业第二曲线的组织学。' },
];

const workouts = [
  { workout_id: 'w1', workout_type: 'RUNNING', title: '东湖晨跑 10km', started_at: '2026-10-12T06:40:00+08:00', ended_at: '2026-10-12T07:31:00+08:00', duration_minutes: 51, calories_kcal: 486, avg_heart_rate: 152, rpe_score: 7, distance_meters: 10000, avg_pace_sec_km: 305, tags: ['晨跑', '自律'] },
  { workout_id: 'w2', workout_type: 'STRENGTH', title: '力量训练：推举日', started_at: '2026-10-10T19:20:00+08:00', ended_at: '2026-10-10T20:10:00+08:00', duration_minutes: 50, rpe_score: 8, total_volume_kg: 4820, total_sets: 18, tags: ['力量'] },
  { workout_id: 'w3', workout_type: 'RUNNING', title: '珞珈山慢跑 7km', started_at: '2026-10-08T07:05:00+08:00', ended_at: '2026-10-08T07:44:00+08:00', duration_minutes: 39, calories_kcal: 372, avg_heart_rate: 146, rpe_score: 6, distance_meters: 7000, avg_pace_sec_km: 334, tags: ['慢跑'] },
];

const retrospectives = [
  {
    retro_id: 'r1', retro_type: 'WEEKLY', domain: 'SYSTEM_TECH', title: '第 41 周复盘：把波动率研究变成可执行清单',
    period_start: '2026-10-05', period_end: '2026-10-11',
    initial_hypothesis: '本周优先完成 IV Rank 指标脚本并跑通 3 个标的。',
    actual_execution: '脚本完成，2 个标的接上实时快照，1 个标的数据源有延迟。',
    root_cause_analysis: '数据源未做冗余，缺少 fallback。',
    codified_principles: '任何单点数据源必须配置一个平滑回退。',
    kpi_snapshot: { 研究时长小时: 6.5, 训练次数: 3, 复盘完成度: 1 },
    action_items: [{ text: '为宏观采集器增加多源回退', owner: '我', due: '周日' }],
    execution_score: 8, outcome_score: 7, tags: ['周复盘'], privacy: 'RESTRICTED',
  },
  {
    retro_id: 'r2', retro_type: 'PROJECT_POSTMORTEM', domain: 'CAREER_WORK', title: '（内部）一次亏损交易的归因复盘',
    period_start: '2026-09-15', period_end: '2026-09-19',
    initial_hypothesis: '配对交易会在行业 beta 回落时受益。',
    actual_execution: '行业 beta 未回落，价差走阔触发止损。',
    root_cause_analysis: '缺少行业景气度的高频验证。',
    codified_principles: '价差交易的进场必须叠加至少两个独立的高频信号。',
    kpi_snapshot: { 回撤R: -0.42 },
    action_items: [],
    execution_score: 6, outcome_score: 5, tags: ['内部复盘'], privacy: 'VAULT', is_sensitive: true,
  },
];

// ===========================================================================
// 生成并写盘
// ===========================================================================
const capitalPublic = {
  macro_theses: filterVisibility(theses),
  strategy_playbooks: filterVisibility(playbooks),
  trade_reviews: filterVisibility(trades),
  publications: filterVisibility(publications),
  media_metrics: mediaMetrics,
};

const capitalInternal = {
  macro_theses: theses,
  strategy_playbooks: playbooks,
  trade_reviews: trades,
  publications,
  media_metrics: mediaMetrics,
};

const terminalSnapshot = {
  macro_indicators: macroIndicators,
  options_vol_surface: volSurface,
  portfolio_nav: nav,
};

const homePublic = {
  timeline_stories: filterSensitive(timelineStories),
  gallery_assets: filterSensitive(galleryAssets),
  reading_library: readingLibrary,
  workouts,
  retrospectives: filterSensitive(retrospectives),
};

const homeInternal = {
  timeline_stories: timelineStories,
  gallery_assets: galleryAssets,
  reading_library: readingLibrary,
  workouts,
  retrospectives,
};

const written = [];
written.push(writeJson('sites/mobocapital/data/public-data.json', capitalPublic));
written.push(writeJson('sites/mobocapital/data/terminal-snapshot.json', terminalSnapshot));
written.push(writeJson('sites/mobocapital/internal/internal-data.json', capitalInternal));
written.push(writeJson('sites/mobohome/data/public-home-data.json', homePublic));
written.push(writeJson('sites/mobohome/internal/internal-home-data.json', homeInternal));

console.log('[generate-sample-data] 已生成：');
written.forEach(p => console.log('   - ' + path.relative(ROOT, p).split(path.sep).join('/')));

let failed = false;
for (const [name, payload] of [['capital public', capitalPublic], ['home public', homePublic]]) {
  const a = audit(payload);
  console.log(`[audit] ${name}: ${a.ok ? 'OK（0 违规）' : 'FAILED ' + JSON.stringify(a)}`);
  if (!a.ok) failed = true;
}
console.log(`[audit] capital internal（应含敏感字段，仅内网可见）: ${audit(capitalInternal).ok ? 'OK' : '含敏感字段（预期）'}`);
console.log(`[audit] home internal（应含敏感字段，仅内网可见）: ${audit(homeInternal).ok ? 'OK' : '含敏感字段（预期）'}`);

if (failed) { console.error('[generate-sample-data] 公域包脱敏校验失败'); process.exit(1); }
console.log('[generate-sample-data] 完成。');
