"""Markdown 复盘解析与简单计算。"""
from __future__ import annotations

import re
from typing import Any

HEADING_MAP: list[tuple[tuple[str, ...], str]] = [
    (("初始假设", "假设", "hypothesis", "initial hypothesis"), "initial_hypothesis"),
    (("实际执行", "执行", "execution", "what happened"), "actual_execution"),
    (("根因分析", "归因", "root cause", "root cause analysis"), "root_cause_analysis"),
    (("原则迭代", "原则", "codified principles", "principles"), "codified_principles"),
    (("kpi", "指标", "kpi snapshot"), "kpi_snapshot"),
    (("行动项", "行动", "action items", "actions"), "action_items"),
]


def _norm(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip().lower())


def _section_key(heading: str) -> str | None:
    h = _norm(heading)
    for aliases, key in HEADING_MAP:
        if any(alias in h for alias in aliases):
            return key
    return None


def parse_kv_lines(lines: list[str]) -> dict[str, Any]:
    """把 `- key: value` 或 `- key=value` 解析为 dict。"""
    out: dict[str, Any] = {}
    for line in lines:
        item = re.sub(r"^\s*[-*+]\s*", "", line).strip()
        if not item:
            continue
        m = re.match(r"^([^:=：]+)\s*[:=：]\s*(.+)$", item)
        if not m:
            continue
        key = m.group(1).strip()
        raw = m.group(2).strip()
        value: Any = raw
        if re.fullmatch(r"-?\d+", raw):
            value = int(raw)
        elif re.fullmatch(r"-?\d+\.\d+", raw):
            value = float(raw)
        elif raw.lower() in {"true", "false", "yes", "no"}:
            value = raw.lower() in {"true", "yes"}
        out[key] = value
    return out


def parse_action_items(lines: list[str]) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for line in lines:
        item = re.sub(r"^\s*[-*+]\s*", "", line).strip()
        if not item:
            continue
        entry: dict[str, Any] = {"text": item}
        m = re.search(r"(?:owner|负责人)\s*[:：]\s*([^;；]+)", item)
        if m:
            entry["owner"] = m.group(1).strip()
        m = re.search(r"(?:due|截止)\s*[:：]\s*([^;；]+)", item)
        if m:
            entry["due"] = m.group(1).strip()
        items.append(entry)
    return items


def parse_retro_markdown(text: str) -> dict[str, Any]:
    """按二级标题解析复盘；未知标题内容并入 actual_execution。"""
    sections: dict[str, list[str]] = {}
    current = "actual_execution"
    for line in text.splitlines():
        m = re.match(r"^#{1,6}\s+(.+?)\s*$", line)
        if m:
            key = _section_key(m.group(1))
            current = key or "actual_execution"
            sections.setdefault(current, [])
            continue
        sections.setdefault(current, []).append(line)

    def joined(key: str) -> str | None:
        value = "\n".join(sections.get(key, [])).strip()
        return value or None

    result: dict[str, Any] = {
        "initial_hypothesis": joined("initial_hypothesis"),
        "actual_execution": joined("actual_execution"),
        "root_cause_analysis": joined("root_cause_analysis"),
        "codified_principles": joined("codified_principles"),
        "kpi_snapshot": parse_kv_lines(sections.get("kpi_snapshot", [])),
        "action_items": parse_action_items(sections.get("action_items", [])),
    }
    return result


def pace_sec_per_km(distance_meters: int | None, duration_minutes: int | None) -> int | None:
    if not distance_meters or not duration_minutes or distance_meters <= 0:
        return None
    return int(round(duration_minutes * 60 / (distance_meters / 1000.0)))
