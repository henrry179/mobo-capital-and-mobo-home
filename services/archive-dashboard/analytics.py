"""网站 B 看板的计算函数与 52 周合成沙盒数据。

保持纯函数，便于 pytest；不依赖 Streamlit。
"""
from __future__ import annotations

import math
from datetime import datetime, timedelta

import numpy as np
import pandas as pd

WEEKLY_METRICS: dict[str, str] = {
    "reading_hours": "阅读时长（小时）",
    "pages_read": "阅读页数",
    "workouts": "训练次数",
    "workout_hours": "训练时长（小时）",
    "running_km": "跑量（km）",
    "strength_tonnage": "力量容量（吨）",
    "avg_sleep_hours": "平均睡眠（小时）",
    "avg_resting_hr": "静息心率",
    "avg_weight_kg": "平均体重（kg）",
    "retro_completed": "复盘次数",
    "avg_execution_score": "平均执行分",
}

DOMAINS = [
    "CAREER_WORK",
    "INVEST_TRADING",
    "LEARNING_EXAM",
    "FITNESS_HEALTH",
    "FAMILY_LIFE",
    "SYSTEM_TECH",
]

DOMAIN_LABELS = {
    "CAREER_WORK": "职业/工作",
    "INVEST_TRADING": "投资/交易",
    "LEARNING_EXAM": "学习/考试",
    "FITNESS_HEALTH": "运动/健康",
    "FAMILY_LIFE": "家庭/生活",
    "SYSTEM_TECH": "系统/技术",
}

EVENT_LABELS = {
    "BOOK_FINISHED": "读完书籍",
    "WORKOUT_RUNNING": "跑步",
    "WORKOUT_STRENGTH": "力量训练",
    "WORKOUT_CYCLING": "骑行",
    "RETRO_WEEKLY": "周复盘",
    "RETRO_PROJECT_POSTMORTEM": "项目复盘",
    "RETRO_TRADING_PLAYBOOK": "交易复盘",
    "ASSET_UPLOAD": "资产入库",
}


def human_bytes(num: float | int | None) -> str:
    """把字节数格式化为可读字符串。"""
    if num is None or (isinstance(num, float) and math.isnan(num)):
        return "—"
    n = float(num)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(n) < 1024.0:
            return f"{n:,.1f} {unit}" if unit != "B" else f"{int(n)} {unit}"
        n /= 1024.0
    return f"{n:,.1f} PB"


def zscore(series: pd.Series) -> pd.Series:
    """标准化；0 方差返回全 0，避免 NaN 污染图表。"""
    s = pd.to_numeric(series, errors="coerce")
    mean = s.mean()
    std = s.std(ddof=0)
    if std is None or not np.isfinite(std) or std == 0:
        return pd.Series(np.zeros(len(s)), index=s.index, dtype=float)
    return (s - mean) / std


def lead_lag_corr(
    df: pd.DataFrame,
    x: str,
    y: str,
    max_lag: int = 4,
    min_n: int = 8,
) -> pd.DataFrame:
    """计算 X 与 Y 的滞后相关。

    lag > 0：X 领先 Y（X_t 与 Y_{t+lag}）
    lag < 0：Y 领先 X
    lag = 0：同期相关
    """
    if x not in df.columns or y not in df.columns:
        raise KeyError(f"缺少列：{x} / {y}")

    xv = pd.to_numeric(df[x], errors="coerce").to_numpy(dtype=float)
    yv = pd.to_numeric(df[y], errors="coerce").to_numpy(dtype=float)
    rows = []
    for lag in range(-max_lag, max_lag + 1):
        if lag > 0:
            a, b = xv[:-lag], yv[lag:]
        elif lag < 0:
            a, b = xv[-lag:], yv[:lag]
        else:
            a, b = xv, yv
        mask = np.isfinite(a) & np.isfinite(b)
        n = int(mask.sum())
        r = np.nan
        if n >= min_n:
            aa, bb = a[mask], b[mask]
            if np.std(aa) > 1e-12 and np.std(bb) > 1e-12:
                r = float(np.corrcoef(aa, bb)[0, 1])
        rows.append({"lag": lag, "r": r, "n": n})
    return pd.DataFrame(rows)


def sandbox_weekly(weeks: int = 52, seed: int = 42) -> pd.DataFrame:
    """生成 52 周合成数据；用于无数据库/演示。"""
    rng = np.random.default_rng(seed)
    end = pd.Timestamp.now(tz="Asia/Shanghai").normalize().tz_localize(None)
    start = end - pd.Timedelta(weeks=weeks - 1)
    dates = pd.date_range(start=start, periods=weeks, freq="W-MON")

    t = np.arange(weeks)
    seasonal = np.sin(2 * np.pi * t / 52.0)
    trend = t / max(weeks - 1, 1)

    reading = np.clip(4.0 + 2.0 * seasonal + 1.5 * trend + rng.normal(0, 1.2, weeks), 0, None)
    pages = np.clip(reading * rng.uniform(28, 42, weeks) + rng.normal(0, 20, weeks), 0, None)
    workouts = np.clip(np.round(3.5 + 1.2 * seasonal + rng.normal(0, 1.0, weeks)), 0, 7).astype(int)
    workout_hours = np.clip(workouts * rng.uniform(0.7, 1.2, weeks) + rng.normal(0, 0.3, weeks), 0, None)
    running_km = np.clip(workouts * rng.uniform(3.0, 7.0, weeks) + rng.normal(0, 3, weeks), 0, None)
    strength = np.clip(workouts * rng.uniform(2.0, 5.0, weeks) + rng.normal(0, 2, weeks), 0, None)
    sleep = np.clip(7.2 + 0.35 * seasonal + rng.normal(0, 0.35, weeks), 5.5, 9.0)
    resting_hr = np.clip(58 - 2.0 * seasonal + rng.normal(0, 2.0, weeks), 48, 75)
    weight = np.clip(70.0 - 1.2 * trend + 0.4 * seasonal + rng.normal(0, 0.3, weeks), 65, 78)
    retro = rng.integers(0, 3, weeks)
    execution = np.clip(6.0 + 1.0 * seasonal + rng.normal(0, 1.0, weeks), 1, 10)

    return pd.DataFrame(
        {
            "week_start": dates,
            "reading_hours": np.round(reading, 1),
            "pages_read": pages.round(0).astype(int),
            "workouts": workouts,
            "workout_hours": np.round(workout_hours, 1),
            "running_km": np.round(running_km, 1),
            "strength_tonnage": np.round(strength, 2),
            "avg_sleep_hours": np.round(sleep, 2),
            "avg_resting_hr": np.round(resting_hr, 1),
            "avg_weight_kg": np.round(weight, 2),
            "retro_completed": retro,
            "avg_execution_score": np.round(execution, 1),
        }
    )


def sandbox_timeline(events: int = 80, seed: int = 7) -> pd.DataFrame:
    """生成最近 120 天的合成时间线。"""
    rng = np.random.default_rng(seed)
    now = pd.Timestamp.now(tz="Asia/Shanghai").tz_localize(None)
    rows = []
    event_types = [
        ("BOOK_FINISHED", "LEARNING_EXAM", "读完《合成书》"),
        ("WORKOUT_RUNNING", "FITNESS_HEALTH", "跑步训练"),
        ("WORKOUT_STRENGTH", "FITNESS_HEALTH", "力量训练"),
        ("RETRO_WEEKLY", "SYSTEM_TECH", "周复盘"),
        ("RETRO_PROJECT_POSTMORTEM", "CAREER_WORK", "项目复盘"),
        ("RETRO_TRADING_PLAYBOOK", "INVEST_TRADING", "交易复盘"),
    ]
    for i in range(events):
        et, domain, title = event_types[int(rng.integers(0, len(event_types)))]
        occurred = now - timedelta(days=int(rng.integers(0, 120)), hours=int(rng.integers(6, 22)))
        duration = int(rng.integers(20, 150))
        importance = int(rng.integers(3, 10))
        rows.append(
            {
                "event_id": f"sandbox-{i:04d}",
                "title": f"{title} #{i + 1}",
                "domain": domain,
                "event_type": et,
                "occurred_at": occurred,
                "ended_at": occurred + timedelta(minutes=duration),
                "importance_score": importance,
                "energy_impact": int(rng.integers(-2, 4)),
                "duration_minutes": duration,
                "tags": ["sandbox"],
                "metrics_payload": {
                    "source": "sandbox",
                    "score": round(float(rng.uniform(1, 10)), 1),
                    "note": "合成数据",
                },
                "privacy": "PRIVATE",
            }
        )
    return pd.DataFrame(rows).sort_values("occurred_at").reset_index(drop=True)


def sandbox_assets(seed: int = 11) -> pd.DataFrame:
    """生成合成资产总账。"""
    rng = np.random.default_rng(seed)
    categories = ["PHOTO", "VIDEO", "SCAN_DOC", "CERTIFICATE", "MEDICAL", "OTHER"]
    tiers = ["OSS_STANDARD", "OSS_IA", "OSS_ARCHIVE"]
    rows = []
    for cat in categories:
        for tier in tiers:
            count = int(rng.integers(3, 60))
            avg_mb = {
                "PHOTO": 8,
                "VIDEO": 220,
                "SCAN_DOC": 3,
                "CERTIFICATE": 1,
                "MEDICAL": 2,
                "OTHER": 5,
            }[cat]
            total = int(count * avg_mb * 1024 * 1024 * rng.uniform(0.7, 1.3))
            rows.append(
                {
                    "current_tier": tier,
                    "asset_category": cat,
                    "asset_count": count,
                    "total_bytes": total,
                    "total_pretty": human_bytes(total),
                }
            )
    return pd.DataFrame(rows)


if __name__ == "__main__":
    # 本地快速自检：python analytics.py
    weekly = sandbox_weekly()
    assert len(weekly) == 52
    assert not weekly["reading_hours"].isna().any()
    corr = lead_lag_corr(weekly, "reading_hours", "avg_sleep_hours")
    assert len(corr) == 9
    print(weekly.head(3).to_string(index=False))
    print(corr.to_string(index=False))
