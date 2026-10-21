"""莫伯资本（capital Schema）读写封装。

对应表（`db_mobobrain.capital`）：

- ``macro_theses``             宏观与产业投研思考
- ``strategy_playbooks``       交易策略标准手册
- ``trade_reviews``            实战交易复盘与归因（平仓触发 NAV 核算）
- ``fund_incubation_milestones`` 基金孵化里程碑
- ``fund_governance_docs``     基金治理与合规文档
- ``capital_publications``     “1+3”四端合成与发布主表
- ``media_channel_metrics``    自媒体渠道运营指标
- ``portfolio_nav_ledger``     组合净值台账（由触发器维护）

所有 SQL 一律带 ``capital.`` 限定，避免落到 ``public`` Schema。
"""
from __future__ import annotations

from typing import Any, Mapping, Sequence

from psycopg2.extras import RealDictCursor

CAPITAL_SCHEMA = "capital"


def _rows(cur) -> list[dict[str, Any]]:
    return [dict(r) for r in cur.fetchall()]


def upsert_thesis(
    conn,
    *,
    thesis_code: str,
    title: str,
    region: str = "GLOBAL",
    asset_class: str = "MULTI",
    time_horizon: str = "1_3_MONTHS",
    directional_bias: str = "NEUTRAL",
    conviction_score: int = 5,
    core_logic_md: str = "",
    invalidation_criteria: str = "",
    leading_indicators: Mapping[str, Any] | None = None,
    visibility: str = "PUBLIC",
) -> dict[str, Any]:
    """写入或更新一条宏观论点（按 thesis_code 幂等）。"""
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            """
            INSERT INTO capital.macro_theses (
                thesis_code, title, region, asset_class, time_horizon,
                directional_bias, conviction_score, leading_indicators,
                core_logic_md, invalidation_criteria, status, visibility
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s::jsonb, %s, %s, 'ACTIVE', %s)
            ON CONFLICT (thesis_code) DO UPDATE SET
                title = EXCLUDED.title,
                region = EXCLUDED.region,
                asset_class = EXCLUDED.asset_class,
                time_horizon = EXCLUDED.time_horizon,
                directional_bias = EXCLUDED.directional_bias,
                conviction_score = EXCLUDED.conviction_score,
                leading_indicators = EXCLUDED.leading_indicators,
                core_logic_md = EXCLUDED.core_logic_md,
                invalidation_criteria = EXCLUDED.invalidation_criteria,
                visibility = EXCLUDED.visibility,
                updated_at = NOW()
            RETURNING id, thesis_code, title, status, visibility, updated_at;
            """,
            (
                thesis_code, title, region, asset_class, time_horizon,
                directional_bias, conviction_score,
                _jsonb(leading_indicators), core_logic_md, invalidation_criteria, visibility,
            ),
        )
        row = cur.fetchone()
    conn.commit()
    return dict(row) if row else {}


def list_theses(conn, *, limit: int = 50, only_active: bool = True) -> list[dict[str, Any]]:
    sql = "SELECT id, thesis_code, title, region, asset_class, directional_bias, conviction_score, status, visibility FROM capital.macro_theses"
    if only_active:
        sql += " WHERE status IN ('ACTIVE', 'VALIDATED')"
    sql += " ORDER BY conviction_score DESC, created_at DESC LIMIT %s;"
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(sql, (limit,))
        return _rows(cur)


def upsert_playbook(
    conn,
    *,
    strategy_code: str,
    name: str,
    strategy_family: str = "LONG_SHORT_EQUITY",
    holding_period: str = "1-3 Months",
    entry_rules_md: str = "",
    exit_and_stop_rules_md: str = "",
    option_structure_guide: str | None = None,
    max_risk_per_trade_pct: float = 1.0,
    target_sharpe: float | None = None,
    target_win_rate_pct: float | None = None,
    target_rr_ratio: float | None = None,
    max_sector_exposure_pct: float | None = None,
    visibility: str = "LP_PROSPECT",
) -> dict[str, Any]:
    """写入或更新一条策略手册（按 strategy_code 幂等）。"""
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            """
            INSERT INTO capital.strategy_playbooks (
                strategy_code, name, strategy_family, holding_period,
                target_sharpe, target_win_rate_pct, target_rr_ratio,
                max_risk_per_trade_pct, max_sector_exposure_pct,
                entry_rules_md, option_structure_guide, exit_and_stop_rules_md, visibility
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (strategy_code) DO UPDATE SET
                name = EXCLUDED.name,
                strategy_family = EXCLUDED.strategy_family,
                holding_period = EXCLUDED.holding_period,
                target_sharpe = EXCLUDED.target_sharpe,
                target_win_rate_pct = EXCLUDED.target_win_rate_pct,
                target_rr_ratio = EXCLUDED.target_rr_ratio,
                max_risk_per_trade_pct = EXCLUDED.max_risk_per_trade_pct,
                max_sector_exposure_pct = EXCLUDED.max_sector_exposure_pct,
                entry_rules_md = EXCLUDED.entry_rules_md,
                option_structure_guide = EXCLUDED.option_structure_guide,
                exit_and_stop_rules_md = EXCLUDED.exit_and_stop_rules_md,
                visibility = EXCLUDED.visibility,
                updated_at = NOW()
            RETURNING id, strategy_code, name, strategy_family, visibility;
            """,
            (
                strategy_code, name, strategy_family, holding_period,
                target_sharpe, target_win_rate_pct, target_rr_ratio,
                max_risk_per_trade_pct, max_sector_exposure_pct,
                entry_rules_md, option_structure_guide, exit_and_stop_rules_md, visibility,
            ),
        )
        row = cur.fetchone()
    conn.commit()
    return dict(row) if row else {}


def record_trade(
    conn,
    *,
    trade_code: str,
    underlying_ticker: str,
    asset_name: str,
    direction: str = "LONG",
    instrument_structure: str = "",
    entry_date: str,
    initial_risk_pct: float,
    pre_trade_thesis_md: str = "",
    strategy_code: str | None = None,
    thesis_code: str | None = None,
    visibility: str = "PUBLIC",
) -> dict[str, Any]:
    """登记一笔开仓交易（trade_reviews）。"""
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            "SELECT id FROM capital.strategy_playbooks WHERE strategy_code = %s;",
            (strategy_code,) if strategy_code else (None,),
        )
        strategy_row = cur.fetchone() if strategy_code else None
        cur.execute(
            "SELECT id FROM capital.macro_theses WHERE thesis_code = %s;",
            (thesis_code,) if thesis_code else (None,),
        )
        thesis_row = cur.fetchone() if thesis_code else None

        cur.execute(
            """
            INSERT INTO capital.trade_reviews (
                trade_code, thesis_id, strategy_id, underlying_ticker, asset_name,
                direction, instrument_structure, entry_date, trade_status,
                initial_risk_pct, pre_trade_thesis_md, visibility
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'OPEN', %s, %s, %s)
            ON CONFLICT (trade_code) DO UPDATE SET
                underlying_ticker = EXCLUDED.underlying_ticker,
                asset_name = EXCLUDED.asset_name,
                pre_trade_thesis_md = EXCLUDED.pre_trade_thesis_md,
                visibility = EXCLUDED.visibility,
                updated_at = NOW()
            RETURNING id, trade_code, trade_status, visibility;
            """,
            (
                trade_code,
                thesis_row.get("id") if thesis_row else None,
                strategy_row.get("id") if strategy_row else None,
                underlying_ticker, asset_name, direction, instrument_structure,
                entry_date, initial_risk_pct, pre_trade_thesis_md, visibility,
            ),
        )
        row = cur.fetchone()
    conn.commit()
    return dict(row) if row else {}


def close_trade(
    conn,
    *,
    trade_code: str,
    exit_date: str,
    realized_r_multiple: float | None = None,
    realized_return_pct: float | None = None,
    portfolio_impact_bps: int | None = None,
    discipline_score: int | None = None,
    execution_review_md: str = "",
    lessons_learned_md: str = "",
) -> dict[str, Any]:
    """平仓一笔交易；NAV 与回撤熔断由数据库触发器自动核算。"""
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            """
            UPDATE capital.trade_reviews
            SET trade_status = 'CLOSED',
                exit_date = %s,
                realized_r_multiple = %s,
                realized_return_pct = %s,
                portfolio_impact_bps = %s,
                discipline_score = %s,
                execution_review_md = %s,
                lessons_learned_md = %s,
                updated_at = NOW()
            WHERE trade_code = %s
            RETURNING id, trade_code, trade_status, realized_r_multiple, portfolio_impact_bps;
            """,
            (
                exit_date, realized_r_multiple, realized_return_pct,
                portfolio_impact_bps, discipline_score,
                execution_review_md, lessons_learned_md, trade_code,
            ),
        )
        row = cur.fetchone()
    conn.commit()
    return dict(row) if row else {}


def nav_snapshot(conn) -> dict[str, Any]:
    """读取最新净值台账 + 风险状态（回撤熔断状态）。"""
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            """
            SELECT valuation_date, gross_nav, high_water_mark, net_nav,
                   current_drawdown_pct, cumulative_r_multiple,
                   risk_regime_status, risk_action_note
            FROM capital.portfolio_nav_ledger
            ORDER BY valuation_date DESC, created_at DESC
            LIMIT 1;
            """
        )
        row = cur.fetchone()
    return dict(row) if row else {}


def list_publications(conn, *, limit: int = 20, published_only: bool = True) -> list[dict[str, Any]]:
    sql = (
        "SELECT id, slug, category, title, summary, publish_status, "
        "published_at, cover_oss_url, tags, visibility "
        "FROM capital.capital_publications"
    )
    params: list[Any] = []
    if published_only:
        sql += " WHERE publish_status = 'PUBLISHED'"
    sql += " ORDER BY COALESCE(published_at, created_at) DESC LIMIT %s;"
    params.append(limit)
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(sql, params)
        return _rows(cur)


def strategy_performance(conn) -> list[dict[str, Any]]:
    """策略胜率 / 盈亏比 / 纪律得分聚合（来自 v_strategy_performance_summary）。"""
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            """
            SELECT strategy_code, strategy_name, strategy_family,
                   closed_trades_count, actual_win_rate_pct,
                   avg_win_r, avg_loss_r, cumulative_r_multiple, avg_discipline_score
            FROM capital.v_strategy_performance_summary
            ORDER BY strategy_code;
            """
        )
        return _rows(cur)


def _jsonb(value: Mapping[str, Any] | None) -> str:
    import json

    return json.dumps(value or {}, ensure_ascii=False)
