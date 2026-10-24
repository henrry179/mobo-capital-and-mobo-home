# -*- coding: utf-8 -*-
"""对已生成的 duplicates.csv 做二次汇总（不重新哈希）。"""
from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent


def top_of(path: str) -> str:
    p = str(path)
    return p.split("\\")[0] if "\\" in p else "(root)"


def p2_of(path: str) -> str:
    parts = str(path).split("\\")
    return "\\".join(parts[:2]) if len(parts) > 2 else (parts[0] if parts else "(root)")


def main():
    df = pd.read_csv(HERE / "duplicates.csv")
    by_top = defaultdict(lambda: {"files": 0, "bytes": 0})
    by_p2 = defaultdict(lambda: {"files": 0, "bytes": 0})
    for row in df.itertuples(index=False):
        dups = [x for x in str(row.duplicates).split(" | ") if x]
        for p in dups:
            for bucket, key in ((by_top, top_of(p)), (by_p2, p2_of(p))):
                bucket[key]["files"] += 1
                bucket[key]["bytes"] += int(row.bytes)
    out = {
        "by_top": sorted(({"path": k, **v, "gb": round(v["bytes"] / 1024 ** 3, 3)} for k, v in by_top.items()), key=lambda x: x["bytes"], reverse=True),
        "by_p2": sorted(({"path": k, **v, "gb": round(v["bytes"] / 1024 ** 3, 3)} for k, v in by_p2.items()), key=lambda x: x["bytes"], reverse=True),
    }
    (HERE / "duplicate-by-folder.json").write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(out["by_top"][:8], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
