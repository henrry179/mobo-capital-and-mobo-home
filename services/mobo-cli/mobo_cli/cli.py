"""mobo-cli：本地/云端录入网站 B 数据。

用法：
    mobo-cli doctor
    mobo-cli upload ~/Pictures/a.jpg --category PHOTO --domain FAMILY_LIFE
    mobo-cli read --title "..." --author "..." --status COMPLETED --rating 9
    mobo-cli workout --type RUNNING --minutes 51 --distance-km 10
    mobo-cli bio --sleep 7.4 --resting-hr 56
    mobo-cli retro --file weekly.md --type WEEKLY
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import date, datetime, time, timedelta
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

import psycopg2
from psycopg2.extras import Json

from .config import Settings, get_settings
from .db import connect_archive, connect_mobobrain
from .embeddings import embed_text, vector_literal
from .media import (
    extract_pdf_text,
    guess_mime,
    human_size,
    image_info,
    is_image,
    is_pdf,
    make_thumbnail,
    object_keys,
    parse_exif_date,
    sha256_file,
)
from .retro import pace_sec_per_km, parse_kv_lines, parse_retro_markdown
from .storage import Storage

TZ = ZoneInfo(os.getenv("TZ", "Asia/Shanghai"))

LIFE_DOMAINS = [
    "CAREER_WORK",
    "INVEST_TRADING",
    "LEARNING_EXAM",
    "FITNESS_HEALTH",
    "FAMILY_LIFE",
    "SYSTEM_TECH",
]
PRIVACY = ["PUBLIC", "RESTRICTED", "PRIVATE", "VAULT"]
CATEGORIES = ["PHOTO", "VIDEO", "SCAN_DOC", "CERTIFICATE", "MEDICAL", "OTHER"]


def parse_date(value: str) -> date:
    return date.fromisoformat(value)


def parse_dt(value: str) -> datetime:
    dt = datetime.fromisoformat(value)
    if dt.tzinfo is None:
        # 只给日期时默认上午 9 点；给时间则按本地时区
        if len(value) <= 10:
            dt = datetime.combine(dt.date(), time(9, 0))
        dt = dt.replace(tzinfo=TZ)
    return dt


def split_tags(value: str | None) -> list[str]:
    if not value:
        return []
    return [x.strip() for x in value.split(",") if x.strip()]


def now_local() -> datetime:
    return datetime.now(TZ)


def print_kv(title: str, rows: dict[str, Any]) -> None:
    print(title)
    for key, value in rows.items():
        if value is not None:
            print(f"  {key}: {value}")


def fetch_timeline_event(cur, source_table: str, source_id: Any) -> dict[str, Any] | None:
    cur.execute(
        """
        SELECT event_id, title, occurred_at, ended_at, importance_score, metrics_payload
        FROM archive.timeline_events
        WHERE source_table = %s AND source_id = %s
        """,
        (source_table, source_id),
    )
    row = cur.fetchone()
    if not row:
        return None
    return {
        "event_id": row[0],
        "title": row[1],
        "occurred_at": row[2].isoformat() if row[2] else None,
        "ended_at": row[3].isoformat() if row[3] else None,
        "importance_score": row[4],
        "metrics_payload": row[5],
    }


# =============================================================================
# doctor
# =============================================================================
def cmd_doctor(args: argparse.Namespace) -> int:
    settings = get_settings(args.env_file)
    fails = 0
    warns = 0

    def ok(msg: str) -> None:
        print(f"[OK]   {msg}")

    def warn(msg: str) -> None:
        nonlocal warns
        warns += 1
        print(f"[WARN] {msg}")

    def fail(msg: str) -> None:
        nonlocal fails
        fails += 1
        print(f"[FAIL] {msg}")

    print(f"mobo-cli doctor · DB {settings.db_host}:{settings.db_port}")

    if settings.archive_password:
        ok("CLI_ARCHIVE_DB_PASSWORD 已配置")
    else:
        fail("CLI_ARCHIVE_DB_PASSWORD 未配置")

    try:
        if not settings.archive_password:
            raise RuntimeError("缺少 CLI_ARCHIVE_DB_PASSWORD")
        with connect_archive(settings) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT current_database(), current_user, version()")
                db, user, version = cur.fetchone()
                ok(f"archive 连接：{db} / {user} / {version.split(',')[0]}")
                cur.execute("SELECT count(*) FROM archive.timeline_events")
                ok(f"timeline_events: {cur.fetchone()[0]} 行")
                cur.execute("SELECT count(*) FROM archive.archive_assets")
                ok(f"archive_assets: {cur.fetchone()[0]} 行")
                cur.execute("SELECT count(*) FROM archive.v_weekly_life_analytics")
                ok(f"v_weekly_life_analytics: {cur.fetchone()[0]} 行")
    except Exception as exc:  # noqa: BLE001
        fail(f"archive 连接/查询失败：{exc}")

    try:
        if not settings.mobobrain_password:
            raise RuntimeError("缺少 CLI_MOBOBRAIN_DB_PASSWORD")
        with connect_mobobrain(settings) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT count(*) FROM intel.articles_vault")
                ok(f"intel.articles_vault: {cur.fetchone()[0]} 行")
                cur.execute("SELECT count(*) FROM intel.content_drafts")
                ok(f"intel.content_drafts: {cur.fetchone()[0]} 行")
                cur.execute("SELECT to_regnamespace('n8n') IS NOT NULL")
                if cur.fetchone()[0]:
                    ok("n8n Schema 存在")
                else:
                    warn("n8n Schema 不存在（首次启动 n8n 后创建）")
    except Exception as exc:  # noqa: BLE001
        fail(f"mobobrain 连接/查询失败：{exc}")

    if settings.oss_ready():
        try:
            storage = Storage(settings)
            ok(f"OSS Bucket: {storage.bucket_name} / ACL={storage.acl()}")
        except Exception as exc:  # noqa: BLE001
            fail(f"OSS 检查失败：{exc}")
    else:
        warn("OSS 配置不完整（上传功能不可用；其余命令可用）")

    if settings.embedding_api_base and settings.embedding_api_key and settings.embedding_model:
        ok(f"Embedding: {settings.embedding_model} (dim={settings.embedding_dim})")
    else:
        warn("Embedding 未配置（upload --embed 将跳过）")

    print(f"\n结果：FAIL={fails} WARN={warns}")
    return 1 if fails else 0


# =============================================================================
# upload
# =============================================================================
def cmd_upload(args: argparse.Namespace) -> int:
    settings = get_settings(args.env_file)
    path = Path(args.file).expanduser().resolve()
    if not path.is_file():
        raise SystemExit(f"文件不存在：{path}")

    digest = sha256_file(path)
    mime = guess_mime(path)
    category = args.category.upper()
    key, thumb_key = object_keys(category, path, digest)
    title = (args.title or path.stem)[:255]
    tags = split_tags(args.tags)

    if args.dry_run:
        print_kv(
            "DRY RUN（不会上传/写库）",
            {
                "file": str(path),
                "size": human_size(path.stat().st_size),
                "mime": mime,
                "sha256": digest,
                "category": category,
                "oss_key": key,
                "thumbnail_key": thumb_key,
                "title": title,
                "domain": args.domain,
                "privacy": args.privacy,
            },
        )
        return 0

    if not settings.oss_ready():
        raise SystemExit("OSS 配置不完整；至少需要 OSS_CLI_ENDPOINT/OSS_PUBLIC_ENDPOINT、Bucket、AK/SK")

    storage = Storage(settings)
    info = image_info(path)
    exif_date = parse_exif_date(info)
    captured_date = args.captured_at or (date.fromisoformat(exif_date) if exif_date else None)
    if captured_date:
        captured_at = datetime.combine(captured_date, time(12, 0), tzinfo=TZ)
    else:
        captured_at = datetime.fromtimestamp(path.stat().st_mtime, TZ)
    document_date = args.document_date or captured_date or captured_at.date()

    extracted = extract_pdf_text(path) if is_pdf(path) else ""
    media_metadata: dict[str, Any] = {
        "image": info,
        "exif_date": exif_date,
        "thumbnail_generated": False,
        "source": "mobo-cli",
    }

    uploaded_original = False
    uploaded_thumb = False
    thumb_tmp: str | None = None

    try:
        uploaded_original = storage.upload_file(path, key, mime)

        if thumb_key and is_image(path) and not args.no_thumbnail:
            thumb_tmp, _thumb_info = make_thumbnail(path)
            if thumb_tmp:
                with open(thumb_tmp, "rb") as fh:
                    storage.upload_bytes(thumb_key, fh.read(), "image/webp")
                uploaded_thumb = True
                media_metadata["thumbnail_generated"] = True

        with connect_archive(settings) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT asset_id, oss_object_key, thumbnail_key
                    FROM archive.archive_assets
                    WHERE sha256_hash = %s
                    """,
                    (digest,),
                )
                existing = cur.fetchone()
                if existing:
                    asset_id, existing_key, existing_thumb = existing
                    print(f"文件已存在，秒传：asset_id={asset_id}")
                    # 同一内容可能因文件名不同而产生不同的 OSS key；保留已登记对象
                    if uploaded_original and key != existing_key:
                        storage.delete(key)
                    if uploaded_thumb and thumb_key:
                        if existing_thumb:
                            if thumb_key != existing_thumb:
                                storage.delete(thumb_key)
                        else:
                            cur.execute(
                                "UPDATE archive.archive_assets SET thumbnail_key=%s WHERE asset_id=%s",
                                (thumb_key, asset_id),
                            )
                            existing_thumb = thumb_key
                else:
                    text_for_fts = (extracted or title)[:200000]
                    cur.execute(
                        """
                        INSERT INTO archive.archive_assets (
                            asset_category, title, original_filename, mime_type,
                            file_size_bytes, sha256_hash, oss_bucket, oss_object_key,
                            thumbnail_key, current_tier, is_encrypted,
                            captured_at, document_date, extracted_text, search_vector,
                            media_metadata, domain, tags, privacy
                        ) VALUES (
                            %s, %s, %s, %s,
                            %s, %s, %s, %s,
                            %s, 'OSS_STANDARD', FALSE,
                            %s, %s, %s, to_tsvector('simple', %s),
                            %s, %s, %s, %s
                        )
                        ON CONFLICT (sha256_hash) DO NOTHING
                        RETURNING asset_id
                        """,
                        (
                            category,
                            title,
                            path.name[:512],
                            mime,
                            path.stat().st_size,
                            digest,
                            settings.oss_bucket,
                            key,
                            thumb_key if uploaded_thumb else None,
                            captured_at,
                            document_date,
                            extracted[:200000] or None,
                            text_for_fts,
                            Json(media_metadata),
                            args.domain,
                            tags,
                            args.privacy,
                        ),
                    )
                    row = cur.fetchone()
                    if row:
                        asset_id = row[0]
                        print(f"资产入库：asset_id={asset_id}")
                    else:
                        cur.execute(
                            "SELECT asset_id, oss_object_key, thumbnail_key FROM archive.archive_assets WHERE sha256_hash=%s",
                            (digest,),
                        )
                        asset_id, key, thumb_key = cur.fetchone()
                        print(f"并发去重：asset_id={asset_id}")

                if args.embed and asset_id:
                    vec = embed_text(settings, extracted or title)
                    if vec:
                        cur.execute(
                            "UPDATE archive.archive_assets SET embedding=%s::vector WHERE asset_id=%s",
                            (vector_literal(vec), asset_id),
                        )
                        print("Embedding 已写入")
                    else:
                        print("Embedding 未配置，跳过")

            conn.commit()

        print_kv(
            "完成",
            {
                "asset_id": asset_id,
                "bucket": settings.oss_bucket,
                "oss_key": existing_key if existing else key,
                "thumbnail_key": (existing_thumb if existing else thumb_key) if (existing or uploaded_thumb) else None,
                "size": human_size(path.stat().st_size),
                "sha256": digest,
                "signed_url": storage.signed_url(existing_key if existing else key, 3600),
            },
        )
        return 0
    except Exception:
        if uploaded_thumb and thumb_key:
            storage.delete(thumb_key)
        if uploaded_original:
            storage.delete(key)
        raise
    finally:
        if thumb_tmp and os.path.exists(thumb_tmp):
            os.unlink(thumb_tmp)


# =============================================================================
# read
# =============================================================================
def cmd_read(args: argparse.Namespace) -> int:
    settings = get_settings(args.env_file)
    authors = args.author or []
    tags = split_tags(args.tags)
    finished = args.finished
    if args.status == "COMPLETED" and not finished:
        finished = date.today()

    with connect_archive(settings) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT item_id FROM archive.reading_items
                WHERE title = %s AND authors = %s
                ORDER BY created_at DESC LIMIT 1
                """,
                (args.title, authors),
            )
            row = cur.fetchone()

            if row:
                item_id = row[0]
                sets = ["status = %s"]
                values: list[Any] = [args.status]
                for col, val in [
                    ("total_pages", args.total_pages),
                    ("current_page", args.current_page),
                    ("rating", args.rating),
                    ("core_takeaways", args.summary),
                    ("isbn_or_doi", args.isbn),
                    ("started_at", args.started),
                    ("finished_at", finished),
                ]:
                    if val is not None:
                        sets.append(f"{col} = %s")
                        values.append(val)
                if tags:
                    sets.append("tags = %s")
                    values.append(tags)
                if args.domain:
                    sets.append("domain = %s")
                    values.append(args.domain)
                values.append(item_id)
                cur.execute(
                    f"UPDATE archive.reading_items SET {', '.join(sets)} WHERE item_id = %s",
                    values,
                )
                print(f"更新书目：{item_id}")
            else:
                cur.execute(
                    """
                    INSERT INTO archive.reading_items (
                        title, authors, isbn_or_doi, status, total_pages, current_page,
                        rating, core_takeaways, domain, tags, started_at, finished_at
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    RETURNING item_id
                    """,
                    (
                        args.title,
                        authors,
                        args.isbn,
                        args.status,
                        args.total_pages,
                        args.current_page or 0,
                        args.rating,
                        args.summary,
                        args.domain,
                        tags,
                        args.started,
                        finished,
                    ),
                )
                item_id = cur.fetchone()[0]
                print(f"新增书目：{item_id}")

            if args.minutes is not None or args.end_page is not None or args.note:
                cur.execute(
                    """
                    INSERT INTO archive.reading_logs (
                        item_id, log_type, duration_minutes, start_page, end_page,
                        quote_text, comment_markdown
                    ) VALUES (%s, 'SESSION', %s, %s, %s, %s, %s)
                    """,
                    (
                        item_id,
                        args.minutes or 0,
                        args.start_page if args.start_page is not None else (args.current_page or 0),
                        args.end_page,
                        args.quote,
                        args.note,
                    ),
                )
                print("已写入阅读日志")

            conn.commit()
            event = fetch_timeline_event(cur, "reading_items", item_id)

    print_kv("书目 ID", {"item_id": item_id})
    if event:
        print_kv("时间线事件", event)
    else:
        print("时间线：无（状态不是 COMPLETED，或触发器未启用）")
    return 0


# =============================================================================
# workout
# =============================================================================
def cmd_workout(args: argparse.Namespace) -> int:
    if args.minutes <= 0:
        raise SystemExit("--minutes 必须大于 0")
    settings = get_settings(args.env_file)
    started = parse_dt(args.started) if args.started else now_local()
    ended = parse_dt(args.ended) if args.ended else started + timedelta(minutes=args.minutes)
    distance_m = int(round(args.distance_km * 1000)) if args.distance_km is not None else None
    pace = pace_sec_per_km(distance_m, args.minutes)
    details = []
    if args.details:
        details = json.loads(args.details)
    tags = split_tags(args.tags)

    with connect_archive(settings) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO archive.fitness_workouts (
                    workout_type, title, started_at, ended_at, duration_minutes,
                    calories_kcal, avg_heart_rate, max_heart_rate, rpe_score,
                    training_load, distance_meters, avg_pace_sec_km, avg_cadence,
                    elevation_gain_m, total_volume_kg, total_sets, exercise_details,
                    tags, notes
                ) VALUES (
                    %s, %s, %s, %s, %s,
                    %s, %s, %s, %s,
                    %s, %s, %s, %s,
                    %s, %s, %s, %s,
                    %s, %s
                ) RETURNING workout_id
                """,
                (
                    args.type,
                    args.title,
                    started,
                    ended,
                    args.minutes,
                    args.calories,
                    args.avg_hr,
                    args.max_hr,
                    args.rpe,
                    args.load,
                    distance_m,
                    pace,
                    args.cadence,
                    args.elevation,
                    args.volume_kg,
                    args.sets,
                    Json(details),
                    tags,
                    args.notes,
                ),
            )
            workout_id = cur.fetchone()[0]
            conn.commit()
            event = fetch_timeline_event(cur, "fitness_workouts", workout_id)

    print_kv(
        "运动记录",
        {
            "workout_id": workout_id,
            "type": args.type,
            "started_at": started.isoformat(),
            "duration_minutes": args.minutes,
            "distance_km": args.distance_km,
            "pace_sec_km": pace,
            "tags": tags,
        },
    )
    if event:
        print_kv("时间线事件", event)
    return 0


# =============================================================================
# bio
# =============================================================================
def cmd_bio(args: argparse.Namespace) -> int:
    settings = get_settings(args.env_file)
    fields: dict[str, Any] = {
        "weight_kg": args.weight,
        "body_fat_pct": args.body_fat,
        "resting_hr": args.resting_hr,
        "hrv_ms": args.hrv,
        "sleep_hours": args.sleep,
        "deep_sleep_hours": args.deep_sleep,
        "steps_count": args.steps,
        "subjective_energy": args.energy,
    }
    fields = {k: v for k, v in fields.items() if v is not None}
    if not fields:
        raise SystemExit("至少提供一个生理指标（--weight/--body-fat/--resting-hr/--sleep/...）")

    record_date = args.date or date.today()
    cols = ["record_date"] + list(fields.keys())
    placeholders = ", ".join(["%s"] * len(cols))
    updates = ", ".join(f"{k} = EXCLUDED.{k}" for k in fields)
    sql = (
        f"INSERT INTO archive.fitness_biometrics ({', '.join(cols)}) "
        f"VALUES ({placeholders}) "
        f"ON CONFLICT (record_date) DO UPDATE SET {updates} "
        f"RETURNING record_date"
    )
    with connect_archive(settings) as conn:
        with conn.cursor() as cur:
            cur.execute(sql, [record_date, *fields.values()])
            conn.commit()
    print_kv("生理基线已写入", {"record_date": record_date, **fields})
    return 0


# =============================================================================
# retro
# =============================================================================
def cmd_retro(args: argparse.Namespace) -> int:
    settings = get_settings(args.env_file)
    text = ""
    source_name = args.title
    if args.file:
        if args.file == "-":
            text = sys.stdin.read()
        else:
            text = Path(args.file).expanduser().read_text(encoding="utf-8")
            source_name = source_name or Path(args.file).stem
    parsed = parse_retro_markdown(text) if text else {
        "initial_hypothesis": None,
        "actual_execution": None,
        "root_cause_analysis": None,
        "codified_principles": None,
        "kpi_snapshot": {},
        "action_items": [],
    }

    def pick(cli_value: Any, parsed_value: Any) -> Any:
        return cli_value if cli_value is not None else parsed_value

    hypothesis = pick(args.hypothesis, parsed["initial_hypothesis"])
    actual = pick(args.actual, parsed["actual_execution"])
    root_cause = pick(args.root_cause, parsed["root_cause_analysis"])
    principles = pick(args.principles, parsed["codified_principles"])

    kpi = dict(parsed["kpi_snapshot"] or {})
    if args.kpi:
        kpi.update(parse_kv_lines(args.kpi))
    actions = list(parsed["action_items"] or [])
    if args.action:
        actions.extend({"text": a} for a in args.action)

    today = date.today()
    period_start = args.period_start or (today - timedelta(days=today.weekday()))
    period_end = args.period_end or (period_start + timedelta(days=6))
    if period_end < period_start:
        raise SystemExit("--period-end 不能早于 --period-start")

    title = source_name or f"周复盘 {period_start.isoformat()}"
    tags = split_tags(args.tags)

    with connect_archive(settings) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO archive.project_retrospectives (
                    retro_type, domain, title, period_start, period_end,
                    initial_hypothesis, actual_execution, root_cause_analysis,
                    codified_principles, kpi_snapshot, action_items,
                    execution_score, outcome_score, tags, privacy
                ) VALUES (
                    %s, %s, %s, %s, %s,
                    %s, %s, %s,
                    %s, %s, %s,
                    %s, %s, %s, %s
                ) RETURNING retro_id
                """,
                (
                    args.type,
                    args.domain,
                    title,
                    period_start,
                    period_end,
                    hypothesis,
                    actual,
                    root_cause,
                    principles,
                    Json(kpi),
                    Json(actions),
                    args.execution,
                    args.outcome,
                    tags,
                    args.privacy,
                ),
            )
            retro_id = cur.fetchone()[0]
            if args.embed:
                vec = embed_text(settings, "\n".join(x for x in [title, actual, root_cause, principles] if x))
                if vec:
                    cur.execute(
                        "UPDATE archive.project_retrospectives SET embedding=%s::vector WHERE retro_id=%s",
                        (vector_literal(vec), retro_id),
                    )
            conn.commit()
            event = fetch_timeline_event(cur, "project_retrospectives", retro_id)

    print_kv(
        "复盘已写入",
        {
            "retro_id": retro_id,
            "type": args.type,
            "title": title,
            "period": f"{period_start} ~ {period_end}",
            "kpi_keys": list(kpi.keys()),
            "actions": len(actions),
        },
    )
    if event:
        print_kv("时间线事件", event)
    return 0


# =============================================================================
# argparse
# =============================================================================
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mobo-cli",
        description="莫伯双站 · 网站 B 数据录入 CLI",
    )
    parser.add_argument("--env-file", help="指定 .env 路径（默认当前目录 .env）")
    parser.add_argument("--version", action="version", version="mobo-cli 0.1.0")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("doctor", help="检查数据库/OSS/Embedding 配置")
    p.set_defaults(func=cmd_doctor)

    p = sub.add_parser("upload", help="上传数字资产并写 archive_assets")
    p.add_argument("file", help="本地文件路径")
    p.add_argument("--category", default="OTHER", choices=CATEGORIES)
    p.add_argument("--title", help="标题，默认文件名")
    p.add_argument("--domain", default="FAMILY_LIFE", choices=LIFE_DOMAINS)
    p.add_argument("--privacy", default="PRIVATE", choices=PRIVACY)
    p.add_argument("--tags", help="逗号分隔标签")
    p.add_argument("--captured-at", type=parse_date, help="拍摄/创建日期 YYYY-MM-DD")
    p.add_argument("--document-date", type=parse_date, help="文档日期 YYYY-MM-DD")
    p.add_argument("--no-thumbnail", action="store_true", help="不生成 WebP 缩略图")
    p.add_argument("--embed", action="store_true", help="调用 Embedding API 写入向量")
    p.add_argument("--dry-run", action="store_true", help="只打印计划，不上传/写库")
    p.set_defaults(func=cmd_upload)

    p = sub.add_parser("read", help="新增/更新书目与阅读日志")
    p.add_argument("--title", required=True)
    p.add_argument("--author", action="append", default=[], help="作者，可重复")
    p.add_argument("--status", default="READING", choices=["WISHLIST", "READING", "COMPLETED", "ABANDONED"])
    p.add_argument("--total-pages", type=int)
    p.add_argument("--current-page", type=int)
    p.add_argument("--rating", type=float, help="0–10")
    p.add_argument("--started", type=parse_date)
    p.add_argument("--finished", type=parse_date)
    p.add_argument("--domain", default="LEARNING_EXAM", choices=LIFE_DOMAINS)
    p.add_argument("--tags")
    p.add_argument("--isbn")
    p.add_argument("--summary", help="核心收获")
    p.add_argument("--minutes", type=int, help="本次阅读分钟数")
    p.add_argument("--start-page", type=int)
    p.add_argument("--end-page", type=int)
    p.add_argument("--quote", help="摘录")
    p.add_argument("--note", help="批注 Markdown")
    p.set_defaults(func=cmd_read)

    p = sub.add_parser("workout", help="新增运动记录")
    p.add_argument("--type", required=True, choices=["RUNNING", "STRENGTH", "CYCLING", "SWIMMING", "OTHER"])
    p.add_argument("--minutes", type=int, required=True)
    p.add_argument("--started", help="ISO 时间/日期，默认现在")
    p.add_argument("--ended", help="ISO 时间；默认 started + minutes")
    p.add_argument("--distance-km", type=float)
    p.add_argument("--rpe", type=float)
    p.add_argument("--avg-hr", type=int)
    p.add_argument("--max-hr", type=int)
    p.add_argument("--calories", type=int)
    p.add_argument("--load", type=int, help="训练负荷")
    p.add_argument("--cadence", type=int)
    p.add_argument("--elevation", type=float, help="累计爬升 m")
    p.add_argument("--volume-kg", type=float, help="力量总容量 kg")
    p.add_argument("--sets", type=int, help="总组数")
    p.add_argument("--details", help="动作明细 JSON 数组字符串")
    p.add_argument("--title")
    p.add_argument("--tags")
    p.add_argument("--notes")
    p.set_defaults(func=cmd_workout)

    p = sub.add_parser("bio", help="新增/更新每日生理基线")
    p.add_argument("--date", type=parse_date)
    p.add_argument("--weight", type=float)
    p.add_argument("--body-fat", type=float)
    p.add_argument("--resting-hr", type=int)
    p.add_argument("--hrv", type=int)
    p.add_argument("--sleep", type=float)
    p.add_argument("--deep-sleep", type=float)
    p.add_argument("--steps", type=int)
    p.add_argument("--energy", type=int, help="主观能量 1–10")
    p.set_defaults(func=cmd_bio)

    p = sub.add_parser("retro", help="新增结构化复盘（Markdown 或参数）")
    p.add_argument("--file", help="Markdown 文件；- 表示 stdin")
    p.add_argument("--title")
    p.add_argument("--type", default="WEEKLY", choices=["WEEKLY", "PROJECT_POSTMORTEM", "TRADING_PLAYBOOK", "EXAM_STAGE", "OTHER"])
    p.add_argument("--domain", default="SYSTEM_TECH", choices=LIFE_DOMAINS)
    p.add_argument("--period-start", type=parse_date)
    p.add_argument("--period-end", type=parse_date)
    p.add_argument("--hypothesis")
    p.add_argument("--actual")
    p.add_argument("--root-cause")
    p.add_argument("--principles")
    p.add_argument("--kpi", action="append", help="KPI，如 '阅读小时=6.5'，可重复")
    p.add_argument("--action", action="append", help="行动项，可重复")
    p.add_argument("--execution", type=int, help="执行分 1–10")
    p.add_argument("--outcome", type=int, help="结果分 1–10")
    p.add_argument("--privacy", default="PRIVATE", choices=PRIVACY)
    p.add_argument("--tags")
    p.add_argument("--embed", action="store_true")
    p.set_defaults(func=cmd_retro)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except psycopg2.Error as exc:
        print(f"数据库错误：{exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("已取消", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
