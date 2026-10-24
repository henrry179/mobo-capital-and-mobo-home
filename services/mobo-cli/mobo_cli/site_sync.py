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

from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping

from psycopg2.extras import RealDictCursor

from . import capital, exporters

# 莫伯之家：时间线/图库公域仅 PUBLIC；阅读无 privacy 列，靠 tag public_portal
HOME_PUBLIC_PRIVACY = ("PUBLIC", "RESTRICTED")
HOME_PUBLIC_TIMELINE_PRIVACY = ("PUBLIC",)
HOME_PUBLIC_GALLERY_PRIVACY = ("PUBLIC",)
HOME_PUBLIC_READING_TAG = "public_portal"


def _rows(cur) -> list[dict[str, Any]]:
    return [dict(r) for r in cur.fetchall()]


def _fetch_capital(conn) -> dict[str, list[dict[str, Any]]]:
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
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

        cur.execute(
            """
            SELECT id, phase_number, phase_name, domain_category, milestone_title,
                   target_metric_desc, current_progress_pct, target_date,
                   completed_date, status, action_plan_md, visibility, created_at
            FROM capital.fund_incubation_milestones
            ORDER BY phase_number, target_date;
            """
        )
        milestones = _rows(cur)

        cur.execute(
            """
            SELECT id, doc_slug, doc_type, title, version, summary, content_md,
                   private_attachment_oss_key, visibility, published_at
            FROM capital.fund_governance_docs
            ORDER BY published_at DESC NULLS LAST, title;
            """
        )
        governance_docs = _rows(cur)

    return {
        "theses": theses,
        "playbooks": playbooks,
        "trades": trades,
        "publications": publications,
        "metrics": metrics,
        "milestones": milestones,
        "governance_docs": governance_docs,
    }


def _fetch_home(conn) -> dict[str, list[dict[str, Any]]]:
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
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

        cur.execute(
            """
            SELECT item_id, title, authors, domain, status, rating, core_takeaways
            FROM archive.reading_items
            ORDER BY COALESCE(finished_at, created_at) DESC
            LIMIT 200;
            """
        )
        readings = _rows(cur)

    return {
        "timeline": timeline,
        "assets": assets,
        "retros": retros,
        "workouts": workouts,
        "readings": readings,
    }


def _home_public(
    records: list[dict[str, Any]],
    *,
    allowed: tuple[str, ...] = HOME_PUBLIC_PRIVACY,
) -> list[dict[str, Any]]:
    """莫伯之家公域过滤：按允许的 privacy 集合剔除敏感记录。"""
    allow = {a.upper() for a in allowed}
    kept = [
        r
        for r in records
        if str(r.get("privacy", "PUBLIC")).upper() in allow and not r.get("is_sensitive")
    ]
    return [exporters.strip_private_fields(r) for r in kept]


def _home_public_timeline(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """公域时间线仅 PUBLIC。"""
    return _home_public(records, allowed=HOME_PUBLIC_TIMELINE_PRIVACY)


def _home_public_gallery(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """公域图库仅 PUBLIC（排除 RESTRICTED 沙盒占位图）。"""
    return _home_public(records, allowed=HOME_PUBLIC_GALLERY_PRIVACY)


def _home_public_readings(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """公域书单：reading_items 无 privacy 列，仅导出带 public_portal 标签的条目。"""
    kept = [
        r
        for r in records
        if HOME_PUBLIC_READING_TAG in [str(t) for t in (r.get("tags") or [])]
        and not r.get("is_sensitive")
        and "沙盒" not in str(r.get("title") or "")
    ]
    return [exporters.strip_private_fields(r) for r in kept]


# 门户（sites/mobohome/index.html）期望的字段形态，与库内表结构不同：
# 门户用 timeline_stories / gallery_assets / reading_library 三组键。
_PLACEHOLDER_THUMB = (
    "data:image/svg+xml;charset=utf-8,"
    "%3Csvg xmlns='http://www.w3.org/2000/svg' width='800' height='450'%3E"
    "%3Crect width='800' height='450' fill='%23141721'/%3E"
    "%3Ctext x='50%25' y='50%25' fill='%236b7280' font-size='26' "
    "text-anchor='middle' font-family='sans-serif'%3E%E6%9C%AA%E6%8C%89%E8%B4%A8%E7%B3%BB%E5%8F%98%E6%9C%AC%E8%AF%81%E4%BB%A3%EF%BC%9C%3C/text%3E"
    "%3C/svg%3E"
)


# 档案 domain 枚举 → 之家门户篇章筛选键（整合总览 G5）
_DOMAIN_TO_LIFE_CHAPTER: dict[str, str] = {
    "FITNESS_HEALTH": "湖北·归航与长期筑基",
    "SYSTEM_TECH": "湖北·归航与长期筑基",
    "LEARNING_EXAM": "湖北·归航与长期筑基",
    "CAREER_WORK": "上海·供应链深耕",
    "FAMILY_LIFE": "湖北·归航与长期筑基",
    "INVEST_TRADING": "北上深·历练期",
    "INVEST_RESEARCH": "北上深·历练期",
    "TRAVEL": "北上深·历练期",
}


def _life_chapter_from_row(row: Mapping[str, Any], metrics: Mapping[str, Any]) -> str:
    """优先用 metrics 里的中文篇章；否则把 domain 映射到门户筛选键。"""
    raw = metrics.get("life_chapter") or metrics.get("chapter")
    if isinstance(raw, str) and raw.strip():
        return raw.strip()
    domain = str(row.get("domain") or "").strip().upper()
    if domain in _DOMAIN_TO_LIFE_CHAPTER:
        return _DOMAIN_TO_LIFE_CHAPTER[domain]
    if domain:
        return domain
    return "人生纪事"


def _to_timeline_story(row: dict[str, Any]) -> dict[str, Any]:
    """库内 timeline_events → 门户期望的 timeline_stories。"""
    metrics = row.get("metrics_payload") or {}
    if not isinstance(metrics, dict):
        metrics = {}
    media = metrics.get("attached_media") or []
    if not isinstance(media, list):
        media = []
    content = metrics.get("content_markdown") or row.get("summary") or ""
    return {
        "id": str(metrics.get("editorial_slug") or row.get("event_id") or ""),
        "event_date": str(row.get("occurred_at", ""))[:10],
        "category": str(row.get("event_type") or row.get("domain") or "event").lower(),
        "title": row.get("title", ""),
        "summary": row.get("summary") or "",
        "location_name": row.get("location_name") or "",
        "importance": int(row.get("importance_score") or 5),
        "mood_score": int(metrics.get("mood_score") or 5),
        "energy_score": int(metrics.get("energy_score") or abs(int(row.get("energy_impact") or 0)) or 5),
        "tags": list(row.get("tags") or []),
        "metadata": {
            "life_chapter": _life_chapter_from_row(row, metrics),
            "domain": str(row.get("domain") or ""),
            "content_markdown": content,
        },
        "attached_media": media,
    }


def _to_gallery_asset(row: dict[str, Any]) -> dict[str, Any]:
    """库内 archive_assets → 门户期望的 gallery_assets。"""
    media = row.get("media_metadata") or {}
    if not isinstance(media, dict):
        media = {}
    thumb = media.get("public_thumb_url") or _PLACEHOLDER_THUMB
    asset_type = "video" if str(row.get("asset_category", "")).upper() == "VIDEO" or "video" in str(
        row.get("mime_type", "")
    ) else "photo"
    return {
        "id": str(media.get("editorial_slug") or row.get("asset_id") or ""),
        "asset_type": asset_type,
        "title": row.get("title", ""),
        "captured_at": str(row.get("captured_at") or row.get("document_date") or "")[:10],
        "public_thumb_url": thumb,
    }


def _to_reading_book(row: dict[str, Any]) -> dict[str, Any]:
    """库内 reading_items → 门户期望的 reading_library。"""
    tags = [str(t) for t in (row.get("tags") or [])]
    category = next(
        (t for t in tags if t in {"PHYSICS", "FINANCE", "STRATEGY", "GENERAL"}),
        str(row.get("domain") or "GENERAL"),
    )
    rating = row.get("rating")
    try:
        rating_i = int(round(float(rating))) if rating is not None else 0
    except (TypeError, ValueError):
        rating_i = 0
    return {
        "id": str(row.get("isbn_or_doi") or row.get("item_id") or ""),
        "title": row.get("title", ""),
        "author": "、".join(row.get("authors") or []),
        "category": category,
        "status": str(row.get("status") or "READING"),
        "rating": rating_i,
        "core_takeaway": row.get("core_takeaways") or "",
    }


def export_capital_site(settings, *, include_internal: bool = True) -> dict[str, Path]:
    """导出莫伯资本站点数据包。"""
    from .db import connect_mobobrain  # 局部导入避免循环

    written: dict[str, Path] = {}
    with connect_mobobrain(settings) as conn:
        data = _fetch_capital(conn)
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
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
        milestones=data["milestones"],
        governance_docs=data["governance_docs"],
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
            milestones=data["milestones"],
            governance_docs=data["governance_docs"],
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
        # 门户视图形态（sites/mobohome/index.html 直接消费）
        "timeline_stories": [_to_timeline_story(r) for r in _home_public_timeline(data["timeline"])],
        "gallery_assets": [_to_gallery_asset(r) for r in _home_public_gallery(data["assets"])],
        "reading_library": [_to_reading_book(r) for r in _home_public_readings(data["readings"])],
        # 原始表结构形态（控制台 / 二次分析用）
        "timeline_events": _home_public_timeline(data["timeline"]),
        "archive_assets": _home_public_gallery(data["assets"]),
        # 复盘/运动沙盒数据仅进内网包，避免公域 JSON 泄漏「沙盒」字样
        "retrospectives": [],
        "workouts": [],
        "exported_at": datetime.now(timezone.utc).isoformat(),
        "visibility": "PUBLIC",
        "source_notes": (
            "timeline/gallery privacy=PUBLIC; reading_library tag=public_portal; "
            "retrospectives/workouts omitted from public package"
        ),
    }
    audit = exporters.audit_payload(public)
    if not audit["ok"]:
        raise RuntimeError(f"公域数据包脱敏校验未通过：{audit}")

    root = Path(settings.home_web_dir)
    written["public_data"] = exporters.write_json(root / "data" / "public-home-data.json", public)

    if include_internal:
        internal = {
            "timeline_stories": [_to_timeline_story(r) for r in data["timeline"]],
            "gallery_assets": [_to_gallery_asset(r) for r in data["assets"]],
            "reading_library": [_to_reading_book(r) for r in data["readings"]],
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
