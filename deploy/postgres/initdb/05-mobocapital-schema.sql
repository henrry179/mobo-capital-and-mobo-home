-- ============================================================================
-- 文件路径: /opt/mobo-stack/deploy/postgres/initdb/04-mobocapital-schema.sql
-- 目标数据库: db_mobobrain  Schema: capital  属主: user_mobobrain
-- 核心功能: 支撑 MoBoCapital.com 投研思考、策略复盘、基金孵化与自媒体运营全链路
-- ============================================================================

\c db_mobobrain

-- 全部对象落在 capital Schema（与 intel 采集域、n8n 自动化域隔离）
SET search_path TO capital, public;

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";

-- 1. 宏观与产业投研思考表 (macro_theses)
CREATE TABLE IF NOT EXISTS capital.macro_theses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    thesis_code VARCHAR(32) UNIQUE NOT NULL,
    title VARCHAR(256) NOT NULL,
    region VARCHAR(32) NOT NULL DEFAULT 'GLOBAL',
    asset_class VARCHAR(32) NOT NULL,
    time_horizon VARCHAR(32) NOT NULL,
    directional_bias VARCHAR(16) NOT NULL
        CHECK (directional_bias IN ('BULLISH', 'BEARISH', 'NEUTRAL', 'VOL_LONG', 'VOL_SHORT')),
    conviction_score SMALLINT NOT NULL
        CHECK (conviction_score BETWEEN 1 AND 10),
    leading_indicators JSONB DEFAULT '{}'::jsonb,
    core_logic_md TEXT NOT NULL,
    invalidation_criteria TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'VALIDATED', 'INVALIDATED', 'ARCHIVED')),
    visibility VARCHAR(16) DEFAULT 'PUBLIC'
        CHECK (visibility IN ('PUBLIC', 'LP_PROSPECT', 'INTERNAL')),
    embedding vector(1536),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_macro_theses_status ON capital.macro_theses(status, region, created_at DESC);
CREATE INDEX idx_macro_theses_vec ON capital.macro_theses USING hnsw (embedding vector_cosine_ops);

-- 2. 交易策略标准手册表 (strategy_playbooks)
CREATE TABLE IF NOT EXISTS capital.strategy_playbooks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    strategy_code VARCHAR(32) UNIQUE NOT NULL,
    name VARCHAR(128) NOT NULL,
    strategy_family VARCHAR(32) NOT NULL
        CHECK (strategy_family IN ('LONG_SHORT_EQUITY', 'OPTIONS_VOL', 'MACRO_DIRECTIONAL', 'EVENT_DRIVEN')),
    holding_period VARCHAR(32) NOT NULL,
    target_sharpe NUMERIC(4,2),
    target_win_rate_pct NUMERIC(5,2),
    target_rr_ratio NUMERIC(5,2),
    max_risk_per_trade_pct NUMERIC(4,2) NOT NULL,
    max_sector_exposure_pct NUMERIC(5,2),
    entry_rules_md TEXT NOT NULL,
    option_structure_guide TEXT,
    exit_and_stop_rules_md TEXT NOT NULL,
    visibility VARCHAR(16) DEFAULT 'LP_PROSPECT'
        CHECK (visibility IN ('PUBLIC', 'LP_PROSPECT', 'INTERNAL')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 3. 实战交易复盘与归因账本表 (trade_reviews)
CREATE TABLE IF NOT EXISTS capital.trade_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trade_code VARCHAR(40) UNIQUE NOT NULL,
    thesis_id UUID REFERENCES capital.macro_theses(id) ON DELETE SET NULL,
    strategy_id UUID REFERENCES capital.strategy_playbooks(id) ON DELETE RESTRICT,
    underlying_ticker VARCHAR(32) NOT NULL,
    asset_name VARCHAR(64) NOT NULL,
    direction VARCHAR(16) NOT NULL
        CHECK (direction IN ('LONG', 'SHORT', 'DELTA_NEUTRAL', 'RELATIVE_VALUE')),
    instrument_structure VARCHAR(64) NOT NULL,
    entry_date DATE NOT NULL,
    exit_date DATE,
    trade_status VARCHAR(16) DEFAULT 'OPEN'
        CHECK (trade_status IN ('OPEN', 'CLOSED', 'STOPPED_OUT')),
    initial_risk_pct NUMERIC(4,2) NOT NULL,
    realized_r_multiple NUMERIC(6,2),
    realized_return_pct NUMERIC(7,2),
    portfolio_impact_bps INTEGER,
    greeks_snapshot JSONB DEFAULT '{}'::jsonb,
    pre_trade_thesis_md TEXT NOT NULL,
    execution_review_md TEXT,
    lessons_learned_md TEXT,
    discipline_score SMALLINT
        CHECK (discipline_score BETWEEN 1 AND 10),
    emotional_state_tag VARCHAR(32),
    private_blotter_oss_key TEXT,
    public_chart_oss_url TEXT,
    visibility VARCHAR(16) DEFAULT 'PUBLIC'
        CHECK (visibility IN ('PUBLIC', 'LP_PROSPECT', 'INTERNAL')),
    embedding vector(1536),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_trade_reviews_strat ON capital.trade_reviews(strategy_id, entry_date DESC);
CREATE INDEX idx_trade_reviews_status ON capital.trade_reviews(trade_status, visibility);
CREATE INDEX idx_trade_reviews_vec ON capital.trade_reviews USING hnsw (embedding vector_cosine_ops);

-- 4. 莫伯资本对冲基金孵化里程碑表 (fund_incubation_milestones)
CREATE TABLE IF NOT EXISTS capital.fund_incubation_milestones (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phase_number SMALLINT NOT NULL CHECK (phase_number IN (1, 2, 3)),
    phase_name VARCHAR(64) NOT NULL,
    domain_category VARCHAR(32) NOT NULL
        CHECK (domain_category IN (
            'TRACK_RECORD', 'LEGAL_COMPLIANCE', 'FINANCE_VALUATION', 'TECH_INFRA', 'LP_AND_BRAND'
        )),
    milestone_title VARCHAR(128) NOT NULL,
    target_metric_desc VARCHAR(256) NOT NULL,
    current_progress_pct SMALLINT DEFAULT 0 CHECK (current_progress_pct BETWEEN 0 AND 100),
    target_date DATE NOT NULL,
    completed_date DATE,
    status VARCHAR(20) DEFAULT 'IN_PROGRESS'
        CHECK (status IN ('PLANNED', 'IN_PROGRESS', 'COMPLETED', 'DELAYED')),
    action_plan_md TEXT,
    visibility VARCHAR(16) DEFAULT 'PUBLIC'
        CHECK (visibility IN ('PUBLIC', 'LP_PROSPECT', 'INTERNAL')),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 5. 基金治理、财税法合规与致合伙人文档表 (fund_governance_docs)
CREATE TABLE IF NOT EXISTS capital.fund_governance_docs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doc_slug VARCHAR(128) UNIQUE NOT NULL,
    doc_type VARCHAR(32) NOT NULL
        CHECK (doc_type IN ('INVESTOR_LETTER', 'RISK_SOP', 'LEGAL_STRUCT', 'NAV_ACCOUNTING', 'PITCH_DECK')),
    title VARCHAR(256) NOT NULL,
    version VARCHAR(16) DEFAULT 'v1.0',
    summary TEXT,
    content_md TEXT NOT NULL,
    private_attachment_oss_key TEXT,
    visibility VARCHAR(16) DEFAULT 'LP_PROSPECT'
        CHECK (visibility IN ('PUBLIC', 'LP_PROSPECT', 'INTERNAL')),
    published_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 6. 财经自媒体“1+3”多平台合成与发布主表 (capital_publications)
CREATE TABLE IF NOT EXISTS capital.capital_publications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug VARCHAR(128) UNIQUE NOT NULL,
    category VARCHAR(32) NOT NULL
        CHECK (category IN ('MACRO', 'STRATEGY', 'TRADE_REVIEW', 'FUND_VISION', 'PHILOSOPHY')),
    title VARCHAR(256) NOT NULL,
    summary TEXT,
    related_thesis_id UUID REFERENCES capital.macro_theses(id) ON DELETE SET NULL,
    related_trade_id UUID REFERENCES capital.trade_reviews(id) ON DELETE SET NULL,
    related_milestone_id UUID REFERENCES capital.fund_incubation_milestones(id) ON DELETE SET NULL,
    source_siyuan_id VARCHAR(64),
    web_markdown TEXT NOT NULL,
    wechat_html TEXT,
    xueqiu_markdown TEXT,
    x_thread_json JSONB DEFAULT '[]'::jsonb,
    toutiao_markdown TEXT,
    cover_oss_url TEXT,
    tags TEXT[] DEFAULT '{}',
    visibility VARCHAR(16) DEFAULT 'PUBLIC'
        CHECK (visibility IN ('PUBLIC', 'LP_PROSPECT', 'INTERNAL')),
    publish_status VARCHAR(20) DEFAULT 'DRAFT'
        CHECK (publish_status IN ('DRAFT', 'PENDING_REVIEW', 'APPROVED', 'PUBLISHED', 'FAILED')),
    wechat_draft_media_id VARCHAR(128),
    xueqiu_post_url TEXT,
    x_root_tweet_id VARCHAR(64),
    embedding vector(1536),
    published_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_cap_pub_cat_date ON capital.capital_publications(category, publish_status, published_at DESC);
CREATE INDEX idx_cap_pub_vec ON capital.capital_publications USING hnsw (embedding vector_cosine_ops);

-- 7. 财经自媒体全渠道运营与私域转化指标表 (media_channel_metrics)
CREATE TABLE IF NOT EXISTS capital.media_channel_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    publication_id UUID REFERENCES capital.capital_publications(id) ON DELETE CASCADE,
    channel VARCHAR(24) NOT NULL
        CHECK (channel IN ('WECHAT', 'XUEQIU', 'X_TWITTER', 'TOUTIAO', 'MOBOCAPITAL_WEB')),
    snapshot_date DATE NOT NULL DEFAULT CURRENT_DATE,
    impressions INTEGER DEFAULT 0,
    views_or_reads INTEGER DEFAULT 0,
    likes_and_bookmarks INTEGER DEFAULT 0,
    comments_and_shares INTEGER DEFAULT 0,
    net_new_followers INTEGER DEFAULT 0,
    referral_clicks_to_web INTEGER DEFAULT 0,
    UNIQUE (publication_id, channel, snapshot_date)
);

-- 视图 1: 莫伯资本各策略体系实战胜率、盈亏比与纪律得分聚合视图
CREATE OR REPLACE VIEW capital.v_strategy_performance_summary AS
SELECT 
    sp.strategy_code,
    sp.name AS strategy_name,
    sp.strategy_family,
    sp.target_sharpe,
    COUNT(tr.id) FILTER (WHERE tr.trade_status IN ('CLOSED', 'STOPPED_OUT')) AS closed_trades_count,
    ROUND(
        100.0 * COUNT(tr.id) FILTER (WHERE tr.realized_r_multiple > 0) / 
        NULLIF(COUNT(tr.id) FILTER (WHERE tr.trade_status IN ('CLOSED', 'STOPPED_OUT')), 0), 
        2
    ) AS actual_win_rate_pct,
    ROUND(AVG(tr.realized_r_multiple) FILTER (WHERE tr.realized_r_multiple > 0), 2) AS avg_win_r,
    ROUND(AVG(tr.realized_r_multiple) FILTER (WHERE tr.realized_r_multiple < 0), 2) AS avg_loss_r,
    ROUND(SUM(tr.realized_r_multiple), 2) AS cumulative_r_multiple,
    ROUND(AVG(tr.discipline_score), 1) AS avg_discipline_score
FROM capital.strategy_playbooks sp
LEFT JOIN capital.trade_reviews tr ON sp.id = tr.strategy_id
WHERE sp.is_active = TRUE
GROUP BY sp.id, sp.strategy_code, sp.name, sp.strategy_family, sp.target_sharpe;

-- 视图 2: 《MoBo's Memo》自媒体多平台分发表现与私域导流效率视图
CREATE OR REPLACE VIEW v_media_conversion_funnel AS
SELECT 
    cp.category AS content_category,
    mcm.channel,
    COUNT(DISTINCT cp.id) AS published_articles,
    SUM(mcm.impressions) AS total_impressions,
    SUM(mcm.views_or_reads) AS total_reads,
    SUM(mcm.likes_and_bookmarks) AS total_high_value_engagements,
    SUM(mcm.net_new_followers) AS total_followers_gained,
    SUM(mcm.referral_clicks_to_web) AS total_web_referrals,
    ROUND(
        1000.0 * SUM(mcm.net_new_followers) / NULLIF(SUM(mcm.views_or_reads), 0), 
        2
    ) AS followers_per_1k_reads
FROM capital_publications cp
JOIN media_channel_metrics mcm ON cp.id = mcm.publication_id
WHERE cp.publish_status = 'PUBLISHED'
GROUP BY cp.category, mcm.channel;

-- 预置三阶段基金孵化里程碑 Seed Data
INSERT INTO fund_incubation_milestones 
(phase_number, phase_name, domain_category, milestone_title, target_metric_desc, current_progress_pct, target_date, status, visibility)
VALUES
(1, 'Phase 1: 自营交易与体系化筑基', 'TRACK_RECORD', '建立 ITPM 全球宏观与期权波动率实盘复盘账本', '完成至少 30 笔完整周期的宏观/期权结构化交易归因，平均执行纪律得分不低于 8.5/10', 65, '2027-06-30', 'IN_PROGRESS', 'PUBLIC'),
(1, 'Phase 1: 自营交易与体系化筑基', 'LEGAL_COMPLIANCE', '攻克法律职业资格（法考）与证券从业资格', '建立私募基金合同、合规募集边界与投资者适当性管理的底层法律认知护城河', 60, '2027-10-31', 'IN_PROGRESS', 'PUBLIC'),
(1, 'Phase 1: 自营交易与体系化筑基', 'FINANCE_VALUATION', '攻克中级会计师并搭建基金 NAV 估值核算模型', '熟练掌握企业财报深度排雷与对冲基金高水位法（High-Water Mark）业绩报酬计提逻辑', 55, '2027-09-30', 'IN_PROGRESS', 'PUBLIC'),
(1, 'Phase 1: 自营交易与体系化筑基', 'LP_AND_BRAND', '《MoBo''s Memo》四端同源投研品牌矩阵冷启动', '累计发布 100 篇高质量宏观与策略深度长文，构建莫伯资本主站核心订阅者私域池', 35, '2027-12-31', 'IN_PROGRESS', 'PUBLIC'),
(2, 'Phase 2: 种子孵化与可审计业绩验证', 'TRACK_RECORD', '完成连续 18-24 个月低回撤可验证实盘曲线', '年化夏普比率大于 1.5，最大回撤严格控制在 10% 以内，完成第三方或券商 PB 业绩鉴证', 15, '2028-12-31', 'PLANNED', 'LP_PROSPECT'),
(2, 'Phase 2: 种子孵化与可审计业绩验证', 'TECH_INFRA', '升级莫伯资本投委会风控系统与自动化组合监控', '实现组合 Delta/Vega/行业净敞口超限自动预警与强制减仓风控熔断工作流', 30, '2028-06-30', 'PLANNED', 'LP_PROSPECT'),
(3, 'Phase 3: 莫伯资本独立对冲基金设立', 'LEGAL_COMPLIANCE', '完成独立基金主体架构设立与首批种子 LP 关账', '确立管理人/基金架构，落实独立托管与外包估值，正式开启机构化资产管理运作', 10, '2030-01-01', 'PLANNED', 'LP_PROSPECT');