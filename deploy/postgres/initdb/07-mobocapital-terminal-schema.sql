-- ============================================================================
-- 文件路径: /opt/mobo-stack/deploy/postgres/initdb/06-mobocapital-terminal-schema.sql
-- 目标数据库: db_mobobrain  Schema: capital  属主: user_mobobrain
-- 核心功能: 支撑 MoBoCapital.com /terminal 量化终端的宏观 Z-Score 与期权波动率日频快照
-- ============================================================================

\c db_mobobrain

-- 全部对象落在 capital Schema（与 intel 采集域、n8n 自动化域隔离）
SET search_path TO capital, public;

CREATE TABLE IF NOT EXISTS capital.macro_indicator_series (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    indicator_code VARCHAR(40) NOT NULL,
    indicator_name VARCHAR(128) NOT NULL,
    region VARCHAR(16) NOT NULL DEFAULT 'GLOBAL',
    frequency VARCHAR(16) NOT NULL DEFAULT 'MONTHLY',
    obs_date DATE NOT NULL,
    raw_value NUMERIC(12,4) NOT NULL,
    prev_value NUMERIC(12,4),
    change_val NUMERIC(12,4),
    z_score NUMERIC(6,2) DEFAULT 0.00,
    regime_tag VARCHAR(24) DEFAULT 'NEUTRAL'
        CHECK (regime_tag IN ('EXPANSION', 'IMPROVING', 'NEUTRAL', 'BOTTOMING', 'CONTRACTION')),
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (indicator_code, obs_date)
);

CREATE INDEX idx_macro_series_code_date ON capital.macro_indicator_series(indicator_code, obs_date DESC);

CREATE TABLE IF NOT EXISTS capital.options_vol_surface_daily (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    underlying_ticker VARCHAR(32) NOT NULL,
    asset_name VARCHAR(64) NOT NULL,
    trade_date DATE NOT NULL DEFAULT CURRENT_DATE,
    spot_price NUMERIC(12,4) NOT NULL,
    daily_change_pct NUMERIC(6,2) DEFAULT 0.00,
    iv_30d NUMERIC(6,2) NOT NULL,
    hv_30d NUMERIC(6,2) NOT NULL,
    vrp_spread NUMERIC(6,2) NOT NULL,
    iv_rank_1y NUMERIC(5,2) NOT NULL,
    iv_percentile_1y NUMERIC(5,2) NOT NULL,
    skew_25d NUMERIC(6,2) NOT NULL,
    recommended_structure VARCHAR(64) NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (underlying_ticker, trade_date)
);

CREATE INDEX idx_opt_vol_ticker_date ON capital.options_vol_surface_daily(underlying_ticker, trade_date DESC);

CREATE OR REPLACE VIEW capital.v_latest_macro_indicators AS
SELECT DISTINCT ON (indicator_code)
    indicator_code, indicator_name, region, frequency, obs_date,
    raw_value, prev_value, change_val, z_score, regime_tag, updated_at
FROM capital.macro_indicator_series
ORDER BY indicator_code, obs_date DESC;

CREATE OR REPLACE VIEW capital.v_latest_options_vol_surface AS
SELECT DISTINCT ON (underlying_ticker)
    underlying_ticker, asset_name, trade_date, spot_price, daily_change_pct,
    iv_30d, hv_30d, vrp_spread, iv_rank_1y, iv_percentile_1y,
    skew_25d, recommended_structure, updated_at
FROM capital.options_vol_surface_daily
ORDER BY underlying_ticker, trade_date DESC;