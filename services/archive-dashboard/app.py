"""网站 B · Wolfram 式计算型个人数字档案看板。

运行：
    streamlit run app.py

特性：
- 只读连接 db_archive；数据库不可用时自动切换 52 周合成沙盒。
- 四个模块：周度节律/Z-Score、Lead-Lag、时间线、资产总账。
"""
from __future__ import annotations

import json
import os
from datetime import datetime, timedelta, timezone

import pandas as pd
import plotly.express as px
import streamlit as st

from analytics import (
    DOMAIN_LABELS,
    EVENT_LABELS,
    WEEKLY_METRICS,
    human_bytes,
    lead_lag_corr,
    sandbox_assets,
    sandbox_timeline,
    sandbox_weekly,
    zscore,
)

try:
    import psycopg2
except ImportError:  # pragma: no cover
    psycopg2 = None  # type: ignore


st.set_page_config(
    page_title="莫伯数字档案 · Personal Analytics",
    page_icon="◈",
    layout="wide",
    initial_sidebar_state="expanded",
)

# -----------------------------------------------------------------------------
# 样式
# -----------------------------------------------------------------------------
st.markdown(
    """
<style>
  .block-container { padding-top: 1.4rem; padding-bottom: 3rem; }
  div[data-testid="stMetric"] {
      background: linear-gradient(180deg, rgba(255,255,255,.045), rgba(255,255,255,.015));
      border: 1px solid rgba(148,163,184,.22);
      border-radius: 14px;
      padding: 12px 14px;
  }
  div[data-testid="stMetricLabel"] { color: #93a0c2; }
  .mobo-note {
      border: 1px solid rgba(148,163,184,.22);
      background: rgba(20,27,50,.55);
      border-radius: 12px;
      padding: 12px 14px;
      color: #aab4cc;
      font-size: 13px;
      line-height: 1.65;
  }
  .mobo-badge {
      display: inline-block; font-size: 12px; border-radius: 999px;
      padding: 2px 9px; margin-right: 6px;
      border: 1px solid rgba(148,163,184,.3); color: #c7d2e8;
  }
  code { color: #cfe0ff; }
</style>
""",
    unsafe_allow_html=True,
)


# -----------------------------------------------------------------------------
# 数据访问
# -----------------------------------------------------------------------------
def db_connect():
    """返回 (connection, error)。只读、超时 20s。"""
    if psycopg2 is None:
        return None, "未安装 psycopg2"
    if not (os.getenv("PG_PASS_ARCHIVE") or os.getenv("ARCHIVE_DB_PASSWORD")):
        return None, "未配置 ARCHIVE_DB_PASSWORD"
    try:
        conn = psycopg2.connect(
            host=os.getenv("PG_HOST") or os.getenv("ARCHIVE_DB_HOST", "postgres"),
            port=int(os.getenv("PG_PORT") or os.getenv("ARCHIVE_DB_PORT", "5432")),
            dbname=os.getenv("PG_DB_ARCHIVE") or os.getenv("ARCHIVE_DB_NAME", "db_archive"),
            user=os.getenv("PG_USER_ARCHIVE") or os.getenv("ARCHIVE_DB_USER", "user_dashboard_ro"),
            password=os.getenv("PG_PASS_ARCHIVE") or os.getenv("ARCHIVE_DB_PASSWORD"),
            connect_timeout=3,
            options="-c statement_timeout=20000",
        )
        conn.set_session(readonly=True, autocommit=True)
        return conn, None
    except Exception as exc:  # noqa: BLE001
        return None, str(exc)


@st.cache_data(ttl=300, show_spinner=False)
def load_weekly() -> tuple[pd.DataFrame, str, str | None]:
    conn, err = db_connect()
    if conn is None:
        return sandbox_weekly(), "sandbox", err
    try:
        df = pd.read_sql_query(
            "SELECT * FROM archive.v_weekly_life_analytics ORDER BY week_start",
            conn,
        )
        if df.empty:
            return sandbox_weekly(), "sandbox-empty", "真实库暂无周度数据"
        df["week_start"] = pd.to_datetime(df["week_start"])
        return df, "database", None
    except Exception as exc:  # noqa: BLE001
        return sandbox_weekly(), "sandbox-error", str(exc)
    finally:
        conn.close()


@st.cache_data(ttl=120, show_spinner=False)
def load_timeline(days: int) -> tuple[pd.DataFrame, str, str | None]:
    conn, err = db_connect()
    if conn is None:
        return sandbox_timeline(), "sandbox", err
    try:
        since = datetime.now(timezone.utc) - timedelta(days=days)
        df = pd.read_sql_query(
            """
            SELECT event_id, title, domain, event_type, occurred_at, ended_at,
                   importance_score, energy_impact, duration_minutes,
                   tags, metrics_payload, privacy
            FROM archive.timeline_events
            WHERE occurred_at >= %(since)s
            ORDER BY occurred_at
            """,
            conn,
            params={"since": since},
        )
        if df.empty:
            return sandbox_timeline(), "sandbox-empty", "真实库暂无时间线数据"
        df["occurred_at"] = pd.to_datetime(df["occurred_at"])
        if "ended_at" in df:
            df["ended_at"] = pd.to_datetime(df["ended_at"], errors="coerce")
        return df, "database", None
    except Exception as exc:  # noqa: BLE001
        return sandbox_timeline(), "sandbox-error", str(exc)
    finally:
        conn.close()


@st.cache_data(ttl=300, show_spinner=False)
def load_assets() -> tuple[pd.DataFrame, str, str | None]:
    conn, err = db_connect()
    if conn is None:
        return sandbox_assets(), "sandbox", err
    try:
        df = pd.read_sql_query(
            """
            SELECT current_tier, asset_category,
                   COUNT(*) AS asset_count,
                   COALESCE(SUM(file_size_bytes), 0) AS total_bytes
            FROM archive.archive_assets
            WHERE deleted_at IS NULL
            GROUP BY current_tier, asset_category
            ORDER BY current_tier, total_bytes DESC
            """,
            conn,
        )
        if df.empty:
            return sandbox_assets(), "sandbox-empty", "真实库暂无资产数据"
        df["total_pretty"] = df["total_bytes"].map(human_bytes)
        return df, "database", None
    except Exception as exc:  # noqa: BLE001
        return sandbox_assets(), "sandbox-error", str(exc)
    finally:
        conn.close()


@st.cache_data(ttl=300, show_spinner=False)
def load_recent_assets(limit: int = 30) -> pd.DataFrame:
    conn, err = db_connect()
    if conn is None:
        return pd.DataFrame()
    try:
        return pd.read_sql_query(
            """
            SELECT title, asset_category, current_tier, file_size_bytes,
                   captured_at, document_date, privacy, oss_object_key
            FROM archive.archive_assets
            WHERE deleted_at IS NULL
            ORDER BY created_at DESC
            LIMIT %(limit)s
            """,
            conn,
            params={"limit": limit},
        )
    except Exception:  # noqa: BLE001
        return pd.DataFrame()
    finally:
        conn.close()


def source_badge(source: str) -> str:
    mapping = {
        "database": "真实数据库",
        "sandbox": "52 周合成沙盒",
        "sandbox-empty": "沙盒（真实库为空）",
        "sandbox-error": "沙盒（数据库异常）",
    }
    return mapping.get(source, source)


# -----------------------------------------------------------------------------
# 侧边栏
# -----------------------------------------------------------------------------
with st.sidebar:
    st.title("◈ 莫伯数字档案")
    st.caption("Wolfram 式计算型个人数字档案")
    st.divider()

    days = st.select_slider(
        "时间窗口",
        options=[30, 60, 90, 180, 365],
        value=90,
        format_func=lambda x: f"最近 {x} 天",
    )
    top_metrics = st.multiselect(
        "周度节律指标",
        options=list(WEEKLY_METRICS.keys()),
        default=["reading_hours", "workouts", "avg_sleep_hours"],
        format_func=lambda x: WEEKLY_METRICS[x],
    )
    st.divider()
    if st.button("刷新数据", use_container_width=True):
        st.cache_data.clear()
        st.rerun()
    st.caption("只读账号：`user_dashboard_ro`；数据库不可用时自动切换沙盒。")

weekly, weekly_source, weekly_err = load_weekly()
timeline, timeline_source, timeline_err = load_timeline(days)
assets, assets_source, assets_err = load_assets()

# 统一列名/类型
weekly["week_start"] = pd.to_datetime(weekly["week_start"])
weekly = weekly.sort_values("week_start").reset_index(drop=True)
latest = weekly.iloc[-1] if len(weekly) else None

# -----------------------------------------------------------------------------
# 顶部
# -----------------------------------------------------------------------------
st.markdown("## Personal Analytics")
st.caption("把阅读、运动、睡眠、复盘与数字资产放回同一条时间轴。")

badge = source_badge(weekly_source)
if weekly_source == "database":
    st.success(f"数据源：{badge}")
elif weekly_err:
    st.warning(f"数据源：{badge} · {weekly_err}")
else:
    st.info(f"数据源：{badge}")

if latest is not None:
    c1, c2, c3, c4, c5 = st.columns(5)
    c1.metric("最近一周阅读", f"{float(latest.get('reading_hours', 0) or 0):.1f} h")
    c2.metric("最近一周训练", f"{int(latest.get('workouts', 0) or 0)} 次")
    c3.metric("平均睡眠", f"{float(latest.get('avg_sleep_hours', 0) or 0):.1f} h")
    c4.metric("复盘", f"{int(latest.get('retro_completed', 0) or 0)} 次")
    total_bytes = float(assets["total_bytes"].sum()) if len(assets) else 0.0
    c5.metric("资产总量", human_bytes(total_bytes))

st.divider()

tab1, tab2, tab3, tab4 = st.tabs(
    ["周度节律 · Z-Score", "Lead-Lag 回归", "时间线", "资产总账"]
)

# -----------------------------------------------------------------------------
# Tab 1：周度节律
# -----------------------------------------------------------------------------
with tab1:
    st.subheader("跨指标周度节律")
    st.caption("Z-Score 让阅读、训练、睡眠等不同量纲的指标可以在同一张图上比较。0 表示该指标的历史均值。")

    if not top_metrics:
        st.info("请在左侧至少选择一个指标。")
    else:
        zdf = weekly[["week_start"] + top_metrics].copy()
        for m in top_metrics:
            zdf[f"{m}__z"] = zscore(zdf[m])
        zlong = zdf.melt(
            id_vars="week_start",
            value_vars=[f"{m}__z" for m in top_metrics],
            var_name="metric",
            value_name="z",
        )
        zlong["metric"] = zlong["metric"].str.replace("__z", "", regex=False).map(WEEKLY_METRICS)
        fig = px.line(
            zlong,
            x="week_start",
            y="z",
            color="metric",
            markers=True,
            template="plotly_dark",
            labels={"week_start": "周起始", "z": "Z-Score", "metric": "指标"},
        )
        fig.add_hline(y=0, line_dash="dot", line_color="rgba(148,163,184,.5)")
        fig.update_layout(height=420, legend_title_text="", margin=dict(l=10, r=10, t=20, b=10))
        st.plotly_chart(fig, use_container_width=True)

        st.markdown("#### 原始周度数据")
        show = weekly[["week_start"] + top_metrics].copy()
        show.columns = ["周起始"] + [WEEKLY_METRICS[m] for m in top_metrics]
        st.dataframe(show.sort_values("周起始", ascending=False), use_container_width=True, hide_index=True)

        with st.expander("指标说明"):
            st.markdown(
                """
- **阅读时长/页数**：来自 `reading_logs` 的 SESSION 汇总。
- **训练次数/时长/跑量/力量容量**：来自 `fitness_workouts`。
- **睡眠/静息心率/体重**：来自 `fitness_biometrics` 的周均值。
- **复盘/执行分**：来自 `project_retrospectives`。
- 沙盒模式使用固定随机种子生成 52 周数据，仅用于演示与开发，不代表真实记录。
                """
            )

# -----------------------------------------------------------------------------
# Tab 2：Lead-Lag
# -----------------------------------------------------------------------------
with tab2:
    st.subheader("Lead-Lag：谁领先谁？")
    st.caption("滞后相关只描述时间上的领先/同步关系，不等于因果。样本少于 8 周的滞后不计算。")

    c1, c2, c3 = st.columns([1.2, 1.2, 0.8])
    x_metric = c1.selectbox(
        "X 指标",
        options=list(WEEKLY_METRICS.keys()),
        index=list(WEEKLY_METRICS).index("reading_hours"),
        format_func=lambda x: WEEKLY_METRICS[x],
        key="ll_x",
    )
    y_metric = c2.selectbox(
        "Y 指标",
        options=list(WEEKLY_METRICS.keys()),
        index=list(WEEKLY_METRICS).index("avg_sleep_hours"),
        format_func=lambda x: WEEKLY_METRICS[x],
        key="ll_y",
    )
    max_lag = c3.slider("最大滞后（周）", 1, 8, 4)

    corr = lead_lag_corr(weekly, x_metric, y_metric, max_lag=max_lag)
    fig = px.bar(
        corr,
        x="lag",
        y="r",
        template="plotly_dark",
        labels={"lag": "滞后（周）", "r": "Pearson r"},
        color="r",
        color_continuous_scale=["#ef4444", "#1f2937", "#4ade80"],
        range_color=[-1, 1],
    )
    fig.add_hline(y=0, line_dash="dot", line_color="rgba(148,163,184,.5)")
    fig.update_layout(height=360, coloraxis_showscale=False, margin=dict(l=10, r=10, t=20, b=10))
    st.plotly_chart(fig, use_container_width=True)

    valid = corr.dropna(subset=["r"])
    if len(valid):
        best = valid.loc[valid["r"].abs().idxmax()]
        lag = int(best["lag"])
        r = float(best["r"])
        if lag > 0:
            direction = f"**{WEEKLY_METRICS[x_metric]}** 领先 **{WEEKLY_METRICS[y_metric]}** 约 {lag} 周"
        elif lag < 0:
            direction = f"**{WEEKLY_METRICS[y_metric]}** 领先 **{WEEKLY_METRICS[x_metric]}** 约 {abs(lag)} 周"
        else:
            direction = f"**{WEEKLY_METRICS[x_metric]}** 与 **{WEEKLY_METRICS[y_metric]}** 同期相关"
        st.markdown(f"最强信号：{direction}，r = **{r:.3f}**（n = {int(best['n'])}）。")
        if abs(r) < 0.3:
            st.info("|r| < 0.3，关系较弱；不建议据此做单因果解释。")
        elif abs(r) < 0.5:
            st.warning("|r| 在 0.3–0.5，存在一定关联，但可能受趋势/季节/样本量影响。")
        else:
            st.success("|r| ≥ 0.5，值得进一步做控制变量与分阶段验证。")
    else:
        st.info("样本不足，无法计算有效滞后相关。")

    st.dataframe(
        corr.assign(
            lag=lambda d: d["lag"].map(lambda v: f"{v:+d}"),
            r=lambda d: d["r"].map(lambda v: "—" if pd.isna(v) else f"{v:.3f}"),
        ),
        use_container_width=True,
        hide_index=True,
    )

# -----------------------------------------------------------------------------
# Tab 3：时间线
# -----------------------------------------------------------------------------
with tab3:
    st.subheader("统一时间线")
    st.caption("每个业务模块通过 source_table/source_id 幂等同步到这里；点选事件可查看 metrics_payload。")

    domains = sorted(timeline["domain"].dropna().unique().tolist()) if len(timeline) else []
    selected_domains = st.multiselect(
        "领域筛选",
        options=domains,
        default=domains,
        format_func=lambda d: DOMAIN_LABELS.get(d, d),
    )
    view = timeline[timeline["domain"].isin(selected_domains)].copy() if selected_domains else timeline.copy()

    if view.empty:
        st.info("当前筛选下没有事件。")
    else:
        view["domain_label"] = view["domain"].map(lambda d: DOMAIN_LABELS.get(d, d))
        view["event_label"] = view["event_type"].map(lambda e: EVENT_LABELS.get(e, e))
        view["size"] = view["importance_score"].fillna(5).clip(1, 10)
        view["hover"] = view.apply(
            lambda r: f"{r['title']}<br>{r['event_label']} · {r['domain_label']}<br>"
            f"{r['occurred_at']:%Y-%m-%d %H:%M}<br>重要性 {r['size']}",
            axis=1,
        )
        fig = px.scatter(
            view,
            x="occurred_at",
            y="domain_label",
            size="size",
            color="event_label",
            hover_name="title",
            hover_data={"occurred_at": "|%Y-%m-%d %H:%M", "size": True, "hover": False},
            template="plotly_dark",
            labels={"occurred_at": "时间", "domain_label": "领域", "event_label": "事件类型"},
        )
        fig.update_layout(height=440, legend_title_text="", margin=dict(l=10, r=10, t=20, b=10))
        st.plotly_chart(fig, use_container_width=True)

        st.markdown("#### 事件列表")
        show_cols = ["occurred_at", "title", "domain_label", "event_label", "importance_score", "energy_impact", "duration_minutes", "privacy"]
        st.dataframe(
            view[show_cols].rename(
                columns={
                    "occurred_at": "时间",
                    "title": "标题",
                    "domain_label": "领域",
                    "event_label": "类型",
                    "importance_score": "重要性",
                    "energy_impact": "能量",
                    "duration_minutes": "时长(min)",
                    "privacy": "隐私",
                }
            ).sort_values("时间", ascending=False),
            use_container_width=True,
            hide_index=True,
        )

        st.markdown("#### 事件详情 / JSONB 穿透")
        options = view["event_id"].tolist()
        selected_id = st.selectbox(
            "选择事件",
            options=options,
            format_func=lambda eid: view.loc[view["event_id"] == eid, "title"].iloc[0],
        )
        row = view.loc[view["event_id"] == selected_id].iloc[0]
        c1, c2, c3 = st.columns(3)
        c1.write(f"**类型**：{row['event_label']}")
        c2.write(f"**领域**：{row['domain_label']}")
        c3.write(f"**时间**：{row['occurred_at']:%Y-%m-%d %H:%M}")
        payload = row.get("metrics_payload")
        if isinstance(payload, str):
            try:
                payload = json.loads(payload)
            except json.JSONDecodeError:
                pass
        st.json(payload if isinstance(payload, (dict, list)) else {"value": payload})

# -----------------------------------------------------------------------------
# Tab 4：资产总账
# -----------------------------------------------------------------------------
with tab4:
    st.subheader("数字资产总账")
    st.caption("原片/视频在 OSS 冷热分层；数据库只存元数据。缩略图保持标准层以保证看板加载。")

    if assets.empty:
        st.info("暂无资产数据。")
    else:
        total_bytes = float(assets["total_bytes"].sum())
        total_count = int(assets["asset_count"].sum())
        c1, c2, c3 = st.columns(3)
        c1.metric("资产总量", human_bytes(total_bytes))
        c2.metric("资产数量", f"{total_count:,}")
        c3.metric("平均大小", human_bytes(total_bytes / total_count if total_count else 0))

        chart_df = assets.copy()
        chart_df["total_gb"] = chart_df["total_bytes"] / (1024**3)
        fig = px.bar(
            chart_df,
            x="asset_category",
            y="total_gb",
            color="current_tier",
            barmode="stack",
            template="plotly_dark",
            labels={"asset_category": "类别", "total_gb": "容量（GB）", "current_tier": "存储层级"},
        )
        fig.update_layout(height=400, legend_title_text="", margin=dict(l=10, r=10, t=20, b=10))
        st.plotly_chart(fig, use_container_width=True)

        show = assets.copy()
        show["total_pretty"] = show["total_bytes"].map(human_bytes)
        st.dataframe(
            show[["current_tier", "asset_category", "asset_count", "total_pretty"]].rename(
                columns={
                    "current_tier": "存储层级",
                    "asset_category": "类别",
                    "asset_count": "数量",
                    "total_pretty": "容量",
                }
            ),
            use_container_width=True,
            hide_index=True,
        )

        recent = load_recent_assets()
        if not recent.empty:
            st.markdown("#### 最近入库")
            recent = recent.copy()
            recent["file_size"] = recent["file_size_bytes"].map(human_bytes)
            st.dataframe(
                recent[["title", "asset_category", "current_tier", "file_size", "captured_at", "privacy"]].rename(
                    columns={
                        "title": "标题",
                        "asset_category": "类别",
                        "current_tier": "层级",
                        "file_size": "大小",
                        "captured_at": "拍摄/创建",
                        "privacy": "隐私",
                    }
                ),
                use_container_width=True,
                hide_index=True,
            )

    st.markdown(
        '<div class="mobo-note">'
        "资产总账来自 <code>archive.v_asset_storage_summary</code> / <code>archive_assets</code>。"
        "下载原片请使用 CLI 生成的 OSS 签名 URL，不要把私有 Bucket 设为公共读。"
        "</div>",
        unsafe_allow_html=True,
    )

st.divider()
st.caption(
    f"数据源：周度={source_badge(weekly_source)}；时间线={source_badge(timeline_source)}；资产={source_badge(assets_source)}。"
    " 本看板只读，不提供写入入口。"
)
