"""量化终端采集器（macro_iv_collector）纯函数与配置解析单测。

只测不碰网络/数据库的部分：Z-Score、状态映射、IV 分位、策略路由、
环境文件探测与变量口径。
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

# 采集器位于 mobo_cli 包之外（便于 cron 直接以脚本方式执行）
_PKG_ROOT = Path(__file__).resolve().parents[1]
if str(_PKG_ROOT) not in sys.path:
    sys.path.insert(0, str(_PKG_ROOT))

from collectors.macro_iv_collector import (  # noqa: E402
    MACRO_TARGETS,
    VOL_TARGETS,
    calc_iv_rank_and_percentile,
    calc_rolling_zscore,
    classify_macro_regime,
    recommend_option_structure,
    resolve_env_file,
    resolve_settings,
)


# ---------------------------------------------------------------------------
# 滚动 Z-Score
# ---------------------------------------------------------------------------
def test_rolling_zscore_centered() -> None:
    history = [10.0, 11.0, 12.0, 13.0, 14.0]
    z = calc_rolling_zscore(history, 15.0)
    assert z > 1.0
    assert z == round(z, 2)


def test_rolling_zscore_needs_minimum_samples() -> None:
    assert calc_rolling_zscore([], 5.0) == 0.0
    assert calc_rolling_zscore([1.0], 5.0) == 0.0


def test_rolling_zscore_zero_variance_is_safe() -> None:
    assert calc_rolling_zscore([7.0] * 10, 7.0) == 0.0


def test_rolling_zscore_negative_deviation() -> None:
    history = [10.0, 11.0, 12.0, 13.0, 14.0]
    assert calc_rolling_zscore(history, 9.0) < -1.0


# ---------------------------------------------------------------------------
# 宏观状态映射
# ---------------------------------------------------------------------------
@pytest.mark.parametrize(
    ("z", "expected"),
    [
        (1.20, "EXPANSION"),
        (0.50, "IMPROVING"),
        (0.00, "NEUTRAL"),
        (-0.50, "BOTTOMING"),
        (-1.20, "CONTRACTION"),
    ],
)
def test_classify_macro_regime(z: float, expected: str) -> None:
    assert classify_macro_regime(z) == expected


def test_regime_thresholds_are_inclusive_at_boundaries() -> None:
    assert classify_macro_regime(0.80) == "EXPANSION"
    assert classify_macro_regime(-0.80) == "CONTRACTION"


# ---------------------------------------------------------------------------
# IV Rank / Percentile
# ---------------------------------------------------------------------------
def test_iv_rank_and_percentile_at_maximum() -> None:
    hist = [10.0, 12.0, 14.0, 16.0, 18.0]
    rank, pct = calc_iv_rank_and_percentile(hist, 20.0)
    assert rank == 100.0
    assert pct == 100.0


def test_iv_rank_and_percentile_at_minimum() -> None:
    hist = [10.0, 12.0, 14.0, 16.0, 18.0]
    rank, pct = calc_iv_rank_and_percentile(hist, 8.0)
    assert rank == 0.0
    assert pct < 20.0


def test_iv_rank_and_percentile_insufficient_history_is_neutral() -> None:
    assert calc_iv_rank_and_percentile([10.0, 11.0], 12.0) == (50.0, 50.0)


def test_iv_rank_and_percentile_flat_series_is_neutral() -> None:
    rank, pct = calc_iv_rank_and_percentile([15.0] * 10, 15.0)
    assert rank == 50.0
    assert 0.0 <= pct <= 100.0


# ---------------------------------------------------------------------------
# 策略路由
# ---------------------------------------------------------------------------
def test_low_iv_prefers_vertical_spread_when_skew_flat() -> None:
    assert "垂直价差" in recommend_option_structure(20.0, -1.0)


def test_low_iv_with_positive_skew_prefers_long_vol() -> None:
    assert "Straddle" in recommend_option_structure(20.0, 2.0)


def test_high_iv_with_high_skew_prefers_ratio_spread() -> None:
    assert "Ratio Spread" in recommend_option_structure(75.0, 5.0)


def test_high_iv_with_flat_skew_prefers_short_vol() -> None:
    assert "Iron Condor" in recommend_option_structure(75.0, 1.0)


def test_mid_range_prefers_calendar() -> None:
    assert "Calendar" in recommend_option_structure(45.0, 0.5)


# ---------------------------------------------------------------------------
# 目标清单与库内既有序列对齐
# ---------------------------------------------------------------------------
def test_macro_targets_use_stable_indicator_codes() -> None:
    codes = {t["code"] for t in MACRO_TARGETS}
    # 这些 code 必须与 seeds/52-week-sandbox.sql 入库的序列一致，
    # 否则采集器会另起一套同名异义的序列。
    for expected in ("VIX", "US10Y_YIELD", "USD_CNH", "CN_PMI_NEW_ORDERS", "US_ISM_NEW_ORDERS"):
        assert expected in codes


def test_macro_targets_without_public_feed_are_marked() -> None:
    by_code = {t["code"]: t for t in MACRO_TARGETS}
    assert by_code["CN_PMI_NEW_ORDERS"]["yf_symbol"] is None
    assert by_code["VIX"]["yf_symbol"] == "^VIX"


def test_vol_targets_use_seeded_tickers() -> None:
    tickers = {t["ticker"] for t in VOL_TARGETS}
    assert tickers == {"510300.SH", "159915.SZ", "SPY", "GLD"}


def test_no_duplicate_codes_or_tickers() -> None:
    codes = [t["code"] for t in MACRO_TARGETS]
    tickers = [t["ticker"] for t in VOL_TARGETS]
    assert len(codes) == len(set(codes))
    assert len(tickers) == len(set(tickers))


# ---------------------------------------------------------------------------
# 环境文件与变量口径
# ---------------------------------------------------------------------------
def test_resolve_env_file_missing_explicit_returns_none() -> None:
    assert resolve_env_file("/definitely/not/here/.env") is None


def test_resolve_env_file_prefers_explicit(tmp_path: Path) -> None:
    env = tmp_path / "custom.env"
    env.write_text("PG_HOST=127.0.0.1\n", encoding="utf-8")
    assert resolve_env_file(str(env)) == env


def test_resolve_settings_uses_cli_pg_host_first(monkeypatch, tmp_path: Path) -> None:
    env = tmp_path / "custom.env"
    env.write_text(
        "CLI_PG_HOST=127.0.0.1\nPG_HOST=postgres\nPG_PORT=5432\n"
        "PG_DB_MOBOBRAIN=db_mobobrain\nPG_USER_MOBOBRAIN=user_mobobrain\n"
        "PG_PASS_MOBOBRAIN=secret\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("CLI_PG_HOST", "127.0.0.1")
    monkeypatch.setenv("PG_HOST", "postgres")
    settings, env_file = resolve_settings(str(env))
    assert env_file == env
    # CLI 在宿主机跑：必须用 CLI_PG_HOST，不能是容器内的 "postgres"
    assert settings.db_host == "127.0.0.1"
    assert settings.mobobrain_db == "db_mobobrain"
    assert settings.mobobrain_user == "user_mobobrain"


def test_resolve_settings_makes_web_dir_absolute(monkeypatch, tmp_path: Path) -> None:
    env = tmp_path / "custom.env"
    env.write_text("PG_PASS_MOBOBRAIN=secret\n", encoding="utf-8")
    monkeypatch.chdir(tmp_path)
    settings, _ = resolve_settings(str(env))
    assert Path(settings.capital_web_dir).is_absolute()
    assert Path(settings.capital_web_dir).name == "mobocapital"
