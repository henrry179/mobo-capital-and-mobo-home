"""静态站点数据包同步：数据库 → 公私域 JSON → sites/ 目录。

与红线一（静态前台、服务端 0 额外内存）和红线四（公私域物理脱敏）配套：
CLI 负责"写盘前脱敏"，Caddy 只做只读分发。

产物：

- ``sites/mobocapital/data/public-data.json``          公域（PUBLIC + LP_PROSPECT）
- ``sites/mobocapital/data/terminal-snapshot.json``     宏观 Z-Score 与期权波动率曲面
- ``sites/mobocapital/internal/internal-data.json``      内网全量包（BasicAuth 保护）
- ``sites/mobohome/data/public-home-data.json``         公域个人档案
- ``sites/mobohome/internal/internal-home-data.json``   内网全量包（BasicAuth 保护）
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

from . import capital, exporters

# 莫伯之家公域允许的隐私级别（VAULT / PRIVATE 不进公域）
HOME_PUBLIC_PRIVACY = ("PUBLIC", "RESTRICTED")


def _rows(cur) -> list[dict[str, Any]]:
    return [dict(r) for r in cur.fetchall()]


def _fetch_capital(conn) -> dict[str, list[dict[str, Any]]]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT id, thesis_code, title, region, asset_class, time_horizon,
                   directional_bias, conviction_score, leading_indicators,
                   core_logic_md, invalidation_criteria, status, visibility,
                   created_at, updated_at
            FROM capital.macro_theses
            ORDER BY created_at DESC;
            """
        )
        theses = _rows(cur)

        cur.execute(
            """
            SELECT id, strategy_code, name, strategy_family, holding_period,
                   target_sharpe, target_win_rate_pct, target_rr_ratio,
                   max_risk_per_trade_pct, max_sector_exposure_pct,
                   entry_rules_md, option_structure_guide, exit_and_stop_rules_md,
                   is_active, visibility
            FROM capital.strategy_playbooks
            ORDER BY strategy_code;
            """
        )
        playbooks = _rows(cur)

        cur.execute(
            """
            SELECT id, trade_code, underlying_ticker, asset_name, direction,
                   instrument_structure, entry_date, exit_date, trade_status,
                   initial_risk_pct, realized_r_multiple, realized_return_pct,
                   portfolio_impact_bps, discipline_score, emotional_state_tag,
                   pre_trade_thesis_md, execution_review_md, lessons_learned_md,
                   public_chart_oss_url, private_blotter_oss_key, visibility
            FROM capital.trade_reviews
            ORDER BY entry_date DESC;
            """
        )
        trades = _rows(cur)

        cur.execute(
            """
            SELECT id, slug, category, title, summary, web_markdown,
                   wechat_html, xueqiu_markdown, x_thread_json,
                   cover_oss_url, tags, visibility, publish_status, published_at
            FROM capital.capital_publications
            ORDER BY COALESCE(published_at, created_at) DESC;
            """
        )
        publications = _rows(cur)

        cur.execute(
            """
            SELECT publication_id, channel, snapshot_date, impressions,
                   views_or_reads, likes_and_bookmarks, comments_and_shares,
                   net_new_followers, referral_clicks_to_web
            FROM capital.media_channel_metrics
            ORDER BY snapshot_date DESC;
            """
        )
        metrics = _rows(cur)

    return {
        "theses": theses,
        "playbooks": playbooks,
        "trades": trades,
        "publications": publications,
        "metrics": metrics,
    }


def _fetch_home(conn) -> dict[str, list[dict[str, Any]]]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT event_id, title, summary, domain, event_type, occurred_at,
                   ended_at, importance_score, energy_impact, duration_minutes,
                   location_name, tags, metrics_payload, privacy
            FROM archive.timeline_events
            ORDER BY occurred_at DESC
            LIMIT 500;
            """
        )
        timeline = _rows(cur)

        cur.execute(
            """
            SELECT asset_id, asset_category, title, original_filename, mime_type,
                   file_size_bytes, captured_at, document_date, domain, tags,
                   privacy, media_metadata
            FROM archive.archive_assets
            WHERE deleted_at IS NULL
            ORDER BY COALESCE(captured_at, created_at) DESC
            LIMIT 500;
            """
        )
        assets = _rows(cur)

        cur.execute(
            """
            SELECT retro_id, retro_type, domain, title, period_start, period_end,
                   initial_hypothesis, actual_execution, root_cause_analysis,
                   codified_principles, kpi_snapshot, action_items,
                   execution_score, outcome_score, tags, privacy
            FROM archive.project_retrospectives
            ORDER BY period_end DESC
            LIMIT 200;
            """
        )
        retros = _rows(cur)

        cur.execute(
            """
            SELECT workout_id, workout_type, title, started_at, ended_at,
                   duration_minutes, calories_kcal, avg_heart_rate, rpe_score,
                   distance_meters, avg_pace_sec_km, total_volume_kg, tags
            FROM archive.fitness_workouts
            ORDER BY started_at DESC
            LIMIT 200;
            """
        )
        workouts = _rows(cur)

    return {
        "timeline": timeline,
        "assets": assets,
        "retros": retros,
        "workouts": workouts,
    }


def _home_public(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """莫伯之家公域过滤：剔除 VAULT/PRIVATE 与 is_sensitive 记录。"""
    allowed = set(HOME_PUBLIC_PRIVACY)
    kept = [
        r
        for r in records
        if str(r.get("privacy", "PUBLIC")).upper() in allowed and not r.get("is_sensitive")
    ]
    return [exporters.strip_private_fields(r) for r in kept]


def export_capital_site(settings, *, include_internal: bool = True) -> dict[str, Path]:
    """导出莫伯资本站点数据包。"""
    from .db import connect_mobobrain  # 局部导入避免循环

    written: dict[str, Path] = {}
    with connect_mobobrain(settings) as conn:
        data = _fetch_capital(conn)
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM capital.v_latest_macro_indicators;")
            macro_snapshot = _rows(cur)
            cur.execute("SELECT * FROM capital.v_latest_options_vol_surface;")
            vol_snapshot = _rows(cur)
        nav = capital.nav_snapshot(conn)

    public = exporters.build_public_capital_payload(
        theses=data["theses"],
        playbooks=data["playbooks"],
        trades=data["trades"],
        publications=data["publications"],
        metrics=data["metrics"],
    )
    audit = exporters.audit_payload(public)
    if not audit["ok"]:
        raise RuntimeError(f"公域数据包脱敏校验未通过：{audit}")

    root = Path(settings.capital_web_dir)
    written["public_data"] = exporters.write_json(root / "data" / "public-data.json", public)
    written["terminal_snapshot"] = exporters.write_json(
        root / "data" / "terminal-snapshot.json",
        {
            "macro_indicators": macro_snapshot,
            "options_vol_surface": vol_snapshot,
            "portfolio_nav": nav,
        },
    )

    if include_internal:
        internal = exporters.build_internal_capital_payload(
            theses=data["theses"],
            playbooks=data["playbooks"],
            trades=data["trades"],
            publications=data["publications"],
            metrics=data["metrics"],
        )
        written["internal_data"] = exporters.write_json(
            root / "internal" / "internal-data.json", internal
        )
    return written


def export_home_site(settings, *, include_internal: bool = True) -> dict[str, Path]:
    """导出莫伯之家站点数据包。"""
    from .db import connect_archive

    written: dict[str, Path] = {}
    with connect_archive(settings) as conn:
        data = _fetch_home(conn)

    public = {
        "timeline_events": _home_public(data["timeline"]),
        "archive_assets": _home_public(data["assets"]),
        "retrospectives": _home_public(data["retros"]),
        "workouts": _home_public(data["workouts"]),
    }
    audit = exporters.audit_payload(public)
    if not audit["ok"]:
        raise RuntimeError(f"公域数据包脱敏校验未通过：{audit}")

    root = Path(settings.home_web_dir)
    written["public_data"] = exporters.write_json(root / "data" / "public-home-data.json", public)

    if include_internal:
        internal = {
            "timeline_events": data["timeline"],
            "archive_assets": data["assets"],
            "retrospectives": data["retros"],
            "workouts": data["workouts"],
        }
        written["internal_data"] = exporters.write_json(
            root / "internal" / "internal-home-data.json", internal
        )
    return written


def sync_all(settings, *, include_internal: bool = True) -> dict[str, Path]:
    written: dict[str, Path] = {}
    written.update(export_capital_site(settings, include_internal=include_internal))
    written.update(export_home_site(settings, include_internal=include_internal))
    return written
