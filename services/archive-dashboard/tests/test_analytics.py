from __future__ import annotations

import numpy as np
import pandas as pd

from analytics import human_bytes, lead_lag_corr, sandbox_assets, sandbox_timeline, sandbox_weekly, zscore


def test_zscore_mean_zero_and_unit_std() -> None:
    s = pd.Series([1.0, 2.0, 3.0, 4.0])
    z = zscore(s)
    assert abs(float(z.mean())) < 1e-12
    assert abs(float(z.std(ddof=0)) - 1.0) < 1e-12


def test_zscore_zero_variance() -> None:
    z = zscore(pd.Series([5.0, 5.0, 5.0]))
    assert (z == 0).all()


def test_lead_lag_positive() -> None:
    x = pd.Series(np.arange(30, dtype=float))
    y = x.shift(2)  # y_t = x_{t-2} => X 领先 Y 2 周
    df = pd.DataFrame({"x": x, "y": y})
    corr = lead_lag_corr(df, "x", "y", max_lag=4)
    row = corr.loc[corr["lag"] == 2].iloc[0]
    assert abs(float(row["r"]) - 1.0) < 1e-12
    assert int(row["n"]) == 28


def test_lead_lag_negative() -> None:
    y = pd.Series(np.arange(30, dtype=float))
    x = y.shift(1)  # x_t = y_{t-1} => Y 领先 X 1 周
    df = pd.DataFrame({"x": x, "y": y})
    corr = lead_lag_corr(df, "x", "y", max_lag=3)
    row = corr.loc[corr["lag"] == -1].iloc[0]
    assert abs(float(row["r"]) - 1.0) < 1e-12


def test_sandbox_weekly_shape_and_columns() -> None:
    df = sandbox_weekly(weeks=52)
    assert len(df) == 52
    assert {"week_start", "reading_hours", "workouts", "avg_sleep_hours"}.issubset(df.columns)
    assert df["reading_hours"].notna().all()
    assert (df["reading_hours"] >= 0).all()


def test_sandbox_timeline_and_assets() -> None:
    timeline = sandbox_timeline(events=20)
    assert len(timeline) == 20
    assert {"event_id", "domain", "metrics_payload"}.issubset(timeline.columns)
    assets = sandbox_assets()
    assert {"current_tier", "asset_category", "total_bytes"}.issubset(assets.columns)
    assert (assets["total_bytes"] >= 0).all()


def test_human_bytes() -> None:
    assert human_bytes(0) == "0 B"
    assert human_bytes(1024) == "1.0 KB"
    assert human_bytes(1024**3) == "1.0 GB"
    assert human_bytes(None) == "—"
