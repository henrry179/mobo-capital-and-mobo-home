#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MoBo Dual-Site CLI (v2.1) — 莫伯资本 (MoBoCapital.com) & 莫伯之家 (MoBoHome.com) 双栖终端总控引擎
路径: /opt/mobo-stack/scripts/mobo_cli.py
依赖: pip install psycopg2-binary oss2 Pillow pypdf python-dotenv pyyaml
"""

import os
import sys
import json
import yaml
import hashlib
import mimetypes
import subprocess
import argparse
from io import BytesIO
from datetime import datetime, date
from decimal import Decimal
from pathlib import Path

import oss2
import psycopg2
from psycopg2.extras import RealDictCursor, Json
from PIL import Image, ExifTags
from pypdf import PdfReader
from dotenv import load_dotenv

ENV_PATH = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(dotenv_path=ENV_PATH)


def get_db_conn(target_site: str):
    host = os.getenv("PG_HOST", "127.0.0.1")
    port = int(os.getenv("PG_PORT", "5432"))

    if target_site == "capital":
        return psycopg2.connect(
            host=host,
            port=port,
            dbname=os.getenv("PG_DB_MOBOBRAIN", "db_mobobrain"),
            user=os.getenv("PG_USER_MOBOBRAIN", "user_mobobrain"),
            password=os.getenv("PG_PASS_MOBOBRAIN"),
        )
    elif target_site == "home":
        return psycopg2.connect(
            host=host,
            port=port,
            dbname=os.getenv("PG_DB_ARCHIVE", "db_archive"),
            user=os.getenv("PG_USER_ARCHIVE", "user_archive"),
            password=os.getenv("PG_PASS_ARCHIVE"),
        )
    else:
        raise ValueError(f"未知的目标站点类型: {target_site}")


def get_oss_buckets():
    ak = os.getenv("ALIYUN_ACCESS_KEY_ID")
    sk = os.getenv("ALIYUN_ACCESS_KEY_SECRET")
    endpoint = os.getenv("OSS_ENDPOINT", "https://oss-cn-hangzhou.aliyuncs.com")
    auth = oss2.Auth(ak, sk)

    pub_bucket_name = os.getenv("OSS_BUCKET_PUBLIC", "mobobrain-assets-pub")
    priv_bucket_name = os.getenv("OSS_BUCKET_PRIVATE", "mobo-archive-private-hz")

    return (
        oss2.Bucket(auth, endpoint, pub_bucket_name),
        oss2.Bucket(auth, endpoint, priv_bucket_name),
        pub_bucket_name,
        priv_bucket_name,
    )


def compute_sha256(file_path: Path) -> str:
    h = hashlib.sha256()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def json_serial(obj):
    if isinstance(obj, (datetime, date)):
        return obj.isoformat()
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Type {type(obj)} not serializable")


def extract_image_exif_and_thumb(img_path: Path, max_thumb_width: int = 800):
    exif_meta = {}
    captured_dt = None

    with Image.open(img_path) as img:
        exif_meta["width"] = img.width
        exif_meta["height"] = img.height
        exif_meta["format"] = img.format

        raw_exif = img.getexif()
        if raw_exif:
            for tag_id, val in raw_exif.items():
                tag_name = ExifTags.TAGS.get(tag_id, str(tag_id))
                if tag_name in (
                    "Make", "Model", "DateTime", "DateTimeOriginal",
                    "LensModel", "FocalLength", "FNumber", "ISOSpeedRatings",
                ):
                    exif_meta[tag_name] = str(val)
                if tag_name in ("DateTimeOriginal", "DateTime") and not captured_dt:
                    try:
                        captured_dt = datetime.strptime(str(val), "%Y:%m:%d %H:%M:%S")
                    except Exception:
                        pass

        work_img = img.convert("RGB") if img.mode in ("RGBA", "P") else img.copy()
        if work_img.width > max_thumb_width:
            ratio = max_thumb_width / float(work_img.width)
            new_h = int(float(work_img.height) * ratio)
            work_img = work_img.resize((max_thumb_width, new_h), Image.Resampling.LANCZOS)

        buf = BytesIO()
        work_img.save(buf, format="WEBP", quality=82, method=6)
        webp_bytes = buf.getvalue()

    if not captured_dt:
        captured_dt = datetime.fromtimestamp(img_path.stat().st_mtime)

    return captured_dt, exif_meta, webp_bytes


def extract_video_metadata(video_path: Path) -> tuple:
    meta = {"file_ext": video_path.suffix.lower()}
    captured_dt = datetime.fromtimestamp(video_path.stat().st_mtime)

    try:
        cmd = [
            "ffprobe", "-v", "quiet", "-print_format", "json",
            "-show_format", "-show_streams", str(video_path),
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if res.returncode == 0:
            probe_data = json.loads(res.stdout)
            fmt = probe_data.get("format", {})
            if "duration" in fmt:
                meta["duration_sec"] = round(float(fmt["duration"]), 2)
            tags = fmt.get("tags", {})
            if "creation_time" in tags:
                try:
                    captured_dt = datetime.fromisoformat(
                        tags["creation_time"].replace("Z", "+00:00")
                    )
                except Exception:
                    pass
            for s in probe_data.get("streams", []):
                if s.get("codec_type") == "video":
                    meta["codec"] = s.get("codec_name")
                    meta["width"] = s.get("width")
                    meta["height"] = s.get("height")
                    break
    except Exception:
        meta["ffprobe_note"] = "ffprobe not found, basic file stat used"

    return captured_dt, meta


def extract_pdf_text(pdf_path: Path, max_pages: int = 50) -> tuple:
    text_chunks = []
    meta = {}
    try:
        reader = PdfReader(str(pdf_path))
        meta["total_pages"] = len(reader.pages)
        for page in reader.pages[:max_pages]:
            page_txt = page.extract_text()
            if page_txt:
                text_chunks.append(page_txt.strip())
    except Exception as e:
        meta["pdf_parse_warning"] = str(e)

    return "\n\n".join(text_chunks), meta


def archive_single_media_file(
    file_path: Path,
    asset_type: str = None,
    title: str = None,
    captured_at_override: str = None,
    linked_event_id: str = None,
    is_sensitive: bool = True,
    poster_path: str = None,
    extra_tags: list = None,
) -> dict:
    p = file_path.expanduser().resolve()
    if not p.exists() or not p.is_file():
        raise FileNotFoundError(f"找不到待归档文件: {p}")

    ext = p.suffix.lower()
    if not asset_type:
        if ext in (".jpg", ".jpeg", ".png", ".webp", ".heic"):
            asset_type = "photo"
        elif ext in (".mp4", ".mov", ".mkv", ".avi", ".m4v"):
            asset_type = "video"
        elif ext in (".mp3", ".m4a", ".wav", ".flac"):
            asset_type = "audio"
        else:
            asset_type = "scan_doc"

    file_sha256 = compute_sha256(p)
    file_size = p.stat().st_size
    mime_type, _ = mimetypes.guess_type(str(p))
    mime_type = mime_type or "application/octet-stream"
    asset_title = title or p.stem

    conn = get_db_conn("home")
    pub_bucket, priv_bucket, pub_name, priv_name = get_oss_buckets()

    try:
        with conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    "SELECT id, title, oss_object_key, oss_thumbnail_key FROM archive_assets WHERE file_sha256 = %s;",
                    (file_sha256,),
                )
                existing = cur.fetchone()
                if existing:
                    print(f"⚡ [SHA-256 数据库去重命中] 资产 '{existing['title']}' 已归档 (ID: {existing['id']})")
                    if linked_event_id:
                        cur.execute(
                            """
                            UPDATE archive_assets SET linked_event_id = COALESCE(linked_event_id, %s) WHERE id = %s;
                            INSERT INTO entity_links (source_type, source_id, target_type, target_id, relation_type)
                            VALUES ('timeline_event', %s, 'archive_asset', %s, 'has_media')
                            ON CONFLICT DO NOTHING;
                            """,
                            (linked_event_id, existing["id"], linked_event_id, existing["id"]),
                        )
                    return existing

                extracted_text = None
                exif_or_meta = {}
                webp_thumb_bytes = None
                captured_dt = datetime.fromtimestamp(p.stat().st_mtime)

                if asset_type == "photo":
                    captured_dt, exif_or_meta, webp_thumb_bytes = extract_image_exif_and_thumb(p)
                elif asset_type == "video":
                    captured_dt, exif_or_meta = extract_video_metadata(p)
                    if poster_path:
                        _, _, webp_thumb_bytes = extract_image_exif_and_thumb(
                            Path(poster_path).expanduser().resolve()
                        )
                elif ext == ".pdf":
                    extracted_text, exif_or_meta = extract_pdf_text(p)

                if captured_at_override:
                    captured_dt = datetime.fromisoformat(captured_at_override)

                if extra_tags:
                    exif_or_meta["tags"] = extra_tags

                lifecycle_prefix = (
                    asset_type if asset_type in ("photo", "video", "scan_doc") else "scan_doc"
                )
                ym_folder = captured_dt.strftime("%Y/%m")
                oss_object_key = f"{lifecycle_prefix}/{ym_folder}/{file_sha256[:16]}_{p.name}"

                if not priv_bucket.object_exists(oss_object_key):
                    priv_bucket.put_object_from_file(oss_object_key, str(p))
                    print(f"🔒 [OSS 私有原件上传] oss://{priv_name}/{oss_object_key}")

                oss_thumbnail_key = None
                if webp_thumb_bytes:
                    oss_thumbnail_key = (
                        f"thumbnails/{lifecycle_prefix}/{ym_folder}/{file_sha256[:16]}_800w.webp"
                    )
                    priv_bucket.put_object(
                        oss_thumbnail_key,
                        webp_thumb_bytes,
                        headers={"Content-Type": "image/webp"},
                    )
                    if not is_sensitive:
                        pub_bucket.put_object(
                            oss_thumbnail_key,
                            webp_thumb_bytes,
                            headers={
                                "Content-Type": "image/webp",
                                "Cache-Control": "public, max-age=31536000",
                            },
                        )
                        public_domain = os.getenv(
                            "OSS_PUBLIC_CDN_DOMAIN",
                            f"https://{pub_name}.oss-cn-hangzhou.aliyuncs.com",
                        ).rstrip("/")
                        exif_or_meta["public_thumb_url"] = f"{public_domain}/{oss_thumbnail_key}"

                insert_sql = """
                INSERT INTO archive_assets (
                    asset_type, title, captured_at, oss_bucket, oss_object_key,
                    oss_thumbnail_key, file_sha256, file_size_bytes, mime_type,
                    storage_class, extracted_text, exif_or_meta, linked_event_id, is_sensitive
                ) VALUES (
                    %s, %s, %s, %s, %s,
                    %s, %s, %s, %s,
                    'Standard', %s, %s, %s, %s
                )
                RETURNING id, asset_type, title, oss_object_key, oss_thumbnail_key;
                """
                cur.execute(
                    insert_sql,
                    (
                        asset_type, asset_title, captured_dt, priv_name, oss_object_key,
                        oss_thumbnail_key, file_sha256, file_size, mime_type,
                        extracted_text, Json(exif_or_meta), linked_event_id, is_sensitive,
                    ),
                )
                asset_row = cur.fetchone()

                if linked_event_id:
                    cur.execute(
                        """
                        INSERT INTO entity_links (source_type, source_id, target_type, target_id, relation_type)
                        VALUES ('timeline_event', %s, 'archive_asset', %s, 'has_media')
                        ON CONFLICT DO NOTHING;
                        """,
                        (linked_event_id, asset_row["id"]),
                    )

                print(f"✅ [db_archive 归档入库] 类型: {asset_type} | 标题: {asset_title} | 敏感隔离: {is_sensitive}")
                return asset_row
    finally:
        conn.close()


def handle_home_media_cmd(args):
    is_sensitive = not args.public
    tags = [t.strip() for t in args.tags.split(",") if t.strip()] if args.tags else []

    if args.batch_dir:
        folder = Path(args.batch_dir).expanduser().resolve()
        if not folder.is_dir():
            raise ValueError(f"批量目录不存在: {folder}")
        supported_exts = {".jpg", ".jpeg", ".png", ".webp", ".mp4", ".mov", ".pdf"}
        files = sorted(
            [f for f in folder.rglob("*") if f.is_file() and f.suffix.lower() in supported_exts]
        )
        print(f"📂 [批量归档启动] 在 {folder} 中扫描到 {len(files)} 个多媒体/文档文件...")
        for f in files:
            archive_single_media_file(
                file_path=f,
                asset_type=args.type,
                linked_event_id=args.event_id,
                is_sensitive=is_sensitive,
                extra_tags=tags,
            )
    elif args.file:
        archive_single_media_file(
            file_path=Path(args.file),
            asset_type=args.type,
            title=args.title,
            captured_at_override=args.captured_at,
            linked_event_id=args.event_id,
            is_sensitive=is_sensitive,
            poster_path=args.poster,
            extra_tags=tags,
        )
    else:
        raise ValueError("必须指定 --file (单文件) 或 --batch-dir (批量目录)")

    if not args.skip_sync:
        export_home_frontend_json(args.web_dir)


def handle_home_story_cmd(args):
    meta = {}
    content_md = ""

    if args.from_md:
        md_file = Path(args.from_md).expanduser().resolve()
        raw_text = md_file.read_text(encoding="utf-8")
        if raw_text.startswith("---"):
            parts = raw_text.split("---", 2)
            fm = yaml.safe_load(parts[1]) or {}
            content_md = parts[2].strip()
        else:
            fm = {}
            content_md = raw_text.strip()
    else:
        fm = {}
        content_md = args.content or ""

    event_date = args.date or str(fm.get("event_date", date.today()))
    category = args.category or fm.get("category", "milestone")
    title = args.title or fm.get("title")
    summary = args.summary or fm.get("summary") or (content_md[:180] + "..." if len(content_md) > 180 else content_md)
    location = args.location or fm.get("location_name", "武汉")
    importance = int(args.importance if args.importance is not None else fm.get("importance", 4))
    mood = int(args.mood if args.mood is not None else fm.get("mood_score", 8))
    energy = int(args.energy if args.energy is not None else fm.get("energy_score", 8))
    life_stage = args.chapter or fm.get("life_chapter", "湖北·归航与长期筑基")
    is_sensitive = (not args.public) if args.public else bool(fm.get("is_sensitive", False))

    if args.tags:
        tags = [t.strip() for t in args.tags.split(",") if t.strip()]
    else:
        tags = fm.get("tags", [])

    if not title:
        raise ValueError("成长故事或时间线事件必须提供标题 (--title 或在 Markdown Frontmatter 中声明 title)")

    meta["life_chapter"] = life_stage
    meta["content_markdown"] = content_md
    meta["word_count"] = len(content_md)
    if fm.get("slug"):
        meta["slug"] = fm["slug"]

    conn = get_db_conn("home")
    event_id = None

    try:
        with conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    INSERT INTO timeline_events (
                        event_date, event_timestamp, category, title, summary,
                        location_name, importance, mood_score, energy_score,
                        tags, metadata, is_sensitive
                    ) VALUES (
                        %s, CURRENT_TIMESTAMP, %s, %s, %s,
                        %s, %s, %s, %s,
                        %s, %s, %s
                    )
                    RETURNING id, event_date, category, title;
                    """,
                    (
                        event_date, category, title, summary,
                        location, importance, mood, energy,
                        tags, Json(meta), is_sensitive,
                    ),
                )
                ev = cur.fetchone()
                event_id = str(ev["id"])
                print(f"✅ [莫伯之家成长故事已入库] ID: {event_id} | 日期: {ev['event_date']} | 标题: {ev['title']}")
    finally:
        conn.close()

    if args.attach and event_id:
        attach_paths = [p.strip() for p in args.attach.split(",") if p.strip()]
        for ap in attach_paths:
            archive_single_media_file(
                file_path=Path(ap),
                linked_event_id=event_id,
                is_sensitive=is_sensitive,
                extra_tags=tags,
            )

    if not args.skip_sync:
        export_home_frontend_json(args.web_dir)


def handle_home_habit_cmd(args):
    conn = get_db_conn("home")
    try:
        with conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                if args.habit_type == "workout":
                    cur.execute(
                        """
                        INSERT INTO fitness_workouts (
                            workout_date, workout_type, duration_minutes, distance_km,
                            avg_heart_rate, rpe_score, calories_burned, notes
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                        RETURNING id, workout_date, workout_type, duration_minutes;
                        """,
                        (
                            args.date or str(date.today()), args.workout_type,
                            args.duration, args.distance, args.hr, args.rpe,
                            args.calories, args.notes,
                        ),
                    )
                    w = cur.fetchone()
                    print(f"🏃 [运动打卡入库 + 触发器同步完成] {w['workout_date']} | {w['workout_type']} {w['duration_minutes']}分钟")
                elif args.habit_type == "retro":
                    cur.execute(
                        """
                        INSERT INTO project_retrospectives (
                            review_period, period_type, review_date, title,
                            achievements, bottlenecks, next_actions, content_markdown, is_sensitive
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                        RETURNING id, review_period, title;
                        """,
                        (
                            args.period, args.period_type, args.date or str(date.today()),
                            args.title, args.achievements, args.bottlenecks,
                            args.next_actions, args.content or args.achievements or "",
                            not args.public,
                        ),
                    )
                    r = cur.fetchone()
                    print(f"📝 [周期复盘入库 + 触发器同步完成] {r['review_period']} | {r['title']}")
    finally:
        conn.close()

    if not args.skip_sync:
        export_home_frontend_json(args.web_dir)


def export_home_frontend_json(web_dir_override: str = None):
    base_dir = Path(web_dir_override or os.getenv("MOBOHOME_WEB_DIR", "/opt/mobo-stack/sites/mobohome"))
    pub_dir = base_dir / "data"
    int_dir = base_dir / "internal"
    pub_dir.mkdir(parents=True, exist_ok=True)
    int_dir.mkdir(parents=True, exist_ok=True)

    conn = get_db_conn("home")
    _, priv_bucket, pub_name, _ = get_oss_buckets()
    public_domain = os.getenv(
        "OSS_PUBLIC_CDN_DOMAIN", f"https://{pub_name}.oss-cn-hangzhou.aliyuncs.com"
    ).rstrip("/")

    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT id, event_date, category, title, summary, location_name,
                       importance, mood_score, energy_score, tags, metadata,
                       source_table, is_sensitive, created_at
                FROM timeline_events
                ORDER BY event_date DESC, importance DESC;
                """
            )
            events_all = cur.fetchall()

            cur.execute(
                """
                SELECT id, asset_type, title, captured_at, oss_bucket, oss_object_key,
                       oss_thumbnail_key, file_size_bytes, mime_type, storage_class,
                       exif_or_meta, linked_event_id, is_sensitive
                FROM archive_assets
                ORDER BY captured_at DESC;
                """
            )
            assets_all = cur.fetchall()

            cur.execute(
                """
                SELECT id, item_type, title, author, category, status, rating,
                       started_date, completed_date, core_takeaway, tags
                FROM reading_items
                ORDER BY COALESCE(completed_date, started_date, CURRENT_DATE) DESC;
                """
            )
            books_all = cur.fetchall()

            cur.execute("SELECT * FROM v_weekly_life_analytics LIMIT 26;")
            weekly_analytics = cur.fetchall()

            cur.execute(
                """
                SELECT id, review_period, period_type, review_date, title,
                       achievements, bottlenecks, next_actions, content_markdown, is_sensitive
                FROM project_retrospectives
                ORDER BY review_date DESC;
                """
            )
            retros_all = cur.fetchall()

        public_assets, internal_assets = [], []
        event_media_map_pub, event_media_map_int = {}, {}

        for a in assets_all:
            a_int = dict(a)
            a_int["id"] = str(a_int["id"])
            if a_int.get("linked_event_id"):
                a_int["linked_event_id"] = str(a_int["linked_event_id"])

            try:
                a_int["signed_original_url"] = priv_bucket.sign_url("GET", a_int["oss_object_key"], 7200)
                a_int["signed_thumb_url"] = (
                    priv_bucket.sign_url("GET", a_int["oss_thumbnail_key"], 7200)
                    if a_int.get("oss_thumbnail_key") else None
                )
            except Exception:
                a_int["signed_original_url"] = None
                a_int["signed_thumb_url"] = None

            internal_assets.append(a_int)
            if a_int.get("linked_event_id"):
                event_media_map_int.setdefault(a_int["linked_event_id"], []).append(a_int)

            if not a["is_sensitive"]:
                a_pub = {
                    "id": str(a["id"]),
                    "asset_type": a["asset_type"],
                    "title": a["title"],
                    "captured_at": a["captured_at"],
                    "mime_type": a["mime_type"],
                    "exif_or_meta": a["exif_or_meta"],
                    "linked_event_id": str(a["linked_event_id"]) if a.get("linked_event_id") else None,
                    "public_thumb_url": (a["exif_or_meta"] or {}).get("public_thumb_url")
                    or (f"{public_domain}/{a['oss_thumbnail_key']}" if a.get("oss_thumbnail_key") else None),
                }
                public_assets.append(a_pub)
                if a_pub["linked_event_id"]:
                    event_media_map_pub.setdefault(a_pub["linked_event_id"], []).append(a_pub)

        public_events, internal_events = [], []
        for ev in events_all:
            ev_id = str(ev["id"])
            ev_int = dict(ev)
            ev_int["id"] = ev_id
            ev_int["attached_media"] = event_media_map_int.get(ev_id, [])
            internal_events.append(ev_int)

            if not ev["is_sensitive"]:
                ev_pub = dict(ev)
                ev_pub["id"] = ev_id
                ev_pub["attached_media"] = event_media_map_pub.get(ev_id, [])
                public_events.append(ev_pub)

        (pub_dir / "public-home-data.json").write_text(
            json.dumps(
                {
                    "generated_at": datetime.now().isoformat(),
                    "site": "MoBoHome.com (莫伯之家 · 公开数字档案)",
                    "clearance_scope": "PUBLIC",
                    "timeline_stories": public_events,
                    "gallery_assets": public_assets,
                    "reading_library": books_all,
                    "weekly_life_analytics": weekly_analytics,
                    "retrospectives": [r for r in retros_all if not r["is_sensitive"]],
                },
                default=json_serial, ensure_ascii=False, indent=2,
            ),
            encoding="utf-8",
        )
        (int_dir / "internal-home-data.json").write_text(
            json.dumps(
                {
                    "generated_at": datetime.now().isoformat(),
                    "site": "MoBoHome.com (莫伯之家 · 内网全量生命档案馆)",
                    "clearance_scope": "INTERNAL_PRIVATE",
                    "timeline_stories": internal_events,
                    "gallery_assets": internal_assets,
                    "reading_library": books_all,
                    "weekly_life_analytics": weekly_analytics,
                    "retrospectives": retros_all,
                },
                default=json_serial, ensure_ascii=False, indent=2,
            ),
            encoding="utf-8",
        )
        print("🏡 [MoBoHome 莫伯之家前端数据已同步]")
    finally:
        conn.close()


def upload_private_blotter(file_path: str) -> str:
    p = Path(file_path).expanduser().resolve()
    if not p.exists():
        raise FileNotFoundError(f"找不到交割单文件: {p}")
    sha256_hex = compute_sha256(p)
    ext = p.suffix.lower()
    now_prefix = datetime.now().strftime("%Y/%m")
    oss_key = f"blotters/{now_prefix}/{sha256_hex[:16]}_{p.stem}{ext}"
    _, priv_bucket, _, priv_name = get_oss_buckets()
    if not priv_bucket.object_exists(oss_key):
        priv_bucket.put_object_from_file(oss_key, str(p))
        print(f"🔒 [OSS 私有交割单归档] oss://{priv_name}/{oss_key}")
    return oss_key


def upload_public_chart_webp(file_path: str, max_width: int = 1200) -> str:
    p = Path(file_path).expanduser().resolve()
    if not p.exists():
        raise FileNotFoundError(f"找不到图表文件: {p}")
    sha256_hex = compute_sha256(p)
    now_prefix = datetime.now().strftime("%Y/%m")
    oss_key = f"charts/{now_prefix}/{sha256_hex[:16]}.webp"
    pub_bucket, _, pub_name, _ = get_oss_buckets()
    public_domain = os.getenv(
        "OSS_PUBLIC_CDN_DOMAIN", f"https://{pub_name}.oss-cn-hangzhou.aliyuncs.com"
    ).rstrip("/")
    if not pub_bucket.object_exists(oss_key):
        _, _, webp_bytes = extract_image_exif_and_thumb(p, max_thumb_width=max_width)
        pub_bucket.put_object(
            oss_key, webp_bytes,
            headers={"Content-Type": "image/webp", "Cache-Control": "public, max-age=31536000"},
        )
    return f"{public_domain}/{oss_key}"


def parse_trade_markdown(md_path: str) -> dict:
    p = Path(md_path).expanduser().resolve()
    content = p.read_text(encoding="utf-8")
    if not content.startswith("---"):
        raise ValueError("Markdown 复盘文件必须包含顶部 YAML Frontmatter")
    parts = content.split("---", 2)
    frontmatter = yaml.safe_load(parts[1])
    body = parts[2].strip()
    sections = {"pre_trade": "", "execution": "", "lessons": ""}
    current_sec = "pre_trade"
    for line in body.splitlines():
        hl = line.strip().lower()
        if hl.startswith("## ") and ("pre-trade" in hl or "建仓前" in hl):
            current_sec = "pre_trade"
            continue
        elif hl.startswith("## ") and ("execution" in hl or "持仓" in hl or "平仓" in hl):
            current_sec = "execution"
            continue
        elif hl.startswith("## ") and ("lesson" in hl or "心得" in hl or "教训" in hl):
            current_sec = "lessons"
            continue
        sections[current_sec] += line + "\n"
    frontmatter["pre_trade_thesis_md"] = sections["pre_trade"].strip()
    frontmatter["execution_review_md"] = sections["execution"].strip()
    frontmatter["lessons_learned_md"] = sections["lessons"].strip()
    return frontmatter


def upsert_trade_review(args):
    data = parse_trade_markdown(args.from_md) if args.from_md else {}
    trade_code = args.code or data.get("trade_code")
    strategy_code = args.strategy or data.get("strategy_code")
    thesis_code = args.thesis or data.get("thesis_code")
    ticker = args.ticker or data.get("underlying_ticker")
    asset_name = args.asset_name or data.get("asset_name", ticker)
    direction = (args.direction or data.get("direction", "LONG")).upper()
    structure = args.structure or data.get("instrument_structure", "Spot")
    entry_date = args.entry_date or str(data.get("entry_date", date.today()))
    exit_date = args.exit_date or (str(data["exit_date"]) if data.get("exit_date") else None)
    status = (args.status or data.get("trade_status", "CLOSED")).upper()
    init_risk = float(args.init_risk if args.init_risk is not None else data.get("initial_risk_pct", 1.0))
    r_mult = args.r_multiple if args.r_multiple is not None else data.get("realized_r_multiple")
    ret_pct = args.return_pct if args.return_pct is not None else data.get("realized_return_pct")
    impact_bps = args.impact_bps if args.impact_bps is not None else data.get("portfolio_impact_bps")
    discipline = int(args.discipline if args.discipline is not None else data.get("discipline_score", 9))
    emotion = (args.emotion or data.get("emotional_state_tag", "CALM_SYSTEMATIC")).upper()
    visibility = (args.visibility or data.get("visibility", "PUBLIC")).upper()
    pre_thesis = args.pre_thesis or data.get("pre_trade_thesis_md", "")
    exec_review = args.exec_review or data.get("execution_review_md", "")
    lessons = args.lessons or data.get("lessons_learned_md", "")
    greeks_dict = json.loads(args.greeks) if args.greeks else data.get("greeks_snapshot", {})

    blotter_oss_key = upload_private_blotter(args.blotter) if args.blotter else data.get("private_blotter_oss_key")
    chart_oss_url = upload_public_chart_webp(args.chart) if args.chart else data.get("public_chart_oss_url")

    conn = get_db_conn("capital")
    try:
        with conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("SELECT id FROM strategy_playbooks WHERE strategy_code = %s;", (strategy_code,))
                strat_row = cur.fetchone()
                if not strat_row:
                    raise ValueError(f"策略代码 '{strategy_code}' 不存在")
                strategy_id = strat_row["id"]
                thesis_id = None
                if thesis_code:
                    cur.execute("SELECT id FROM macro_theses WHERE thesis_code = %s;", (thesis_code,))
                    t_row = cur.fetchone()
                    if t_row:
                        thesis_id = t_row["id"]

                cur.execute(
                    """
                    INSERT INTO trade_reviews (
                        trade_code, thesis_id, strategy_id, underlying_ticker, asset_name,
                        direction, instrument_structure, entry_date, exit_date, trade_status,
                        initial_risk_pct, realized_r_multiple, realized_return_pct, portfolio_impact_bps,
                        greeks_snapshot, pre_trade_thesis_md, execution_review_md, lessons_learned_md,
                        discipline_score, emotional_state_tag, private_blotter_oss_key, public_chart_oss_url,
                        visibility, updated_at
                    ) VALUES (
                        %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                        %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP
                    )
                    ON CONFLICT (trade_code) DO UPDATE SET
                        realized_r_multiple = EXCLUDED.realized_r_multiple,
                        portfolio_impact_bps = EXCLUDED.portfolio_impact_bps,
                        trade_status = EXCLUDED.trade_status,
                        exit_date = EXCLUDED.exit_date,
                        greeks_snapshot = EXCLUDED.greeks_snapshot,
                        execution_review_md = EXCLUDED.execution_review_md,
                        lessons_learned_md = EXCLUDED.lessons_learned_md,
                        discipline_score = EXCLUDED.discipline_score,
                        private_blotter_oss_key = COALESCE(EXCLUDED.private_blotter_oss_key, trade_reviews.private_blotter_oss_key),
                        public_chart_oss_url = COALESCE(EXCLUDED.public_chart_oss_url, trade_reviews.public_chart_oss_url),
                        visibility = EXCLUDED.visibility,
                        updated_at = CURRENT_TIMESTAMP
                    RETURNING trade_code, realized_r_multiple;
                    """,
                    (
                        trade_code, thesis_id, strategy_id, ticker, asset_name,
                        direction, structure, entry_date, exit_date, status,
                        init_risk, r_mult, ret_pct, impact_bps,
                        Json(greeks_dict), pre_thesis, exec_review, lessons,
                        discipline, emotion, blotter_oss_key, chart_oss_url, visibility,
                    ),
                )
                res = cur.fetchone()
                print(f"✅ [MoBoCapital 战役入库成功] {res['trade_code']} ({res['realized_r_multiple']}R)")
    finally:
        conn.close()

    if not args.skip_sync:
        export_capital_frontend_json(args.web_dir)


def export_capital_frontend_json(web_dir_override: str = None):
    base_dir = Path(web_dir_override or os.getenv("MOBOCAPITAL_WEB_DIR", "/opt/mobo-stack/sites/mobocapital"))
    pub_data_dir = base_dir / "data"
    int_data_dir = base_dir / "internal"
    pub_data_dir.mkdir(parents=True, exist_ok=True)
    int_data_dir.mkdir(parents=True, exist_ok=True)

    conn = get_db_conn("capital")
    _, priv_bucket, _, _ = get_oss_buckets()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT * FROM v_strategy_performance_summary ORDER BY strategy_code;")
            strategies_perf = cur.fetchall()
            cur.execute("SELECT * FROM macro_theses WHERE status IN ('ACTIVE', 'VALIDATED') ORDER BY created_at DESC;")
            theses_all = cur.fetchall()
            cur.execute(
                """
                SELECT tr.*, sp.strategy_code, mt.thesis_code
                FROM trade_reviews tr
                JOIN strategy_playbooks sp ON tr.strategy_id = sp.id
                LEFT JOIN macro_theses mt ON tr.thesis_id = mt.id
                ORDER BY tr.entry_date DESC;
                """
            )
            trades_all = cur.fetchall()
            cur.execute("SELECT * FROM fund_incubation_milestones ORDER BY phase_number ASC, target_date ASC;")
            milestones_all = cur.fetchall()
            cur.execute("SELECT * FROM v_media_conversion_funnel;")
            media_funnel = cur.fetchall()

        public_trades, internal_trades = [], []
        for t in trades_all:
            t_int = dict(t)
            t_int.pop("embedding", None)
            if t_int.get("private_blotter_oss_key"):
                try:
                    t_int["signed_blotter_url"] = priv_bucket.sign_url("GET", t_int["private_blotter_oss_key"], 3600)
                except Exception:
                    t_int["signed_blotter_url"] = None
            internal_trades.append(t_int)
            if t["visibility"] in ("PUBLIC", "LP_PROSPECT"):
                t_pub = dict(t_int)
                t_pub.pop("private_blotter_oss_key", None)
                t_pub.pop("signed_blotter_url", None)
                public_trades.append(t_pub)

        for m in theses_all:
            m.pop("embedding", None)

        (pub_data_dir / "public-data.json").write_text(
            json.dumps(
                {
                    "generated_at": datetime.now().isoformat(),
                    "strategies_summary": strategies_perf,
                    "macro_theses": [m for m in theses_all if m["visibility"] != "INTERNAL"],
                    "trade_reviews": public_trades,
                    "incubation_milestones": [ms for ms in milestones_all if ms["visibility"] != "INTERNAL"],
                    "media_funnel": media_funnel,
                },
                default=json_serial, ensure_ascii=False, indent=2,
            ),
            encoding="utf-8",
        )
        (int_data_dir / "internal-data.json").write_text(
            json.dumps(
                {
                    "generated_at": datetime.now().isoformat(),
                    "strategies_summary": strategies_perf,
                    "macro_theses": theses_all,
                    "trade_reviews": internal_trades,
                    "incubation_milestones": milestones_all,
                    "media_funnel": media_funnel,
                },
                default=json_serial, ensure_ascii=False, indent=2,
            ),
            encoding="utf-8",
        )
        print("🚀 [MoBoCapital 前端静态数据包已同步]")
    finally:
        conn.close()


def build_parser():
    parser = argparse.ArgumentParser(
        description="MoBo Dual-Site CLI v2.1 — 莫伯资本 & 莫伯之家终端总控"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_trade = sub.add_parser("trade", help="[MoBoCapital] 录入/更新实盘交易复盘与期权归因")
    p_trade.add_argument("--from-md", type=str)
    p_trade.add_argument("--code", type=str)
    p_trade.add_argument("--strategy", type=str)
    p_trade.add_argument("--thesis", type=str)
    p_trade.add_argument("--ticker", type=str)
    p_trade.add_argument("--asset-name", type=str)
    p_trade.add_argument("--direction", type=str)
    p_trade.add_argument("--structure", type=str)
    p_trade.add_argument("--entry-date", type=str)
    p_trade.add_argument("--exit-date", type=str)
    p_trade.add_argument("--status", type=str)
    p_trade.add_argument("--init-risk", type=float)
    p_trade.add_argument("--r-multiple", type=float)
    p_trade.add_argument("--return-pct", type=float)
    p_trade.add_argument("--impact-bps", type=int)
    p_trade.add_argument("--greeks", type=str)
    p_trade.add_argument("--discipline", type=int)
    p_trade.add_argument("--emotion", type=str)
    p_trade.add_argument("--pre-thesis", type=str)
    p_trade.add_argument("--exec-review", type=str)
    p_trade.add_argument("--lessons", type=str)
    p_trade.add_argument("--blotter", type=str)
    p_trade.add_argument("--chart", type=str)
    p_trade.add_argument("--visibility", type=str)
    p_trade.add_argument("--web-dir", type=str)
    p_trade.add_argument("--skip-sync", action="store_true")

    p_sync_cap = sub.add_parser("sync-capital-web", help="[MoBoCapital] 同步导出莫伯资本前端 JSON")
    p_sync_cap.add_argument("--web-dir", type=str)

    p_media = sub.add_parser("home-media", help="[MoBoHome] 归档个人照片、视频、PDF扫描件")
    p_media.add_argument("--file", type=str)
    p_media.add_argument("--batch-dir", type=str)
    p_media.add_argument("--type", type=str, choices=["photo", "video", "scan_doc", "audio", "certificate"])
    p_media.add_argument("--title", type=str)
    p_media.add_argument("--captured-at", type=str)
    p_media.add_argument("--event-id", type=str)
    p_media.add_argument("--poster", type=str)
    p_media.add_argument("--tags", type=str)
    p_media.add_argument("--public", action="store_true")
    p_media.add_argument("--web-dir", type=str)
    p_media.add_argument("--skip-sync", action="store_true")

    p_story = sub.add_parser("home-story", help="[MoBoHome] 录入个人成长经历与故事文章")
    p_story.add_argument("--from-md", type=str)
    p_story.add_argument("--title", type=str)
    p_story.add_argument("--date", type=str)
    p_story.add_argument("--category", type=str, default="milestone")
    p_story.add_argument("--chapter", type=str)
    p_story.add_argument("--location", type=str)
    p_story.add_argument("--summary", type=str)
    p_story.add_argument("--content", type=str)
    p_story.add_argument("--importance", type=int, default=4)
    p_story.add_argument("--mood", type=int, default=8)
    p_story.add_argument("--energy", type=int, default=8)
    p_story.add_argument("--tags", type=str)
    p_story.add_argument("--attach", type=str)
    p_story.add_argument("--public", action="store_true")
    p_story.add_argument("--web-dir", type=str)
    p_story.add_argument("--skip-sync", action="store_true")

    p_habit = sub.add_parser("home-habit", help="[MoBoHome] 录入运动训练或周期复盘")
    p_habit.add_argument("--habit-type", type=str, required=True, choices=["workout", "retro"])
    p_habit.add_argument("--date", type=str)
    p_habit.add_argument("--workout-type", type=str, default="running")
    p_habit.add_argument("--duration", type=int, default=60)
    p_habit.add_argument("--distance", type=float)
    p_habit.add_argument("--hr", type=int)
    p_habit.add_argument("--rpe", type=int, default=7)
    p_habit.add_argument("--calories", type=int)
    p_habit.add_argument("--notes", type=str)
    p_habit.add_argument("--period", type=str)
    p_habit.add_argument("--period-type", type=str, default="weekly")
    p_habit.add_argument("--title", type=str)
    p_habit.add_argument("--achievements", type=str)
    p_habit.add_argument("--bottlenecks", type=str)
    p_habit.add_argument("--next-actions", type=str)
    p_habit.add_argument("--content", type=str)
    p_habit.add_argument("--public", action="store_true")
    p_habit.add_argument("--web-dir", type=str)
    p_habit.add_argument("--skip-sync", action="store_true")

    p_sync_home = sub.add_parser("sync-home-web", help="[MoBoHome] 导出 db_archive 数据至 MoBoHome.com 前端 JSON")
    p_sync_home.add_argument("--web-dir", type=str)

    return parser


if __name__ == "__main__":
    parser = build_parser()
    cli_args = parser.parse_args()

    if cli_args.command == "trade":
        upsert_trade_review(cli_args)
    elif cli_args.command == "sync-capital-web":
        export_capital_frontend_json(cli_args.web_dir)
    elif cli_args.command == "home-media":
        handle_home_media_cmd(cli_args)
    elif cli_args.command == "home-story":
        handle_home_story_cmd(cli_args)
    elif cli_args.command == "home-habit":
        handle_home_habit_cmd(cli_args)
    elif cli_args.command == "sync-home-web":
        export_home_frontend_json(cli_args.web_dir)