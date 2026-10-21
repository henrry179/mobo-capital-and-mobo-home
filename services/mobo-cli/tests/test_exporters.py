from __future__ import annotations

import json
from pathlib import Path

from mobo_cli.exporters import (
    audit_payload,
    build_internal_capital_payload,
    build_public_capital_payload,
    build_public_home_payload,
    filter_sensitive,
    filter_visibility,
    strip_private_fields,
    write_json,
)


def test_strip_private_fields_is_recursive() -> None:
    record = {
        "title": "组合周报",
        "private_blotter_oss_key": "blotters/2026/10/x.pdf",
        "nested": {"signed_url": "https://oss/...?sig=1", "value": 42},
        "items": [{"oss_object_key": "photo/a.jpg", "id": 1}],
    }
    cleaned = strip_private_fields(record)
    assert "private_blotter_oss_key" not in cleaned
    assert "signed_url" not in cleaned["nested"]
    assert cleaned["nested"]["value"] == 42
    assert "oss_object_key" not in cleaned["items"][0]
    # 原对象不被修改
    assert "private_blotter_oss_key" in record


def test_filter_visibility_drops_internal() -> None:
    records = [
        {"id": 1, "visibility": "PUBLIC"},
        {"id": 2, "visibility": "LP_PROSPECT"},
        {"id": 3, "visibility": "INTERNAL", "private_blotter_oss_key": "k"},
    ]
    kept = filter_visibility(records)
    assert [r["id"] for r in kept] == [1, 2]
    assert all("private_blotter_oss_key" not in r for r in kept)


def test_filter_sensitivity_drops_sensitive() -> None:
    records = [
        {"id": 1, "is_sensitive": False},
        {"id": 2, "is_sensitive": True},
        {"id": 3},
    ]
    kept = filter_sensitive(records)
    assert [r["id"] for r in kept] == [1, 3]


def test_public_capital_payload_is_clean() -> None:
    payload = build_public_capital_payload(
        theses=[{"thesis_code": "T1", "visibility": "PUBLIC"},
                {"thesis_code": "T2", "visibility": "INTERNAL"}],
        trades=[{"trade_code": "X1", "visibility": "PUBLIC",
                 "private_blotter_oss_key": "blotters/a.pdf"}],
    )
    assert len(payload["macro_theses"]) == 1
    assert "private_blotter_oss_key" not in payload["trade_reviews"][0]
    assert audit_payload(payload)["ok"] is True


def test_public_home_payload_is_clean() -> None:
    payload = build_public_home_payload(
        timeline=[{"event_id": "e1"}, {"event_id": "e2", "is_sensitive": True}],
    )
    assert len(payload["timeline_events"]) == 1


def test_internal_payload_keeps_private_fields() -> None:
    payload = build_internal_capital_payload(
        trades=[{"trade_code": "X1", "private_blotter_oss_key": "blotters/a.pdf"}]
    )
    assert payload["trade_reviews"][0]["private_blotter_oss_key"] == "blotters/a.pdf"
    assert audit_payload(payload)["ok"] is False  # 内网包故意含敏感字段


def test_audit_detects_violations() -> None:
    result = audit_payload({"a": {"private_blotter_oss_key": "x"}})
    assert result["ok"] is False
    assert result["private_field_violations"]


def test_write_json_is_atomic_and_utf8(tmp_path: Path) -> None:
    target = tmp_path / "data" / "public-data.json"
    write_json(target, {"标题": "莫伯资本", "n": 1})
    assert target.exists()
    payload = json.loads(target.read_text(encoding="utf-8"))
    assert payload["标题"] == "莫伯资本"
    assert not (tmp_path / "data" / "public-data.json.tmp").exists()
