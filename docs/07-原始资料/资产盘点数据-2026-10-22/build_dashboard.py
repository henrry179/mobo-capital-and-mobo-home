# -*- coding: utf-8 -*-
"""把盘点聚合数据注入单文件 HTML 仪表板。"""
from __future__ import annotations

import json
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent
DOCS = HERE.parent  # docs/07-原始资料
OUT = DOCS / "莫伯双站内容资产双维盘点仪表板.html"
TEMPLATE = HERE / "dashboard_template.html"


def main():
    summary = json.loads((HERE / "summary.json").read_text(encoding="utf-8"))
    dups = json.loads((HERE / "duplicate-summary.json").read_text(encoding="utf-8"))
    dup_folder = json.loads((HERE / "duplicate-by-folder.json").read_text(encoding="utf-8"))
    launch = json.loads((HERE / "launch-packages.json").read_text(encoding="utf-8"))
    sync5 = json.loads((HERE / "sync-v5.json").read_text(encoding="utf-8"))

    p2 = pd.read_csv(HERE / "folder-size-level2.csv").to_dict("records")
    p3 = pd.read_csv(HERE / "folder-size-level3.csv").head(120).to_dict("records")

    data = {
        "meta": {
            "date": summary["generated_at"],
            "total_gb": summary["total_gb"],
            "total_bytes": summary["total_bytes"],
            "total_files": summary["total_files"],
            "effective_gb": summary["effective_gb"],
            "effective_share": summary["effective_share"],
            "temp_files": summary["temp"]["files"],
            "git_gb": summary["git"]["gb"],
            "backup": summary["backup"],
        },
        "top": summary["top"],
        "p2": p2,
        "p3": p3,
        "categories": summary["categories"],
        "category_order": summary.get("category_order", []),
        "dest": summary["dest"],
        "dest_categories": summary["dest_categories"],
        "cross": summary["cross"],
        "category_folders": summary["category_folders"],
        "top_files": summary["top_files"][:24],
        "backup_snapshots": summary["backup_snapshots"],
        "duplicates": {
            "groups": dups["duplicate_groups"],
            "redundant_files": dups["redundant_files"],
            "redundant_gb": dups["redundant_gb"],
            "by_ext": dups["by_ext"][:10],
            "top_groups": dups["top_groups"][:10],
        },
        "dup_by_folder": dup_folder,
        "launch": {
            "total": launch["total"],
            "excluded": launch["excluded"],
            "remaining": launch["remaining"],
        },
        "syncv5": sync5,
    }

    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")
    html = TEMPLATE.read_text(encoding="utf-8").replace("/*__DATA__*/", payload)
    OUT.write_text(html, encoding="utf-8")
    (HERE / "dashboard-data.json").write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"written: {OUT} ({OUT.stat().st_size/1024:.1f} KB)")


if __name__ == "__main__":
    main()
