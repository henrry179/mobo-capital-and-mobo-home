from __future__ import annotations

import hashlib
from pathlib import Path

from mobo_cli.media import category_prefix, human_size, object_keys, safe_filename, sha256_file


def test_sha256_file(tmp_path: Path) -> None:
    p = tmp_path / "a.txt"
    p.write_bytes(b"mobo")
    digest = sha256_file(p)
    assert len(digest) == 64
    assert digest == hashlib.sha256(b"mobo").hexdigest()


def test_safe_filename_keeps_chinese_and_strips_unsafe() -> None:
    assert safe_filename("a b?.jpg") == "a_b_.jpg"
    assert safe_filename("读书笔记.md") == "读书笔记.md"


def test_category_prefix() -> None:
    from datetime import datetime

    assert category_prefix("PHOTO", datetime(2026, 10, 18)).startswith("photo/2026/10/")
    assert category_prefix("VIDEO", datetime(2026, 10, 18)).startswith("video/2026/10/")
    assert category_prefix("CERTIFICATE", datetime(2026, 10, 18)).startswith("documents/certificate/2026/")


def test_object_keys_image_has_thumbnail() -> None:
    key, thumb = object_keys("PHOTO", "x.jpg", "abc123" * 11)
    assert key.startswith("photo/")
    assert key.endswith("-x.jpg")
    assert thumb is not None and thumb.startswith("thumbnails/") and thumb.endswith(".webp")


def test_object_keys_pdf_no_thumbnail() -> None:
    key, thumb = object_keys("SCAN_DOC", "x.pdf", "def456" * 11)
    assert key.startswith("scan_doc/")
    assert thumb is None


def test_human_size() -> None:
    assert human_size(0) == "0 B"
    assert human_size(1024) == "1.0 KB"
