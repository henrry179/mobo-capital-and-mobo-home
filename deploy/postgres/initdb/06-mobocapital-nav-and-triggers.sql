-- ============================================================================
-- 文件路径: /opt/mobo-stack/deploy/postgres/initdb/05-mobocapital-nav-and-triggers.sql
-- 目标数据库: db_mobobrain  Schema: capital  属主: user_mobobrain
-- 核心功能: 组合 NAV 高水位估值核算、三级风控熔断触发器与四大策略手册 Seed Data
-- ============================================================================

\c db_mobobrain

-- 全部对象落在 capital Schema（与 intel 采集域、n8n 自动化域隔离）
SET search_path TO capital, public;

CREATE TABLE IF NOT EXISTS capital.portfolio_nav_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    valuation_date DATE UNIQUE NOT NULL DEFAULT CURRENT_DATE,
    trigger_trade_code VARCHAR(40),
    gross_nav NUMERIC(10,4) NOT NULL DEFAULT 1.0000,
    high_water_mark NUMERIC(10,4) NOT NULL DEFAULT 1.0000,
    accrued_perf_fee_nav NUMERIC(10,4) DEFAULT 0.0000,
    net_nav NUMERIC(10,4) NOT NULL DEFAULT 1.0000,
    current_drawdown_pct NUMERIC(6,2) NOT NULL DEFAULT 0.00,
    cumulative_r_multiple NUMERIC(8,2) NOT NULL DEFAULT 0.00,
    risk_regime_status VARCHAR(24) NOT NULL DEFAULT 'NORMAL'
        CHECK (risk_regime_status IN ('NORMAL', 'YELLOW_ALERT', 'RED_CIRCUIT_BREAKER')),
    risk_action_note TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO capital.portfolio_nav_ledger (
    valuation_date, trigger_trade_code, gross_nav, high_water_mark, net_nav, 
    current_drawdown_pct, cumulative_r_multiple, risk_regime_status, risk_action_note
) VALUES (
    '2026-01-01', 'GENESIS-INIT', 1.0000, 1.0000, 1.0000, 
    0.00, 0.00, 'NORMAL', '莫伯资本 Phase 1 实盘孵化组合初始基准净值 (NAV = 1.0000)'
) ON CONFLICT (valuation_date) DO NOTHING;

CREATE OR REPLACE FUNCTION fn_update_nav_on_trade_close()
RETURNS TRIGGER AS $$
DECLARE
    v_prev_nav NUMERIC(10,4);
    v_prev_hwm NUMERIC(10,4);
    v_total_r NUMERIC(8,2);
    v_new_gross_nav NUMERIC(10,4);
    v_new_hwm NUMERIC(10,4);
    v_perf_fee NUMERIC(10,4);
    v_new_net_nav NUMERIC(10,4);
    v_drawdown_pct NUMERIC(6,2);
    v_risk_status VARCHAR(24);
    v_risk_note TEXT;
BEGIN
    IF NEW.trade_status IN ('CLOSED', 'STOPPED_OUT') AND NEW.portfolio_impact_bps IS NOT NULL THEN
        SELECT gross_nav, high_water_mark 
        INTO v_prev_nav, v_prev_hwm
        FROM capital.portfolio_nav_ledger
        ORDER BY valuation_date DESC, created_at DESC
        LIMIT 1;

        v_prev_nav := COALESCE(v_prev_nav, 1.0000);
        v_prev_hwm := COALESCE(v_prev_hwm, 1.0000);

        SELECT COALESCE(SUM(realized_r_multiple), 0.00)
        INTO v_total_r
        FROM capital.trade_reviews
        WHERE trade_status IN ('CLOSED', 'STOPPED_OUT');

        SELECT 1.0000 + COALESCE(SUM(portfolio_impact_bps), 0) / 10000.0
        INTO v_new_gross_nav
        FROM capital.trade_reviews
        WHERE trade_status IN ('CLOSED', 'STOPPED_OUT');

        v_new_hwm := GREATEST(v_prev_hwm, v_new_gross_nav);

        IF v_new_gross_nav > 1.0000 THEN
            v_perf_fee := ROUND((v_new_gross_nav - 1.0000) * 0.20, 4);
        ELSE
            v_perf_fee := 0.0000;
        END IF;

        v_new_net_nav := v_new_gross_nav - v_perf_fee;
        v_drawdown_pct := ROUND(((v_new_gross_nav - v_new_hwm) / v_new_hwm) * 100.0, 2);

        IF v_drawdown_pct <= -8.00 THEN
            v_risk_status := 'RED_CIRCUIT_BREAKER';
            v_risk_note := '【红色风控熔断】组合回撤已触及 -8% 警戒线！强制将总敞口压降至 25% 以内，禁止新开买方期权头寸。';
        ELSIF v_drawdown_pct <= -5.00 THEN
            v_risk_status := 'YELLOW_ALERT';
            v_risk_note := '【黄色回撤预警】组合回撤超过 -5%，单笔最大风险敞口由 1.50% 下调至 0.75% NAV。';
        ELSE
            v_risk_status := 'NORMAL';
            v_risk_note := '组合净值运行稳健，维持标准风险预算（单笔不超过 1.50% NAV）。';
        END IF;

        INSERT INTO capital.portfolio_nav_ledger (
            valuation_date, trigger_trade_code, gross_nav, high_water_mark,
            accrued_perf_fee_nav, net_nav, current_drawdown_pct,
            cumulative_r_multiple, risk_regime_status, risk_action_note
        ) VALUES (
            COALESCE(NEW.exit_date, CURRENT_DATE), NEW.trade_code, v_new_gross_nav, v_new_hwm,
            v_perf_fee, v_new_net_nav, v_drawdown_pct,
            v_total_r, v_risk_status, v_risk_note
        )
        ON CONFLICT (valuation_date) DO UPDATE SET
            trigger_trade_code = EXCLUDED.trigger_trade_code,
            gross_nav = EXCLUDED.gross_nav,
            high_water_mark = EXCLUDED.high_water_mark,
            accrued_perf_fee_nav = EXCLUDED.accrued_perf_fee_nav,
            net_nav = EXCLUDED.net_nav,
            current_drawdown_pct = EXCLUDED.current_drawdown_pct,
            cumulative_r_multiple = EXCLUDED.cumulative_r_multiple,
            risk_regime_status = EXCLUDED.risk_regime_status,
            risk_action_note = EXCLUDED.risk_action_note,
            created_at = CURRENT_TIMESTAMP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = capital, public;

DROP TRIGGER IF EXISTS trg_auto_calc_nav_on_trade ON capital.trade_reviews;
CREATE TRIGGER trg_auto_calc_nav_on_trade
AFTER INSERT OR UPDATE ON capital.trade_reviews
FOR EACH ROW
EXECUTE FUNCTION fn_update_nav_on_trade_close();

INSERT INTO capital.strategy_playbooks (
    strategy_code, name, strategy_family, holding_period, target_sharpe,
    target_win_rate_pct, target_rr_ratio, max_risk_per_trade_pct, max_sector_exposure_pct,
    entry_rules_md, option_structure_guide, exit_and_stop_rules_md, visibility
) VALUES
(
    'OPT-VOL-SKEW-01', '期权波动率偏度与跨式非对称策略', 'OPTIONS_VOL', '2-6 Weeks',
    1.95, 65.0, 2.80, 1.25, 25.0,
    '1. 宏观或行业催化剂明确且先行指标 Z-Score 大于 +1.0σ；2. 标的 30D IV Rank 处于 30% 分位以下或 80% 分位以上。',
    '低 IV 买方向使用 Bull Call / Bear Put Spread (45DTE)；高 Skew 环境使用 1x2 Ratio Spread 或 Calendar Spread。',
    '单笔权利金最大亏损严格锁死在 1.25% NAV；到期前 7 天无条件移仓或平仓规避尾部 Gamma 风险。', 'PUBLIC'
),
(
    'ITPM-LS-EQUITY', 'ITPM 基本面多空配对股票策略 (L/S Equity)', 'LONG_SHORT_EQUITY', '1-3 Months',
    1.75, 60.0, 2.50, 1.50, 30.0,
    '结合自上而下 PMI/社融先行指标与零售/供应链微观周转率印证，做多自由现金流拐点龙头，同时配对做空基本面恶化同业标的。',
    '以现货配对为主，辅以卖出虚值 Covered Call 增厚持仓收益。',
    '配对组合触及 -1.0R（即 1.50% NAV）或基本面证伪条件触发时，双腿同步无条件平仓。', 'PUBLIC'
),
(
    'MACRO-CROSS-ASSET', '全球宏观跨资产趋势与利差对冲策略', 'MACRO_DIRECTIONAL', '1-6 Months',
    1.60, 55.0, 3.00, 1.00, 25.0,
    '围绕中美欧货币政策周期错位、M1-M2 剪刀差与实际利差变化，在宽基股指 ETF、国债 ETF 与黄金期权之间构建低相关性宏观头寸。',
    '优先采用对角价差 (Diagonal Spread) 或远期合成头寸控制资金占用。',
    '宏观先行指标连续两个月逆转或触及预设证伪点位时立即止损离场。', 'PUBLIC'
),
(
    'TAIL-RISK-SHIELD', '尾部风险保护伞与系统性熔断对冲', 'EVENT_DRIVEN', 'Continuous',
    1.40, 40.0, 5.00, 0.50, 15.0,
    '当全市场 VIX 或 300ETF 隐含波动率跌入历史 15% 极低分位且市场情绪极度乐观时，定投远月深度虚值 Put 作为组合保险。',
    '60-90DTE 10-Delta 至 15-Delta 虚值 Put 或 Put Backspread。',
    '市场发生黑天鹅急跌、Vega 脉冲式飙升超过 4R 时分批止盈兑现，将所得现金反哺低估核心资产。', 'LP_PROSPECT'
)
ON CONFLICT (strategy_code) DO NOTHING;

INSERT INTO capital.macro_theses (
    thesis_code, title, region, asset_class, time_horizon,
    directional_bias, conviction_score, leading_indicators,
    core_logic_md, invalidation_criteria, status, visibility
) VALUES
(
    'THESIS-2026Q4-CN-RETAIL',
    '中国必选消费与生鲜冷链供应链：高周转率企业的自由现金流重估',
    'CN', 'MULTI', '3_6_MONTHS', 'BULLISH', 8,
    '{"PMI_NewOrders": 51.4, "Inventory_Turnover_Days": "-14%", "300ETF_IV_Rank": "28%"}'::jsonb,
    '高频渠道与供应链数据显示，具备数字化仓配能力的生鲜零售企业已越过资本开支高峰，库存周转天数缩短，而期权隐含波动率仍处于 28% 低分位。',
    '若社零餐饮分项连续两个月环比回落超 1.5%，无条件平仓全部多头期权头寸。', 'ACTIVE', 'PUBLIC'
),
(
    'THESIS-2026Q4-US-VOL-SKEW',
    '美债期限溢价回升背景下的美股科技股波动率偏度（Skew）均值回归',
    'US', 'EQUITY', '1_3_MONTHS', 'VOL_LONG', 9,
    '{"US10Y_Yield": "4.18%", "SPY_25D_Skew_Pct": "92%", "ISM_NewOrders": 48.9}'::jsonb,
    '美股内部宽度收窄且机构尾部保护需求推高 Put-Call Skew 至 92% 分位，适合通过认沽比例价差博弈波动率中枢上移。',
    '若 VIX 跌破 13.5 且 ISM 新订单超预期跃升至 53 以上，立即止损平仓。', 'ACTIVE', 'PUBLIC'
)
ON CONFLICT (thesis_code) DO NOTHING;