#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""MoBoCapital 量化终端采集器（本地优先版 v2.1）。

职责（三段式，与前台 ``/terminal`` 栏目一一对应）：

1. **采集 + 计算**：拉取中美宏观先行指标与核心 ETF 行情，计算滚动 Z-Score、
   30 日历史波动率（HV30）、1 年期 IV Rank / IV Percentile 与 25D 偏度，
   自动匹配期权策略结构。
2. **入库**：写入 ``db_mobobrain.capital.macro_indicator_series`` 与
   ``capital.options_vol_surface_daily``（幂等 upsert，按日期去重）。
3. **发布**：触发静态数据包重导出，让前台立即看到新数据。

连接口径与 ``mobo-cli`` 完全一致（复用 ``mobo_cli.config.get_settings``）：

======================  ==========================================
主机                    ``CLI_PG_HOST`` → ``PG_HOST`` → ``127.0.0.1``
库名                    ``PG_DB_MOBOBRAIN``（默认 ``db_mobobrain``）
账号                    ``PG_USER_MOBOBRAIN``（默认 ``user_mobobrain``）
口令                    ``PG_PASS_MOBOBRAIN``
前台目录                ``MOBOCAPITAL_WEB_DIR``（默认 ``sites/mobocapital``）
======================  ==========================================

⚠️ 与生产（阿里云 ECS）版本的差异见
``docs/00-总册/生产级落地附录-v2.1.md`` 的「本地化落地差异」小节：
本地版**不写死行情兜底常量**，网络不可用时保持库内最近一期不变，避免污染时间序列。

用法（WSL 内）::

    /root/venv-mobo-cli/bin/python services/mobo-cli/collectors/macro_iv_collector.py \\
        --env-file .env.local                    # 每日采集 + 导出
    ... --check                                  # 只体检，不写库
    ... --export-only                            # 只重导出静态包
    ... --set-macro VIX 'CBOE VIX 恐慌指数' US 19.45 20.28
    ... --set-vol 510300.SH '沪深300ETF期权' 3.98 19.8 21.6 28.4 4.6
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import date, datetime
from pathlib import Path
from typing import Any

import numpy as np

# 让本文件既能被 `python services/mobo-cli/collectors/macro_iv_collector.py`
# 直接执行，也能被 pytest 以 `from collectors.macro_iv_collector import ...` 引用。
_PKG_ROOT = Path(__file__).resolve().parent.parent
if str(_PKG_ROOT) not in sys.path:
    sys.path.insert(0, str(_PKG_ROOT))

from mobo_cli.config import Settings, get_settings  # noqa: E402
from mobo_cli.db import connect_mobobrain  # noqa: E402

PROJECT_ROOT = _PKG_ROOT.parent.parent

# 环境文件自动探测顺序（本地优先：.env.local 优先于 .env）
ENV_CANDIDATES = (".env.local", ".env")


# =============================================================================
# 1. 环境与连接
# =============================================================================
def resolve_env_file(explicit: str | None) -> Path | None:
    """定位环境文件：显式参数 → MOBO_ENV_FILE → 项目根 .env.local / .env。"""
    if explicit:
        path = Path(explicit).expanduser()
        if not path.is_absolute():
            path = (Path.cwd() / path).resolve()
        return path if path.exists() else None

    from_env = os.getenv("MOBO_ENV_FILE")
    if from_env:
        path = Path(from_env).expanduser()
        if path.exists():
            return path

    for name in ENV_CANDIDATES:
        path = PROJECT_ROOT / name
        if path.exists():
            return path
    return None


def resolve_settings(
    env_file: str | None = None,
    web_dir: str | None = None,
) -> tuple[Settings, Path | None]:
    """构造 Settings：沿用 mobo-cli 的变量口径，并把前台目录解析成绝对路径。"""
    resolved_env = resolve_env_file(env_file)
    settings = get_settings(str(resolved_env) if resolved_env else None)

    target = Path(web_dir or settings.capital_web_dir)
    if not target.is_absolute():
        target = (PROJECT_ROOT / target).resolve()
    settings = dataclasses.replace(settings, capital_web_dir=str(target))
    return settings, resolved_env


def db_connection(settings: Settings):
    """连接 db_mobobrain（capital Schema）。"""
    return connect_mobobrain(settings)


# =============================================================================
# 2. 纯 NumPy 量化计算内核（无 IO，可单测）
# =============================================================================
def calc_rolling_zscore(series_values: list, current_val: float) -> float:
    """当前读数在过去窗口中的 Z-Score 偏离度。"""
    arr = np.array(list(series_values) + [current_val], dtype=np.float64)
    if len(arr) < 3:
        return 0.0
    mean = np.mean(arr)
    std = np.std(arr, ddof=1)
    if std < 1e-8:
        return 0.0
    return round(float((current_val - mean) / std), 2)


def classify_macro_regime(z_score: float) -> str:
    """Z-Score → 宏观周期状态标签。"""
    if z_score >= 0.80:
        return "EXPANSION"
    if z_score >= 0.20:
        return "IMPROVING"
    if z_score <= -0.80:
        return "CONTRACTION"
    if z_score <= -0.20:
        return "BOTTOMING"
    return "NEUTRAL"


def calc_iv_rank_and_percentile(iv_history: list, current_iv: float) -> tuple[float, float]:
    """IV Rank（区间位置）与 IV Percentile（分位占比）。"""
    arr = np.array(list(iv_history) + [current_iv], dtype=np.float64)
    if len(arr) < 5:
        return 50.0, 50.0

    iv_min, iv_max = float(np.min(arr)), float(np.max(arr))
    if iv_max - iv_min < 1e-5:
        iv_rank = 50.0
    else:
        iv_rank = round(100.0 * (current_iv - iv_min) / (iv_max - iv_min), 1)

    iv_pct = round(float(np.sum(arr <= current_iv) / len(arr) * 100.0), 1)
    return float(np.clip(iv_rank, 0.0, 100.0)), float(np.clip(iv_pct, 0.0, 100.0))


def recommend_option_structure(iv_pct: float, skew_25d: float) -> str:
    """IV 分位 + 25D 偏度 → 策略结构建议（与前台展示口径一致）。"""
    if iv_pct <= 35.0:
        if skew_25d <= 0.0:
            return "低 IV：Bull Call / Bear Put 垂直价差"
        return "低 IV + 正偏度：Long Diagonal / Straddle"
    if iv_pct >= 60.0:
        if skew_25d >= 3.5:
            return "高 IV + 高偏度：1x2 Put Ratio Spread"
        return "高 IV：Iron Condor / Short Strangle"
    if skew_25d <= -1.0:
        return "Call Ratio Spread"
    return "Calendar Spread（近月 Theta 收割）"


# =============================================================================
# 3. 行情抓取（超时保护 + 失败返回 None）
# =============================================================================
def fetch_json_url(url: str, timeout: int = 8) -> dict:
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 MoBoCapitalQuantTerminal/2.1"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def fetch_yahoo_chart_metrics(symbol: str, timeout: int = 6) -> dict | None:
    """拉日线收盘价，算最新价、涨跌幅与 30D 历史年化波动率。

    网络不可用（国内直连 Yahoo 常被限流）时返回 ``None``，由调用方决定降级策略。
    """
    try:
        url = f"https://query1.finance.yahoo.com/v8/finance/chart/{symbol}?range=1y&interval=1d"
        data = fetch_json_url(url, timeout=timeout)
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
    except (urllib.error.URLError, urllib.error.HTTPError, OSError, ValueError, KeyError, TypeError):
        return None


# =============================================================================
# 4. 采集目标清单
#
# indicator_code / underlying_ticker 与 `seeds/52-week-sandbox.sql` 里
# 已入库的序列**严格对齐**，避免采集器另起一套同名异义的序列。
# `yf_symbol=None` 表示没有免费公开行情源，只能由 --set-macro 手动注入
# （官方统计口径：PMI / 社融 / ISM / 非农 / 欧元区 PMI / 社零）。
# =============================================================================
MACRO_TARGETS: list[dict[str, Any]] = [
    {"code": "VIX", "name": "VIX 恐慌指数", "region": "US", "freq": "DAILY", "yf_symbol": "^VIX"},
    {"code": "US10Y_YIELD", "name": "美债 10 年期收益率", "region": "US", "freq": "DAILY", "yf_symbol": "^TNX"},
    {"code": "USD_CNH", "name": "美元兑离岸人民币", "region": "GLOBAL", "freq": "DAILY", "yf_symbol": "CNH=X"},
    {"code": "GOLD_USD", "name": "伦敦金（美元/盎司）", "region": "GLOBAL", "freq": "DAILY", "yf_symbol": "GC=F"},
    {"code": "BRENT", "name": "布伦特原油", "region": "GLOBAL", "freq": "DAILY", "yf_symbol": "BZ=F"},
    {"code": "CN_PMI_NEW_ORDERS", "name": "中国制造业 PMI 新订单", "region": "CN", "freq": "MONTHLY", "yf_symbol": None},
    {"code": "CN_PMI_PRICE", "name": "中国制造业 PMI 出厂价格", "region": "CN", "freq": "MONTHLY", "yf_symbol": None},
    {"code": "CN_SOCIAL_FINANCE", "name": "社会融资规模存量同比", "region": "CN", "freq": "MONTHLY", "yf_symbol": None},
    {"code": "CN_SOCIAL_RETAIL", "name": "中国社会消费品零售同比", "region": "CN", "freq": "MONTHLY", "yf_symbol": None},
    {"code": "US_ISM_NEW_ORDERS", "name": "美国 ISM 制造业新订单", "region": "US", "freq": "MONTHLY", "yf_symbol": None},
    {"code": "US_PAYROLL", "name": "美国非农就业新增", "region": "US", "freq": "MONTHLY", "yf_symbol": None},
    {"code": "EU_PMI_MFG", "name": "欧元区制造业 PMI", "region": "EU", "freq": "MONTHLY", "yf_symbol": None},
]

VOL_TARGETS: list[dict[str, Any]] = [
    {"ticker": "510300.SH", "name": "沪深300ETF期权", "yf_symbol": "510300.SS"},
    {"ticker": "159915.SZ", "name": "创业板 ETF 期权", "yf_symbol": "159915.SZ"},
    {"ticker": "SPY", "name": "SPDR 标普500 ETF", "yf_symbol": "SPY"},
    {"ticker": "GLD", "name": "SPDR 黄金 ETF", "yf_symbol": "GLD"},
]

# 没有免费期权链数据源时的 IV30 近似系数（HV30 × 系数）。
# 实盘请用 --set-vol 注入真实的 30D IV 与 25D Skew。
IV_ESTIMATE_FACTOR = 1.12
IV_FLOOR = 10.0


# =============================================================================
# 5. 库内读取辅助
# =============================================================================
def latest_macro_history(cur, code: str, before: str, limit: int = 24) -> list[float]:
    cur.execute(
        """
        SELECT raw_value FROM capital.macro_indicator_series
        WHERE indicator_code = %s AND obs_date < %s
        ORDER BY obs_date DESC LIMIT %s;
        """,
        (code, before, limit),
    )
    return [float(r[0]) for r in cur.fetchall()]


def latest_macro_row(cur, code: str):
    cur.execute(
        """
        SELECT obs_date, raw_value, prev_value FROM capital.macro_indicator_series
        WHERE indicator_code = %s ORDER BY obs_date DESC LIMIT 1;
        """,
        (code,),
    )
    return cur.fetchone()


def latest_vol_row(cur, ticker: str):
    cur.execute(
        """
        SELECT trade_date, spot_price, daily_change_pct, iv_30d, hv_30d,
               skew_25d, iv_rank_1y, iv_percentile_1y
        FROM capital.options_vol_surface_daily
        WHERE underlying_ticker = %s ORDER BY trade_date DESC LIMIT 1;
        """,
        (ticker,),
    )
    return cur.fetchone()


def vol_history(cur, ticker: str, before: str, limit: int = 252) -> list[float]:
    cur.execute(
        """
        SELECT iv_30d FROM capital.options_vol_surface_daily
        WHERE underlying_ticker = %s AND trade_date < %s
        ORDER BY trade_date DESC LIMIT %s;
        """,
        (ticker, before, limit),
    )
    return [float(r[0]) for r in cur.fetchall()]


# =============================================================================
# 6. 采集主流程
# =============================================================================
def run_daily_collection(settings: Settings, *, only: str | None = None) -> dict[str, int]:
    """采集 → 入库。返回统计信息。

    降级策略（与生产版的差别）：**行情拉取失败时不写兜底常量**，而是保留库内
    最近一期不变，只记 WARN。这样时间序列里不会混入伪造的观测值。
    """
    today = str(date.today())
    stats = {"written": 0, "skipped": 0, "failed": 0}
    conn = db_connection(settings)
    try:
        with conn:
            with conn.cursor() as cur:
                # ---------- 宏观先行指标 ----------
                for item in MACRO_TARGETS:
                    code = item["code"]
                    if only and only.upper() != code.upper():
                        continue
                    symbol = item["yf_symbol"]
                    if not symbol:
                        stats["skipped"] += 1
                        print(f"[SKIP] {code} 无公开行情源，需 --set-macro 手动注入")
                        continue

                    live = fetch_yahoo_chart_metrics(symbol)
                    if not live:
                        stats["skipped"] += 1
                        last = latest_macro_row(cur, code)
                        keep = f"（沿用库内最近一期 {last[0]}）" if last else "（库内暂无历史）"
                        print(f"[WARN] {code} 行情不可用{keep}，本次不写入")
                        continue

                    val = live["spot"]
                    prev_row = latest_macro_row(cur, code)
                    prev = float(prev_row[1]) if prev_row else val

                    hist = latest_macro_history(cur, code, today)
                    z_score = calc_rolling_zscore(hist, val)
                    regime = classify_macro_regime(z_score)

                    cur.execute(
                        """
                        INSERT INTO capital.macro_indicator_series (
                            indicator_code, indicator_name, region, frequency,
                            obs_date, raw_value, prev_value, change_val, z_score, regime_tag, updated_at
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
                        ON CONFLICT (indicator_code, obs_date) DO UPDATE SET
                            indicator_name = EXCLUDED.indicator_name,
                            raw_value = EXCLUDED.raw_value,
                            prev_value = EXCLUDED.prev_value,
                            change_val = EXCLUDED.change_val,
                            z_score = EXCLUDED.z_score,
                            regime_tag = EXCLUDED.regime_tag,
                            updated_at = CURRENT_TIMESTAMP;
                        """,
                        (
                            code,
                            item["name"],
                            item["region"],
                            item["freq"],
                            today,
                            val,
                            prev,
                            round(val - prev, 4),
                            z_score,
                            regime,
                        ),
                    )
                    stats["written"] += 1
                    print(f"[OK]   {code} = {val} (Z={z_score}σ, {regime})")

                # ---------- 期权波动率曲面 ----------
                for target in VOL_TARGETS:
                    ticker = target["ticker"]
                    if only and only.upper() != ticker.upper():
                        continue

                    live = fetch_yahoo_chart_metrics(target["yf_symbol"])
                    if not live:
                        stats["skipped"] += 1
                        last = latest_vol_row(cur, ticker)
                        keep = f"（沿用库内最近一期 {last[0]}）" if last else "（库内暂无历史）"
                        print(f"[WARN] {ticker} 行情不可用{keep}，本次不写入")
                        continue

                    spot = live["spot"]
                    chg_pct = live["chg_pct"]
                    hv_30d = live["hv_30d"]
                    iv_30d = round(max(IV_FLOOR, hv_30d * IV_ESTIMATE_FACTOR), 2)

                    # 25D 偏度是慢变结构参数：沿用库内最近一期
                    last_vol = latest_vol_row(cur, ticker)
                    skew_25d = float(last_vol[5]) if last_vol and last_vol[5] is not None else 0.0

                    hist = vol_history(cur, ticker, today)
                    iv_rank, iv_pct = calc_iv_rank_and_percentile(hist, iv_30d)
                    vrp = round(iv_30d - hv_30d, 2)
                    rec = recommend_option_structure(iv_pct, skew_25d)

                    cur.execute(
                        """
                        INSERT INTO capital.options_vol_surface_daily (
                            underlying_ticker, asset_name, trade_date, spot_price, daily_change_pct,
                            iv_30d, hv_30d, vrp_spread, iv_rank_1y, iv_percentile_1y,
                            skew_25d, recommended_structure, updated_at
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
                        ON CONFLICT (underlying_ticker, trade_date) DO UPDATE SET
                            asset_name = EXCLUDED.asset_name,
                            spot_price = EXCLUDED.spot_price,
                            daily_change_pct = EXCLUDED.daily_change_pct,
                            iv_30d = EXCLUDED.iv_30d,
                            hv_30d = EXCLUDED.hv_30d,
                            vrp_spread = EXCLUDED.vrp_spread,
                            iv_rank_1y = EXCLUDED.iv_rank_1y,
                            iv_percentile_1y = EXCLUDED.iv_percentile_1y,
                            skew_25d = EXCLUDED.skew_25d,
                            recommended_structure = EXCLUDED.recommended_structure,
                            updated_at = CURRENT_TIMESTAMP;
                        """,
                        (
                            ticker,
                            target["name"],
                            today,
                            spot,
                            chg_pct,
                            iv_30d,
                            hv_30d,
                            vrp,
                            iv_rank,
                            iv_pct,
                            skew_25d,
                            rec,
                        ),
                    )
                    stats["written"] += 1
                    print(f"[OK]   {ticker} spot={spot} IV30={iv_30d} IVP={iv_pct} skew={skew_25d} → {rec}")
        conn.commit()
    finally:
        conn.close()
    return stats


# =============================================================================
# 7. 手动覆写（官方统计口径 / 实盘 IV 与 Skew）
# =============================================================================
def manual_override_macro(
    settings: Settings,
    *,
    code: str,
    name: str,
    region: str,
    val: float,
    prev: float,
    freq: str = "MONTHLY",
) -> None:
    today = str(date.today())
    conn = db_connection(settings)
    try:
        with conn:
            with conn.cursor() as cur:
                hist = latest_macro_history(cur, code, today)
                z_score = calc_rolling_zscore(hist, val)
                regime = classify_macro_regime(z_score)
                cur.execute(
                    """
                    INSERT INTO capital.macro_indicator_series (
                        indicator_code, indicator_name, region, frequency,
                        obs_date, raw_value, prev_value, change_val, z_score, regime_tag, updated_at
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
                    ON CONFLICT (indicator_code, obs_date) DO UPDATE SET
                        indicator_name = EXCLUDED.indicator_name,
                        raw_value = EXCLUDED.raw_value,
                        prev_value = EXCLUDED.prev_value,
                        change_val = EXCLUDED.change_val,
                        z_score = EXCLUDED.z_score,
                        regime_tag = EXCLUDED.regime_tag,
                        updated_at = CURRENT_TIMESTAMP;
                    """,
                    (code, name, region, freq, today, val, prev, round(val - prev, 4), z_score, regime),
                )
        conn.commit()
        print(f"[覆写] {code} = {val}（前值 {prev}，Z={z_score}σ，状态 {regime}）")
    finally:
        conn.close()


def manual_override_vol(
    settings: Settings,
    *,
    ticker: str,
    name: str,
    spot: float,
    iv30: float,
    hv30: float,
    iv_pct: float,
    skew: float,
    chg_pct: float = 0.0,
) -> None:
    today = str(date.today())
    vrp = round(iv30 - hv30, 2)
    rec = recommend_option_structure(iv_pct, skew)
    conn = db_connection(settings)
    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO capital.options_vol_surface_daily (
                        underlying_ticker, asset_name, trade_date, spot_price, daily_change_pct,
                        iv_30d, hv_30d, vrp_spread, iv_rank_1y, iv_percentile_1y,
                        skew_25d, recommended_structure, updated_at
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
                    ON CONFLICT (underlying_ticker, trade_date) DO UPDATE SET
                        asset_name = EXCLUDED.asset_name,
                        spot_price = EXCLUDED.spot_price,
                        daily_change_pct = EXCLUDED.daily_change_pct,
                        iv_30d = EXCLUDED.iv_30d,
                        hv_30d = EXCLUDED.hv_30d,
                        vrp_spread = EXCLUDED.vrp_spread,
                        iv_rank_1y = EXCLUDED.iv_rank_1y,
                        iv_percentile_1y = EXCLUDED.iv_percentile_1y,
                        skew_25d = EXCLUDED.skew_25d,
                        recommended_structure = EXCLUDED.recommended_structure,
                        updated_at = CURRENT_TIMESTAMP;
                    """,
                    (
                        ticker,
                        name,
                        today,
                        spot,
                        chg_pct,
                        iv30,
                        hv30,
                        vrp,
                        iv_pct,
                        iv_pct,
                        skew,
                        rec,
                    ),
                )
        conn.commit()
        print(f"[覆写] {ticker} IV30={iv30} IVP={iv_pct} skew={skew} → {rec}")
    finally:
        conn.close()


# =============================================================================
# 8. 静态数据包导出（复用 mobo-cli 单一写者 + 脱敏审计）
# =============================================================================
def export_static_packages(settings: Settings) -> dict[str, str]:
    """重导出莫伯资本公域包与终端快照。

    刻意复用 ``site_sync.export_capital_site``：
    ``terminal-snapshot.json`` 只有**一个**写者，脱敏审计（``audit_payload``）才会始终生效。
    """
    from mobo_cli import site_sync

    written = site_sync.export_capital_site(settings, include_internal=False)
    for key, path in written.items():
        print(f"[导出] {key}: {path}")
    return {k: str(v) for k, v in written.items()}


def run_health_check(settings: Settings) -> int:
    """体检：连接、权限、目标表可读、静态目录可写。"""
    ok = True
    print(f"DB   : {settings.db_host}:{settings.db_port}/{settings.mobobrain_db}")
    print(f"用户 : {settings.mobobrain_user}")
    print(f"前台 : {settings.capital_web_dir}")

    try:
        conn = db_connection(settings)
    except Exception as exc:  # noqa: BLE001
        print(f"[FAIL] 连接 db_mobobrain 失败：{exc}")
        return 1

    try:
        with conn.cursor() as cur:
            cur.execute("SELECT current_database(), current_user;")
            db, user = cur.fetchone()
            print(f"[OK]   连接成功：{db} / {user}")
            for table in ("capital.macro_indicator_series", "capital.options_vol_surface_daily"):
                cur.execute(f"SELECT count(*) FROM {table};")
                print(f"[OK]   {table}: {cur.fetchone()[0]} 行")
            cur.execute("SELECT count(*) FROM capital.v_latest_macro_indicators;")
            print(f"[OK]   capital.v_latest_macro_indicators: {cur.fetchone()[0]} 行")
            cur.execute("SELECT count(*) FROM capital.v_latest_options_vol_surface;")
            print(f"[OK]   capital.v_latest_options_vol_surface: {cur.fetchone()[0]} 行")
    except Exception as exc:  # noqa: BLE001
        print(f"[FAIL] 查询失败：{exc}")
        ok = False
    finally:
        conn.close()

    web_dir = Path(settings.capital_web_dir)
    if web_dir.is_dir():
        print(f"[OK]   前台目录存在：{web_dir}")
    else:
        print(f"[FAIL] 前台目录不存在：{web_dir}")
        ok = False

    return 0 if ok else 1


# =============================================================================
# 9. CLI
# =============================================================================
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="macro_iv_collector",
        description="MoBoCapital 量化终端采集器（宏观 Z-Score + 期权波动率分位）",
    )
    parser.add_argument(
        "--env-file",
        help="环境文件路径；默认按 .env.local → .env 自动探测（项目根）",
    )
    parser.add_argument("--web-dir", help=f"前台目录覆盖（默认 {PROJECT_ROOT / 'sites/mobocapital'}）")
    parser.add_argument(
        "--only",
        help="只处理指定标的（indicator_code 或 underlying_ticker）",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="只做连通性与权限体检，不写库、不导出",
    )
    parser.add_argument(
        "--export-only",
        action="store_true",
        help="只重导出静态数据包，不采集",
    )
    parser.add_argument(
        "--set-macro",
        nargs=5,
        metavar=("CODE", "NAME", "REGION", "VAL", "PREV"),
        help="手动注入宏观指标，例如 --set-macro VIX 'CBOE VIX 恐慌指数' US 19.45 20.28",
    )
    parser.add_argument(
        "--set-vol",
        nargs=7,
        metavar=("TICKER", "NAME", "SPOT", "IV30", "HV30", "IV_PCT", "SKEW25D"),
        help="手动注入期权波动率曲面，例如 --set-vol 510300.SH '沪深300ETF期权' 3.98 19.8 21.6 28.4 4.6",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    settings, env_file = resolve_settings(args.env_file, args.web_dir)

    if env_file:
        print(f"[环境] {env_file}")
    else:
        print("[环境] 未找到 .env.local / .env，将直接使用当前进程环境变量")

    if args.check:
        return run_health_check(settings)

    if args.set_macro:
        code, name, region, val, prev = args.set_macro
        manual_override_macro(
            settings,
            code=code,
            name=name,
            region=region,
            val=float(val),
            prev=float(prev),
        )
        export_static_packages(settings)
        return 0

    if args.set_vol:
        ticker, name, spot, iv30, hv30, iv_pct, skew = args.set_vol
        manual_override_vol(
            settings,
            ticker=ticker,
            name=name,
            spot=float(spot),
            iv30=float(iv30),
            hv30=float(hv30),
            iv_pct=float(iv_pct),
            skew=float(skew),
        )
        export_static_packages(settings)
        return 0

    if not args.export_only:
        stats = run_daily_collection(settings, only=args.only)
        print(
            f"[采集] 完成：写入 {stats['written']} 条，"
            f"跳过 {stats['skipped']} 条，失败 {stats['failed']} 条"
        )

    export_static_packages(settings)
    print(f"[完成] {datetime.now().isoformat(timespec='seconds')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
