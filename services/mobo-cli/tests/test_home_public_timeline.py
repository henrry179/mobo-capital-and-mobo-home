from __future__ import annotations

from mobo_cli.site_sync import (
    _home_public,
    _home_public_gallery,
    _home_public_readings,
    _home_public_timeline,
    _to_reading_book,
    _to_timeline_story,
)


def test_public_timeline_excludes_restricted() -> None:
    rows = [
        {"event_id": "1", "privacy": "PUBLIC", "title": "公域", "domain": "FAMILY_LIFE",
         "event_type": "milestone", "occurred_at": "2026-01-01", "metrics_payload": {
             "life_chapter": "湖北·归航与长期筑基"}},
        {"event_id": "2", "privacy": "RESTRICTED", "title": "训练", "domain": "FITNESS_HEALTH",
         "event_type": "workout", "occurred_at": "2026-01-02", "metrics_payload": {}},
        {"event_id": "3", "privacy": "PRIVATE", "title": "私密", "domain": "FAMILY_LIFE",
         "event_type": "note", "occurred_at": "2026-01-03", "metrics_payload": {}},
    ]
    public_tl = _home_public_timeline(rows)
    assert [r["event_id"] for r in public_tl] == ["1"]
    # 图库口径仍可含 RESTRICTED
    assert {r["event_id"] for r in _home_public(rows)} == {"1", "2"}


def test_story_keeps_editorial_slug_and_media() -> None:
    story = _to_timeline_story(
        {
            "event_id": "uuid-1",
            "title": "武汉三线融合",
            "summary": "摘要",
            "domain": "FAMILY_LIFE",
            "event_type": "milestone",
            "occurred_at": "2026-10-07T12:00:00+08:00",
            "importance_score": 5,
            "energy_impact": 5,
            "tags": ["三线融合"],
            "metrics_payload": {
                "editorial_slug": "home-2026-1007",
                "life_chapter": "湖北·归航与长期筑基",
                "mood_score": 9,
                "content_markdown": "正文",
                "attached_media": [{"title": "东湖", "public_thumb_url": "https://x"}],
            },
        }
    )
    assert story["id"] == "home-2026-1007"
    assert story["metadata"]["life_chapter"] == "湖北·归航与长期筑基"
    assert story["metadata"]["content_markdown"] == "正文"
    assert story["attached_media"][0]["title"] == "东湖"


def test_gallery_public_only() -> None:
    rows = [
        {"asset_id": "1", "privacy": "PUBLIC", "title": "东湖"},
        {"asset_id": "2", "privacy": "RESTRICTED", "title": "沙盒影像 1"},
    ]
    assert [r["asset_id"] for r in _home_public_gallery(rows)] == ["1"]


def test_readings_require_public_portal_tag() -> None:
    rows = [
        {"item_id": "1", "title": "原则", "tags": ["public_portal", "FINANCE"], "authors": ["Dalio"], "rating": 5},
        {"item_id": "2", "title": "沙盒阅读 01", "tags": [], "authors": ["A"], "rating": 8},
    ]
    kept = _home_public_readings(rows)
    assert len(kept) == 1
    book = _to_reading_book(kept[0])
    assert book["category"] == "FINANCE"
    assert book["title"] == "原则"
