# -*- coding: utf-8 -*-
"""v5 口径：保留原件、不转换；MoBoBrain 与 01-影视库 本地只读；其余同步。"""
from __future__ import annotations

import json
import os
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent
CSV = Path(os.environ["TEMP"]) / "mobo_inventory_20261023.csv"
CAT = {
    ".doc": "Word", ".docx": "Word", ".docm": "Word", ".rtf": "Word", ".odt": "Word",
    ".pdf": "PDF", ".md": "Markdown", ".markdown": "Markdown", ".txt": "文本", ".log": "文本", ".rst": "文本",
    ".jpg": "图片", ".jpeg": "图片", ".png": "图片", ".webp": "图片", ".gif": "图片", ".bmp": "图片",
    ".svg": "图片", ".tif": "图片", ".tiff": "图片", ".heic": "图片", ".ico": "图片",
    ".ppt": "演示/表格", ".pptx": "演示/表格", ".xls": "演示/表格", ".xlsx": "演示/表格",
    ".csv": "演示/表格", ".tsv": "演示/表格", ".ods": "演示/表格",
    ".zip": "压缩包", ".7z": "压缩包", ".rar": "压缩包", ".tar": "压缩包", ".gz": "压缩包",
    ".tgz": "压缩包", ".bz2": "压缩包", ".xz": "压缩包", ".zst": "压缩包",
    ".ttf": "字体", ".otf": "字体", ".woff": "字体", ".woff2": "字体",
    ".py": "代码/配置", ".js": "代码/配置", ".ts": "代码/配置", ".html": "代码/配置", ".css": "代码/配置",
    ".json": "代码/配置", ".yml": "代码/配置", ".yaml": "代码/配置", ".sh": "代码/配置",
    ".sql": "代码/配置", ".ipynb": "代码/配置", ".toml": "代码/配置", ".ini": "代码/配置",
    ".xml": "代码/配置", ".env": "代码/配置",
}
TEXT = {"Word", "PDF", "Markdown", "演示/表格", "文本"}


def cat(ext: str, name: str) -> str:
    if name.startswith("~$") or name.startswith("._"):
        return "临时/系统"
    return CAT.get((ext or "").lower(), "其他")


def group(frame, key):
    g = frame.groupby(key).agg(files=("size", "size"), bytes=("size", "sum")).reset_index()
    g["gb"] = (g["bytes"] / 1024 ** 3).round(4)
    return g.sort_values("bytes", ascending=False)


def main():
    df = pd.read_csv(CSV)
    df["size"] = df["size"].astype("int64")
    df["name"] = df["name"].fillna("").astype(str)
    df["path"] = df["path"].fillna("").astype(str)
    df["ext"] = df["ext"].fillna("").astype(str)
    df["category"] = [cat(e, n) for e, n in zip(df["ext"], df["name"])]
    p = df["path"].str.replace("/", "\\", regex=False)

    video = p.str.contains(r"\\PodcastPlayBooks\\Videos\\|\\07-鬼畜视频系列\\", regex=True)
    audio = p.str.contains(r"\\05-MP3-合成音频\\", regex=True)
    git = p.str.contains(r"\\\.git\\", regex=True) | p.str.startswith(".git\\")
    backup = p.str.startswith("hermes-migration\\henrry-push\\hermes\\backups\\", na=False)
    cache = p.str.contains(r"\\__(?:pycache|pytest_cache|mypy_cache)__\\|\\node_modules\\|\\\.venv\\", regex=True)
    temp = df["category"].eq("临时/系统")

    df["excluded"] = video | audio | git | backup
    df["exclude_reason"] = ""
    df.loc[video, "exclude_reason"] = "视频（排除）"
    df.loc[audio, "exclude_reason"] = "音频（排除）"
    df.loc[git, "exclude_reason"] = "Git（排除）"
    df.loc[backup, "exclude_reason"] = "状态快照（排除）"

    # 本地只读：MoBoBrain 完整目录 + MoBo-Capital-Goals/01-影视库
    mbrain = p.str.startswith("hermes-migration\\henrry-push\\MoBoBrain-ITPM-Archive", na=False)
    film = p.str.startswith("hermes-migration\\henrry-push\\MoBo-Capital-Goals\\01-影视库", na=False)
    df["local_only"] = mbrain | film
    df["local_reason"] = ""
    df.loc[mbrain, "local_reason"] = "MoBoBrain 完整原件（只读本地）"
    df.loc[film, "local_reason"] = "01-影视库（只读本地）"

    sync = df[~df["excluded"] & ~df["local_only"] & ~cache & ~temp].copy()
    local = df[df["local_only"] & ~df["excluded"]].copy()
    excl = df[df["excluded"]].copy()
    cleanup = df[(cache | temp) & ~df["excluded"] & ~df["local_only"]].copy()

    total = int(df["size"].sum())
    out = {
        "total": {"files": len(df), "bytes": total, "gb": round(total / 1024 ** 3, 3)},
        "excluded": {"files": len(excl), "bytes": int(excl["size"].sum()), "gb": round(excl["size"].sum() / 1024 ** 3, 3), "reasons": group(excl, "exclude_reason").to_dict("records")},
        "local_only": {"files": len(local), "bytes": int(local["size"].sum()), "gb": round(local["size"].sum() / 1024 ** 3, 3), "folders": group(local, "local_reason").to_dict("records")},
        "sync": {
            "files": len(sync),
            "bytes": int(sync["size"].sum()),
            "gb": round(sync["size"].sum() / 1024 ** 3, 3),
            "categories": group(sync, "category").to_dict("records"),
            "p2": group(sync, "path").head(1).to_dict("records"),
        },
        "cleanup": {
            "files": len(cleanup),
            "bytes": int(cleanup["size"].sum()),
            "gb": round(cleanup["size"].sum() / 1024 ** 3, 3),
        },
    }

    # p2 for sync
    parts = sync["path"].str.split("\\", expand=True)
    sync["p2"] = [str(parts.iloc[i, 0]) + ("\\" + str(parts.iloc[i, 1]) if pd.notna(parts.iloc[i, 1]) else "") for i in range(len(sync))]
    out["sync"]["p2"] = group(sync, "p2").to_dict("records")

    # 文字类与原件类
    text = sync[sync["category"].isin(TEXT)]
    img = sync[sync["category"] == "图片"]
    other = sync[~sync["category"].isin(TEXT | {"图片"})]
    out["sync"]["text"] = {"files": len(text), "gb": round(text["size"].sum() / 1024 ** 3, 3), "categories": group(text, "category").to_dict("records")}
    out["sync"]["images"] = {"files": len(img), "gb": round(img["size"].sum() / 1024 ** 3, 3)}
    out["sync"]["other"] = {"files": len(other), "gb": round(other["size"].sum() / 1024 ** 3, 3)}

    (HERE / "sync-v5.json").write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    group(sync, "category").to_csv(HERE / "sync-v5-category.csv", index=False, encoding="utf-8-sig")
    group(sync, "p2").to_csv(HERE / "sync-v5-p2.csv", index=False, encoding="utf-8-sig")
    group(local, "local_reason").to_csv(HERE / "sync-v5-local.csv", index=False, encoding="utf-8-sig")

    print(f"total {out['total']['gb']:.3f} GiB / {len(df)}")
    print(f"excluded {out['excluded']['gb']:.3f} GiB / {len(excl)}")
    print(f"local_only {out['local_only']['gb']:.3f} GiB / {len(local)}")
    print(f"sync {out['sync']['gb']:.3f} GiB / {len(sync)}")
    print("\nsync categories:")
    for x in out["sync"]["categories"]:
        print(f"  {x['category']:<14} {x['gb']:>8.3f} GiB {x['files']:>7}")
    print("\nsync p2 top:")
    for x in out["sync"]["p2"][:14]:
        print(f"  {x['p2']:<55} {x['gb']:>8.3f} GiB {x['files']:>7}")
    print(f"\ntext {out['sync']['text']['gb']:.3f} GiB; images {out['sync']['images']['gb']:.3f} GiB; other {out['sync']['other']['gb']:.3f} GiB")


if __name__ == "__main__":
    main()
