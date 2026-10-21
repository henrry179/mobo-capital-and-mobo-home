#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
路径: /opt/mobo-stack/dashboard/app.py
功能: 莫伯之家 (db_archive) 周度体能、阅读、睡眠与心情能量 Z-Score 标准化及 Lead-Lag 滞后回归实验室
内存约束: 严禁引入 scipy/sklearn，100% 采用纯 NumPy 向量运算，常驻内存小于 150MB
"""

import os
import numpy as np
import pandas as pd
import psycopg2
import streamlit as st

st.set_page_config(page_title="MoBo Life Analytics Lab", layout="wide")


@st.cache_data(ttl=300)
def load_weekly_df() -> pd.DataFrame:
    conn = psycopg2.connect(
        host=os.getenv("PG_HOST", "mobo-postgres"),
        port=int(os.getenv("PG_PORT", "5432")),
        dbname=os.getenv("PG_DB_ARCHIVE", "db_archive"),
        user=os.getenv("PG_USER_ARCHIVE", "user_archive"),
        password=os.getenv("PG_PASS_ARCHIVE"),
    )
    try:
        df = pd.read_sql("SELECT * FROM v_weekly_life_analytics ORDER BY week_start ASC;", conn)
        return df
    finally:
        conn.close()


def zscore_series(s: pd.Series) -> pd.Series:
    arr = s.fillna(0).to_numpy(dtype=np.float64)
    std = np.std(arr)
    if std < 1e-8:
        return pd.Series(np.zeros_like(arr), index=s.index)
    return pd.Series((arr - np.mean(arr)) / std, index=s.index)


st.title("📊 莫伯之家 · 生命体征 Z-Score 与 Lead-Lag 滞后回归实验室")

try:
    df = load_weekly_df()
    if df.empty:
        st.info("当前 v_weekly_life_analytics 暂无数据，请先通过 mobo_cli.py home-habit 录入训练或阅读记录。")
    else:
        metrics = ["running_km", "total_workout_mins", "reading_mins", "avg_mood_score", "avg_energy_score"]
        st.subheader("1. 多维自律与状态指标 Z-Score 标准化趋势叠加")
        z_df = pd.DataFrame({m: zscore_series(df[m]) for m in metrics if m in df.columns})
        z_df.index = df["iso_week"]
        st.line_chart(z_df)

        st.subheader("2. Lead-Lag 跨周滞后交叉相关检验 (验证本周运动对下周精力的领先传导)")
        col1, col2, col3 = st.columns(3)
        x_col = col1.selectbox("先行自变量 (X)", metrics, index=0)
        y_col = col2.selectbox("滞后因变量 (Y)", metrics, index=4)
        lag_k = col3.slider("滞后周数 (Lag Weeks)", 0, 4, 1)

        x_arr = df[x_col].fillna(0).to_numpy(dtype=np.float64)
        y_arr = df[y_col].fillna(0).to_numpy(dtype=np.float64)
        if lag_k > 0 and len(x_arr) > lag_k + 2:
            x_aligned, y_aligned = x_arr[:-lag_k], y_arr[lag_k:]
        else:
            x_aligned, y_aligned = x_arr, y_arr

        if len(x_aligned) >= 3 and np.std(x_aligned) > 1e-8 and np.std(y_aligned) > 1e-8:
            r_val = float(np.corrcoef(x_aligned, y_aligned)[0, 1])
            slope, intercept = np.polyfit(x_aligned, y_aligned, 1)
            st.metric(
                label=f"{x_col} 领先 {y_col} ({lag_k} 周) 皮尔逊相关系数 r",
                value=f"{r_val:.3f}",
                delta=f"线性回归斜率 β = {slope:.3f}",
            )
except Exception as e:
    st.warning(f"数据库连接提示: {e}")