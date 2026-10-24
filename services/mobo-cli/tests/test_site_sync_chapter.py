from __future__ import annotations

from mobo_cli.site_sync import _life_chapter_from_row, _to_timeline_story


def test_domain_maps_to_chinese_chapter() -> None:
    assert _life_chapter_from_row({"domain": "FITNESS_HEALTH"}, {}) == "湖北·归航与长期筑基"
    assert _life_chapter_from_row({"domain": "CAREER_WORK"}, {}) == "上海·供应链深耕"


def test_metrics_chapter_wins() -> None:
    assert (
        _life_chapter_from_row({"domain": "FITNESS_HEALTH"}, {"life_chapter": "北上深·历练期"})
        == "北上深·历练期"
    )


def test_timeline_story_carries_mapped_chapter() -> None:
    story = _to_timeline_story(
        {
            "event_id": "e1",
            "title": "训练",
            "summary": "力量课",
            "domain": "FITNESS_HEALTH",
            "event_type": "workout",
            "occurred_at": "2026-10-01T08:00:00+08:00",
            "importance_score": 5,
            "energy_impact": 6,
            "tags": ["gym"],
            "metrics_payload": {},
        }
    )
    assert story["metadata"]["life_chapter"] == "湖北·归航与长期筑基"
    assert story["metadata"]["domain"] == "FITNESS_HEALTH"
