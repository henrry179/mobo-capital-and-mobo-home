# -*- coding: utf-8 -*-
"""重复文件精确扫描（SHA-256）。

策略：只对“存在同尺寸文件”的候选集做完整哈希；按哈希分组，
每组保留一个建议 canonical，其余计为冗余。输出 duplicates.csv
与 duplicate-summary.json。只读扫描，不删除任何文件。
"""
from __future__ import annotations

import hashlib
import json
import os
import sys
from collections import defaultdict
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent
DEFAULT_CSV = Path(os.environ.get("TEMP", ".")) / "mobo_inventory.csv"
CHUNK = 4 * 1024 * 1024


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            b = f.read(CHUNK)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def canonical_score(path: str) -> int:
    p = path.replace("/", "\\")
    low = p.lower()
    score = 0
    if p.startswith(("ITPM原稿内容\\", "AIGC原稿\\", "ReadingBooks\\")):
        score += 100
    if "\\.git\\" in low or low.startswith(".git\\"):
        score -= 100
    if "\\hermes\\backups\\" in low:
        score -= 60
    if "\\01_原始文档\\" in p:
        score -= 30
    if "\\workfiles\\data\\input\\" in low:
        score -= 20
    if "\\mobobrain-itpm-archive\\01-md-" in p:
        score += 40
    if "\\mobobrain-assets\\covers\\" in p:
        score += 20
    if "\\06-images-" in p:
        score += 5
    score += max(0, 12 - p.count("\\"))
    return score


def main(csv_path: Path):
    df = pd.read_csv(csv_path)
    df["size"] = df["size"].astype("int64")
    df = df[df["size"] >= 1024].copy()
    # 只保留有同尺寸同伴的文件
    counts = df.groupby("size")["size"].transform("size")
    cand = df[counts > 1].copy()
    print(f"candidates: {len(cand):,} files / {cand['size'].sum()/1024**3:.2f} GiB")

    hashes: dict[str, list[dict]] = defaultdict(list)
    failed = []
    for i, row in enumerate(cand.itertuples(index=False), 1):
        p = Path(row.path)
        try:
            digest = sha256(p)
        except Exception as exc:  # noqa: BLE001
            failed.append({"path": row.path, "error": str(exc)})
            continue
        hashes[digest].append({"path": row.path, "size": int(row.size), "name": row.name, "ext": row.ext, "mtime": row.mtime})
        if i % 5000 == 0:
            print(f"  hashed {i:,}/{len(cand):,}")

    groups = []
    for digest, items in hashes.items():
        if len(items) < 2:
            continue
        size = items[0]["size"]
        items = sorted(items, key=lambda x: (-canonical_score(x["path"]), len(x["path"]), x["path"]))
        groups.append({
            "sha256": digest,
            "size": size,
            "count": len(items),
            "redundant_bytes": size * (len(items) - 1),
            "canonical": items[0]["path"],
            "ext": items[0]["ext"],
            "paths": [x["path"] for x in items],
        })

    groups.sort(key=lambda g: g["redundant_bytes"], reverse=True)
    total_redundant = sum(g["redundant_bytes"] for g in groups)
    total_dup_files = sum(g["count"] - 1 for g in groups)
    by_ext = defaultdict(lambda: {"groups": 0, "files": 0, "bytes": 0})
    for g in groups:
        e = g["ext"] or "(none)"
        by_ext[e]["groups"] += 1
        by_ext[e]["files"] += g["count"] - 1
        by_ext[e]["bytes"] += g["redundant_bytes"]

    # CSV：一行一组；paths 用 | 分隔，便于人工核对
    rows = []
    for g in groups:
        rows.append({
            "sha256": g["sha256"],
            "bytes": g["size"],
            "copies": g["count"],
            "redundant_bytes": g["redundant_bytes"],
            "ext": g["ext"],
            "canonical": g["canonical"],
            "duplicates": " | ".join(g["paths"][1:]),
        })
    out = pd.DataFrame(rows)
    out.to_csv(HERE / "duplicates.csv", index=False, encoding="utf-8-sig")

    summary = {
        "candidate_files": int(len(cand)),
        "candidate_bytes": int(cand["size"].sum()),
        "duplicate_groups": len(groups),
        "redundant_files": int(total_dup_files),
        "redundant_bytes": int(total_redundant),
        "redundant_gb": round(total_redundant / 1024 ** 3, 3),
        "failed": failed,
        "by_ext": [
            {"ext": e, **v, "gb": round(v["bytes"] / 1024 ** 3, 3)}
            for e, v in sorted(by_ext.items(), key=lambda kv: kv[1]["bytes"], reverse=True)
        ],
        "top_groups": [
            {
                "sha256": g["sha256"],
                "bytes": g["size"],
                "copies": g["count"],
                "redundant_bytes": g["redundant_bytes"],
                "ext": g["ext"],
                "canonical": g["canonical"],
                "sample_duplicates": g["paths"][1:6],
            }
            for g in groups[:20]
        ],
    }
    (HERE / "duplicate-summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"duplicate groups={len(groups):,} redundant_files={total_dup_files:,} redundant={summary['redundant_gb']:.2f} GiB")
    print("by ext:", ", ".join(f"{x['ext']}:{x['gb']:.2f}G" for x in summary["by_ext"][:10]))
    if failed:
        print(f"failed={len(failed)} (see summary.json)")


if __name__ == "__main__":
    main(Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_CSV)
