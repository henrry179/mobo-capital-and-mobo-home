"""文件处理：哈希、MIME、缩略图、PDF 文本、EXIF。"""
from __future__ import annotations

import hashlib
import mimetypes
import os
import re
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any

try:
    from PIL import Image, ImageOps
except ImportError:  # pragma: no cover
    Image = None  # type: ignore
    ImageOps = None  # type: ignore

try:
    from pypdf import PdfReader
except ImportError:  # pragma: no cover
    PdfReader = None  # type: ignore


def sha256_file(path: str | Path, chunk_size: int = 1024 * 1024) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(chunk_size), b""):
            h.update(chunk)
    return h.hexdigest()


def guess_mime(path: str | Path) -> str:
    mime, _ = mimetypes.guess_type(str(path))
    return mime or "application/octet-stream"


def safe_filename(name: str) -> str:
    base = os.path.basename(name)
    base = re.sub(r"[^A-Za-z0-9._\-\u4e00-\u9fff]+", "_", base).strip("._")
    return base or "file"


def category_prefix(category: str, when: datetime | None = None) -> str:
    when = when or datetime.now()
    mapping = {
        "PHOTO": f"photo/{when:%Y/%m}/",
        "VIDEO": f"video/{when:%Y/%m}/",
        "SCAN_DOC": f"scan_doc/{when:%Y/%m}/",
        "CERTIFICATE": f"documents/certificate/{when:%Y}/",
        "MEDICAL": f"documents/medical/{when:%Y}/",
        "OTHER": f"other/{when:%Y/%m}/",
    }
    return mapping.get(category.upper(), f"other/{when:%Y/%m}/")


def object_keys(category: str, path: str | Path, digest: str) -> tuple[str, str | None]:
    """返回 (原图 key, 缩略图 key)。缩略图 key 对非图片为 None。"""
    prefix = category_prefix(category)
    filename = safe_filename(str(path))
    stem = Path(filename).stem
    key = f"{prefix}{digest[:16]}-{filename}"
    thumb = None
    if is_image(path):
        thumb = f"thumbnails/{datetime.now():%Y/%m}/{digest[:16]}-{stem}.webp"
    return key, thumb


def is_image(path: str | Path) -> bool:
    return guess_mime(path).startswith("image/")


def is_pdf(path: str | Path) -> bool:
    return guess_mime(path) == "application/pdf" or str(path).lower().endswith(".pdf")


def image_info(path: str | Path) -> dict[str, Any]:
    if Image is None:
        return {}
    try:
        with Image.open(path) as img:
            info: dict[str, Any] = {
                "width": img.width,
                "height": img.height,
                "format": img.format,
                "mode": img.mode,
            }
            exif = img.getexif()
            if exif:
                # 36867 = DateTimeOriginal, 306 = DateTime
                raw = exif.get(36867) or exif.get(306)
                if raw:
                    info["exif_datetime"] = str(raw)
            return info
    except Exception:  # noqa: BLE001
        return {}


def make_thumbnail(path: str | Path, max_size: int = 800, quality: int = 82) -> tuple[str | None, dict[str, Any]]:
    """生成 WebP 缩略图到临时文件；调用方负责删除。"""
    if Image is None or ImageOps is None or not is_image(path):
        return None, {}
    try:
        with Image.open(path) as img:
            img = ImageOps.exif_transpose(img)
            info = {"width": img.width, "height": img.height, "format": img.format}
            img.thumbnail((max_size, max_size), Image.LANCZOS)
            if img.mode not in ("RGB", "RGBA"):
                img = img.convert("RGB")
            fd, tmp = tempfile.mkstemp(prefix="mobo-thumb-", suffix=".webp")
            os.close(fd)
            img.save(tmp, format="WEBP", quality=quality, method=6)
            return tmp, info
    except Exception:  # noqa: BLE001
        return None, {}


def extract_pdf_text(path: str | Path, max_pages: int = 50) -> str:
    if PdfReader is None or not is_pdf(path):
        return ""
    try:
        reader = PdfReader(str(path))
        parts: list[str] = []
        for page in reader.pages[:max_pages]:
            try:
                text = page.extract_text() or ""
            except Exception:  # noqa: BLE001
                continue
            if text.strip():
                parts.append(text.strip())
        return "\n\n".join(parts)
    except Exception:  # noqa: BLE001
        return ""


def parse_exif_date(info: dict[str, Any]) -> str | None:
    raw = info.get("exif_datetime")
    if not raw:
        return None
    for fmt in ("%Y:%m:%d %H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y:%m:%d"):
        try:
            return datetime.strptime(str(raw), fmt).date().isoformat()
        except ValueError:
            continue
    return None


def human_size(num: int | float) -> str:
    n = float(num)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(n) < 1024.0:
            return f"{n:.1f} {unit}" if unit != "B" else f"{int(n)} B"
        n /= 1024.0
    return f"{n:.1f} PB"
