"""公私域物理脱敏与静态数据包导出（红线四 / ADR-0009）。

两个前台（莫伯资本 MoBoCapital、莫伯之家 MoBoHome）都是**静态 HTML + 预生成 JSON**
架构，服务端不持有业务内存（红线一）。因此 JSON 文件本身就是对外暴露面，
必须在**写盘之前**完成物理脱敏，而不是靠 Caddy 或前端隐藏。

规则（与 `CLAUDE.md` 红线四一致）：

1. 生成 ``data/public-data.json`` 时：
   - 物理删除 ``private_blotter_oss_key`` / ``signed_blotter_url`` /
     ``private_attachment_oss_key`` / ``oss_object_key`` / ``oss_thumbnail_key`` /
     ``signed_url`` 等私有字段；
   - 物理剔除 ``visibility = 'INTERNAL'`` 的记录。
2. 生成 ``data/public-home-data.json`` 时：
   - 物理剔除 ``is_sensitive = TRUE`` 的记录；
   - 同样删除私有 OSS Key 字段。
3. ``internal/internal-data.json`` 存放全量数据与 OSS 临时签名链接，
   必须由 Caddy ``/internal/*`` 的 BasicAuth 保护，禁止放到 ``data/`` 目录。

本模块只依赖标准库，便于在没有数据库的环境下做单元测试。
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

# 任何公域数据包中都不得出现的字段
PRIVATE_FIELDS: frozenset[str] = frozenset(
    {
        "private_blotter_oss_key",
        "signed_blotter_url",
        "private_attachment_oss_key",
        "oss_object_key",
        "oss_thumbnail_key",
        "signed_url",
        "access_key_id",
        "access_key_secret",
        "password",
        "secret",
    }
)

# 公域可见级别；INTERNAL 仅允许出现在 internal 包
PUBLIC_VISIBILITIES: tuple[str, ...] = ("PUBLIC", "LP_PROSPECT")
INTERNAL_VISIBILITY = "INTERNAL"


def strip_private_fields(record: Mapping[str, Any]) -> dict[str, Any]:
    """递归删除私有字段，返回新字典（不修改入参）。"""
    if not isinstance(record, Mapping):
        return record  # type: ignore[return-value]
    cleaned: dict[str, Any] = {}
    for key, value in record.items():
        if key in PRIVATE_FIELDS:
            continue
        if isinstance(value, Mapping):
            cleaned[key] = strip_private_fields(value)
        elif isinstance(value, (list, tuple)):
            cleaned[key] = [
                strip_private_fields(item) if isinstance(item, Mapping) else item for item in value
            ]
        else:
            cleaned[key] = value
    return cleaned


def filter_visibility(records: Iterable[Mapping[str, Any]]) -> list[dict[str, Any]]:
    """剔除 INTERNAL 记录（公域包）。"""
    return [
        strip_private_fields(r)
        for r in records
        if str(r.get("visibility", "PUBLIC")).upper() != INTERNAL_VISIBILITY
    ]


def filter_sensitive(records: Iterable[Mapping[str, Any]]) -> list[dict[str, Any]]:
    """剔除 is_sensitive = TRUE 的记录（莫伯之家公域包）。"""
    return [strip_private_fields(r) for r in records if not r.get("is_sensitive")]


def build_public_capital_payload(
    *,
    theses: Sequence[Mapping[str, Any]] = (),
    playbooks: Sequence[Mapping[str, Any]] = (),
    trades: Sequence[Mapping[str, Any]] = (),
    publications: Sequence[Mapping[str, Any]] = (),
    metrics: Sequence[Mapping[str, Any]] = (),
    terminal: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """构造莫伯资本公域数据包（PUBLIC + LP_PROSPECT）。"""
    payload: dict[str, Any] = {
        "macro_theses": filter_visibility(theses),
        "strategy_playbooks": filter_visibility(playbooks),
        "trade_reviews": filter_visibility(trades),
        "publications": filter_visibility(publications),
        "media_metrics": list(metrics),
    }
    if terminal is not None:
        payload["terminal"] = strip_private_fields(terminal)
    return payload


def build_public_home_payload(
    *,
    timeline: Sequence[Mapping[str, Any]] = (),
    assets: Sequence[Mapping[str, Any]] = (),
    retrospectives: Sequence[Mapping[str, Any]] = (),
    workouts: Sequence[Mapping[str, Any]] = (),
) -> dict[str, Any]:
    """构造莫伯之家公域数据包（剔除 is_sensitive 记录）。"""
    return {
        "timeline_events": filter_sensitive(timeline),
        "archive_assets": filter_sensitive(assets),
        "retrospectives": filter_sensitive(retrospectives),
        "workouts": filter_sensitive(workouts),
    }


def build_internal_capital_payload(
    *,
    theses: Sequence[Mapping[str, Any]] = (),
    playbooks: Sequence[Mapping[str, Any]] = (),
    trades: Sequence[Mapping[str, Any]] = (),
    publications: Sequence[Mapping[str, Any]] = (),
    metrics: Sequence[Mapping[str, Any]] = (),
) -> dict[str, Any]:
    """构造内网驾驶舱数据包：保留全量字段（含私有 OSS Key），仅受 BasicAuth 保护。"""
    return {
        "macro_theses": [dict(r) for r in theses],
        "strategy_playbooks": [dict(r) for r in playbooks],
        "trade_reviews": [dict(r) for r in trades],
        "publications": [dict(r) for r in publications],
        "media_metrics": [dict(r) for r in metrics],
    }


def write_json(path: str | Path, payload: Mapping[str, Any]) -> Path:
    """原子写 JSON（先写临时文件再替换，避免前端读到半截文件）。"""
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(target.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
    tmp.replace(target)
    return target


def _walk(node: Any, path: str = "") -> Iterable[tuple[str, str, Any]]:
    if isinstance(node, Mapping):
        for key, value in node.items():
            child = f"{path}.{key}" if path else str(key)
            yield child, str(key), value
            yield from _walk(value, child)
    elif isinstance(node, (list, tuple)):
        for index, item in enumerate(node):
            child = f"{path}[{index}]"
            yield from _walk(item, child)


def audit_payload(payload: Mapping[str, Any]) -> dict[str, Any]:
    """脱敏审计：返回违规字段路径与 INTERNAL 痕迹，供 CI/发布前门禁使用。"""
    violations: list[str] = []
    internal_hits: list[str] = []
    for child, key, value in _walk(payload):
        if key in PRIVATE_FIELDS:
            violations.append(child)
        if isinstance(value, str) and value.strip().upper() == INTERNAL_VISIBILITY:
            internal_hits.append(child)
    return {
        "ok": not violations and not internal_hits,
        "private_field_violations": violations,
        "internal_markers": internal_hits,
    }
