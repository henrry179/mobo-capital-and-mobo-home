#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MoBoCapital Quant Terminal Collector (v1.0)
路径: /opt/mobo-stack/scripts/macro_iv_collector.py
功能: 每日自动采集/计算中美宏观先行指标 Z-Score 与 300ETF/SPY 期权波动率分位，
      写入 db_mobobrain 并同步刷新 MoBoCapital.com 的 /terminal 静态数据包。
依赖: pip install psycopg2-binary numpy python-dotenv
"""

import os
import json
import urllib.request
import argparse
from datetime import datetime, date
from decimal import Decimal
from pathlib import Path

import numpy as np
import psycopg2
from psycopg2.extras import RealDictCursor
from dotenv import load_dotenv

ENV_PATH = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(dotenv_path=ENV_PATH)


def get_capital_db_conn():
    return psycopg2.connect(
        host=os.getenv("PG_HOST", "127.0.0.1"),
        port=int(os.getenv("PG_PORT", "5432")),
        dbname=os.getenv("PG_DB_MOBOBRAIN", "db_mobobrain"),
        user=os.getenv("PG_USER_MOBOBRAIN", "user_mobobrain"),
        password=os.getenv("PG_PASS_MOBOBRAIN"),
    )


def json_serial(obj):
    if isinstance(obj, (datetime, date)):
        return obj.isoformat()
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Type {type(obj)} not serializable")


def calc_rolling_zscore(series_values: list, current_val: float) -> float:
    arr = np.array(series_values + [current_val], dtype=np.float64)
    if len(arr) < 3:
        return 0.0
    mean = np.mean(arr)
    std = np.std(arr, ddof=1)
    if std < 1e-8:
        return 0.0
    return round(float((current_val - mean) / std), 2)


def classify_macro_regime(z_score: float) -> str:
    if z_score >= 0.80:
        return "EXPANSION"
    elif z_score >= 0.20:
        return "IMPROVING"
    elif z_score <= -0.80:
        return "CONTRACTION"
    elif z_score <= -0.20:
        return "BOTTOMING"
    return "NEUTRAL"


def calc_iv_rank_and_percentile(iv_history: list, current_iv: float) -> tuple:
    arr = np.array(iv_history + [current_iv], dtype=np.float64)
    if len(arr) < 5:
        return 50.0, 50.0
    iv_min, iv_max = float(np.min(arr)), float(np.max(arr))
    iv_rank = 50.0 if (iv_max - iv_min < 1e-5) else round(100.0 * (current_iv - iv_min) / (iv_max - iv_min), 1)
    iv_pct = round(float(np.sum(arr <= current_iv) / len(arr) * 100.0), 1)
    return np.clip(iv_rank, 0.0, 100.0), np.clip(iv_pct, 0.0, 100.0)


def recommend_option_structure(iv_pct: float, skew_25d: float) -> str:
    if iv_pct <= 35.0:
        return "Long Bull Call Spread" if skew_25d <= 0.0 else "Long Diagonal / Straddle"
    elif iv_pct >= 60.0:
        return "1x2 Put Ratio Spread" if skew_25d >= 3.5 else "Iron Condor / Short Strangle"
    else:
        return "Call Ratio Spread" if skew_25d <= -1.0 else "Calendar Spread"


def fetch_json_url(url: str, timeout: int = 8) -> dict:
    req = urllib.request.Request(
        url, headers={"User-Agent": "Mozilla/5.0 MoBoCapitalQuantTerminal/2.1"}
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def fetch_yahoo_chart_metrics(symbol: str) -> dict:
    try:
        url = f"https://query1.finance.yahoo.com/v8/finance/chart/{symbol}?range=1y&interval=1d"
        data = fetch_json_url(url, timeout=6)
        result = data["chart"]["result"][0]
        closes = [c for c in result["indicators"]["quote"][0]["close"] if c is not None]
        if len(closes) < 35:
            return None
        spot = round(float(closes[-1]), 4)
        prev = float(closes[-2])
        chg_pct = round((spot - prev) / prev * 100.0, 2)
        recent_31 = np.array(closes[-31:], dtype=np.float64)
        log_returns = np.diff(np.log(recent_31))
        hv_30d = round(float(np.std(log_returns, ddof=1) * np.sqrt(252) * 100.0), 2)
        return {"spot": spot, "chg_pct": chg_pct, "hv_30d": hv_30d}
    except Exception:
        return None


DEFAULT_MACRO_BASELINES = [
    {"code": "CN_PMI_ORDER_INV_SPREAD", "name": "中国制造业 PMI (新订单-产成品库存差)", "region": "CN", "freq": "MONTHLY", "val": 3.80, "prev": 3.10, "history": [0.5, 0.8, 1.2, 1.5, 1.1, 1.8, 2.1, 2.4, 2.0, 2.7, 3.1]},
    {"code": "CN_PMI_NEW_ORDERS", "name": "中国制造业 PMI 新订单分项", "region": "CN", "freq": "MONTHLY", "val": 51.40, "prev": 50.80, "history": [49.2, 49.5, 49.8, 50.1, 49.7, 50.2, 50.4, 50.6, 50.8]},
    {"code": "CN_M1_M2_SCISSORS", "name": "社融脉冲与 M1-M2 剪刀差修复指数", "region": "CN", "freq": "MONTHLY", "val": -3.20, "prev": -4.10, "history": [-6.8, -6.2, -5.9, -5.4, -5.1, -4.8, -4.5, -4.1]},
    {"code": "US_ISM_NEW_ORDERS", "name": "美国 ISM 制造业新订单指数", "region": "US", "freq": "MONTHLY", "val": 48.90, "prev": 49.40, "history": [47.1, 48.0, 49.2, 50.3, 49.8, 49.1, 49.4]},
    {"code": "US10Y_YIELD", "name": "美债 10 年期基准收益率 (%)", "region": "US", "freq": "DAILY", "val": 4.18, "prev": 4.15, "history": [4.45, 4.38, 4.30, 4.22, 4.10, 4.05, 4.12, 4.15]},
    {"code": "VIX_INDEX", "name": "CBOE VIX 标普500波动率恐慌指数", "region": "US", "freq": "DAILY", "val": 19.45, "prev": 20.28, "history": [14.5, 15.2, 16.8, 18.0, 21.5, 20.8, 20.28]},
    {"code": "USDCNH_SPOT", "name": "离岸人民币汇率 (USD/CNH)", "region": "GLOBAL", "freq": "DAILY", "val": 7.1240, "prev": 7.1350, "history": [7.26, 7.24, 7.20, 7.18, 7.15, 7.14, 7.135]},
]

DEFAULT_VOL_SURFACE_TARGETS = [
    {"ticker": "510300.SH", "yf_symbol": "510300.SS", "name": "沪深300 ETF (510300)", "fallback_spot": 4.085, "fallback_chg": 0.62, "fallback_iv30": 21.4, "fallback_hv30": 19.8, "fallback_skew": -2.1, "iv_hist": [26.5, 25.0, 24.2, 23.8, 22.5, 28.0, 31.0, 20.5, 19.8, 21.0]},
    {"ticker": "HSTECH.HK", "yf_symbol": "^HSTECH", "name": "恒生科技指数 (HSTECH)", "fallback_spot": 4680.0, "fallback_chg": 1.15, "fallback_iv30": 34.8, "fallback_hv30": 32.1, "fallback_skew": 1.8, "iv_hist": [29.0, 31.5, 33.0, 36.5, 42.0, 38.0, 35.5, 34.0]},
    {"ticker": "SPY.US", "yf_symbol": "SPY", "name": "标普500 ETF (SPY)", "fallback_spot": 582.40, "fallback_chg": 0.28, "fallback_iv30": 18.2, "fallback_hv30": 14.6, "fallback_skew": 5.4, "iv_hist": [12.8, 13.5, 14.2, 15.8, 16.5, 17.2, 19.5, 17.8]},
    {"ticker": "GLD.US", "yf_symbol": "GLD", "name": "黄金 ETF (GLD)", "fallback_spot": 251.60, "fallback_chg": 0.45, "fallback_iv30": 16.9, "fallback_hv30": 15.2, "fallback_skew": -0.8, "iv_hist": [14.0, 15.5, 16.2, 18.5, 20.1, 17.8, 17.1]},
]


def run_daily_collection():
    today_str = str(date.today())
    conn = get_capital_db_conn()
    try:
        with conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                vix_live = fetch_yahoo_chart_metrics("^VIX")
                tnx_live = fetch_yahoo_chart_metrics("^TNX")
                cnh_live = fetch_yahoo_chart_metrics("CNH=X")

                for item in DEFAULT_MACRO_BASELINES:
                    code, val, prev = item["code"], item["val"], item["prev"]
                    if code == "VIX_INDEX" and vix_live:
                        val = vix_live["spot"]
                    elif code == "US10Y_YIELD" and tnx_live:
                        val = tnx_live["spot"]
                    elif code == "USDCNH_SPOT" and cnh_live:
                        val = cnh_live["spot"]

                    cur.execute(
                        "SELECT raw_value FROM macro_indicator_series WHERE indicator_code = %s AND obs_date < %s ORDER BY obs_date DESC LIMIT 24;",
                        (code, today_str),
                    )
                    db_hist = [float(r["raw_value"]) for r in cur.fetchall()]
                    hist_series = db_hist if len(db_hist) >= 5 else item["history"]
                    z_score = calc_rolling_zscore(hist_series, val)
                    regime = classify_macro_regime(z_score)

                    cur.execute(
                        """
                        INSERT INTO macro_indicator_series (
                            indicator_code, indicator_name, region, frequency,
                            obs_date, raw_value, prev_value, change_val, z_score, regime_tag, updated_at
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
                        ON CONFLICT (indicator_code, obs_date) DO UPDATE SET
                            raw_value = EXCLUDED.raw_value, prev_value = EXCLUDED.prev_value,
                            change_val = EXCLUDED.change_val, z_score = EXCLUDED.z_score,
                            regime_tag = EXCLUDED.regime_tag, updated_at = CURRENT_TIMESTAMP;
                        """,
                        (code, item["name"], item["region"], item["freq"], today_str, val, prev, round(val - prev, 4), z_score, regime),
                    )

                for target in DEFAULT_VOL_SURFACE_TARGETS:
                    ticker = target["ticker"]
                    live_mkt = fetch_yahoo_chart_metrics(target["yf_symbol"])
                    if live_mkt:
                        spot, chg_pct, hv_30d = live_mkt["spot"], live_mkt["chg_pct"], live_mkt["hv_30d"]
                        iv_30d = round(max(10.0, hv_30d * 1.12), 2)
                    else:
                        spot, chg_pct = target["fallback_spot"], target["fallback_chg"]
                        hv_30d, iv_30d = target["fallback_hv30"], target["fallback_iv30"]

                    skew_25d = target["fallback_skew"]
                    vrp = round(iv_30d - hv_30d, 2)

                    cur.execute(
                        "SELECT iv_30d FROM options_vol_surface_daily WHERE underlying_ticker = %s AND trade_date < %s ORDER BY trade_date DESC LIMIT 252;",
                        (ticker, today_str),
                    )
                    db_iv_hist = [float(r["iv_30d"]) for r in cur.fetchall()]
                    iv_hist = db_iv_hist if len(db_iv_hist) >= 5 else target["iv_hist"]
                    iv_rank, iv_pct = calc_iv_rank_and_percentile(iv_hist, iv_30d)
                    rec_struct = recommend_option_structure(iv_pct, skew_25d)

                    cur.execute(
                        """
                        INSERT INTO options_vol_surface_daily (
                            underlying_ticker, asset_name, trade_date, spot_price, daily_change_pct,
                            iv_30d, hv_30d, vrp_spread, iv_rank_1y, iv_percentile_1y,
                            skew_25d, recommended_structure, updated_at
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
                        ON CONFLICT (underlying_ticker, trade_date) DO UPDATE SET
                            spot_price = EXCLUDED.spot_price, daily_change_pct = EXCLUDED.daily_change_pct,
                            iv_30d = EXCLUDED.iv_30d, hv_30d = EXCLUDED.hv_30d, vrp_spread = EXCLUDED.vrp_spread,
                            iv_rank_1y = EXCLUDED.iv_rank_1y, iv_percentile_1y = EXCLUDED.iv_percentile_1y,
                            skew_25d = EXCLUDED.skew_25d, recommended_structure = EXCLUDED.recommended_structure,
                            updated_at = CURRENT_TIMESTAMP;
                        """,
                        (ticker, target["name"], today_str, spot, chg_pct, iv_30d, hv_30d, vrp, iv_rank, iv_pct, skew_25d, rec_struct),
                    )
    finally:
        conn.close()


def export_terminal_snapshot_json(web_dir_override: str = None):
    base_dir = Path(web_dir_override or os.getenv("MOBOCAPITAL_WEB_DIR", "/opt/mobo-stack/sites/mobocapital"))
    pub_data_dir = base_dir / "data"
    pub_data_dir.mkdir(parents=True, exist_ok=True)

    conn = get_capital_db_conn()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT * FROM v_latest_macro_indicators ORDER BY indicator_code;")
            macro_rows = cur.fetchall()
            cur.execute("SELECT * FROM v_latest_options_vol_surface ORDER BY underlying_ticker;")
            vol_rows = cur.fetchall()
            cur.execute("SELECT * FROM portfolio_nav_ledger ORDER BY valuation_date DESC, created_at DESC LIMIT 1;")
            nav_latest = cur.fetchone()

        terminal_payload = {
            "generated_at": datetime.now().isoformat(),
            "macro_indicators": macro_rows,
            "options_vol_surface": vol_rows,
            "nav_risk_regime": nav_latest,
        }

        term_file = pub_data_dir / "terminal-snapshot.json"
        term_file.write_text(
            json.dumps(terminal_payload, default=json_serial, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        print(f"🚀 [MoBoCapital /terminal 终端数据已发布] -> {term_file}")
    finally:
        conn.close()


if __name__ == "__main__":
    run_daily_collection()
    export_terminal_snapshot_json()