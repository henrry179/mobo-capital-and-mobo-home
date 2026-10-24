# -*- coding: utf-8 -*-
"""莫伯双站内容资产双维盘点：从全量文件清单生成聚合数据。

输入：mobo_inventory.csv（列：path,name,ext,size,mtime,top,depth）
输出：summary.json / folder-size.csv / filetype-size.csv /
      cross-matrix.csv / top-files.csv / ext-detail.csv
只做只读统计，不移动、不删除任何源文件。
"""
from __future__ import annotations

import json
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent
DEFAULT_CSV = Path(os.environ.get("TEMP", ".")) / "mobo_inventory.csv"

# ---------------------------------------------------------------- 分类映射
CATEGORY_ORDER = [
    "视频", "图片", "数据库/状态快照", "版本库对象", "PDF", "Word",
    "压缩包", "音频", "Markdown", "代码/配置", "演示/表格", "文本",
    "字体", "其他/无扩展名",
]

EXT_CATEGORY = {}
for exts, cat in [
    ((".mp4", ".mov", ".mkv", ".avi", ".flv", ".wmv", ".webm", ".m4v", ".mpg", ".mpeg", ".ts"), "视频"),
    ((".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".svg", ".tif", ".tiff", ".heic", ".ico", ".psd", ".ai", ".eps"), "图片"),
    ((".db", ".sqlite", ".sqlite3", ".mdb", ".parquet", ".feather", ".h5", ".hdf5", ".pkl", ".pickle", ".npy", ".npz", ".dat", ".bin"), "数据库/状态快照"),
    ((".pack", ".idx", ".rev", ".bitmap", ".keep"), "版本库对象"),
    ((".pdf",), "PDF"),
    ((".doc", ".docx", ".docm", ".dot", ".dotx", ".rtf", ".odt"), "Word"),
    ((".zip", ".7z", ".rar", ".tar", ".gz", ".tgz", ".bz2", ".xz", ".zst", ".lz4"), "压缩包"),
    ((".mp3", ".wav", ".flac", ".m4a", ".aac", ".ogg", ".wma", ".aiff"), "音频"),
    ((".md", ".markdown", ".mdx"), "Markdown"),
    ((".py", ".pyc", ".pyd", ".js", ".mjs", ".cjs", ".ts", ".tsx", ".jsx", ".html", ".htm", ".css", ".scss", ".less", ".sh", ".bash", ".ps1", ".bat", ".cmd", ".sql", ".ipynb", ".vue", ".php", ".go", ".rs", ".java", ".c", ".cpp", ".h", ".hpp", ".rb", ".lua", ".r", ".m", ".swift", ".kt", ".scala", ".yml", ".yaml", ".toml", ".ini", ".cfg", ".conf", ".json", ".jsonl", ".xml", ".env", ".sty", ".cls", ".tex"), "代码/配置"),
    ((".ppt", ".pptx", ".pps", ".ppsx", ".xls", ".xlsx", ".csv", ".tsv", ".ods"), "演示/表格"),
    ((".txt", ".log", ".rst"), "文本"),
    ((".ttf", ".otf", ".woff", ".woff2", ".eot"), "字体"),
]:
    for e in exts:
        EXT_CATEGORY[e] = cat


def classify(ext: str, name: str) -> str:
    e = (ext or "").lower()
    if name.startswith("~$") or name.startswith("._"):
        return "其他/无扩展名"
    return EXT_CATEGORY.get(e, "其他/无扩展名")


def category_of_row(row) -> str:
    return classify(row["ext"], row["name"])


# ---------------------------------------------------------------- 双站去向规则
def destination(row) -> str:
    """按“后期同步到两站”的处置口径做粗分流（目录级规则）。"""
    p = row["path"].replace("/", "\\")
    low = p.lower()
    name = row["name"]

    # 版本库 / 缓存 / 临时文件
    if "\\.git\\" in low or low.startswith(".git\\"):
        return "版本库与备份"
    if any(x in low for x in ("\\__pycache__\\", "\\.venv\\", "\\node_modules\\", "\\.pytest_cache\\", "\\.mypy_cache\\")):
        return "工程与治理"
    if name.startswith("~$") or name.startswith("._") or name in (".DS_Store", "Thumbs.db", "desktop.ini"):
        return "待清理/临时"

    # 工程栈
    if row["top"] in ("docs", "deploy", "services", "sites", "workflows", "migrations", "seeds", "tests", "tools", ".git") or row["top"] == "(root)":
        if row["top"] == "docs" and "07-原始资料" in p:
            return "工程与治理"
        return "工程与治理"

    # 阅读封面 → 莫伯之家
    if row["top"] == "ReadingBooks":
        return "B站内容源"

    # 工作区
    if p.startswith("01-工作与项目\\AutopilotTradeBoMo"):
        if "010-分析报告" in p or "卸载分析报告" in p or "大模型价格" in p:
            return "运维/内部"
        if "\\01_原始文档\\" in p:
            return "冷存档/待去重"
        return "A站内容源"
    if p.startswith("01-工作与项目\\ITPM-PlayBooks"):
        return "冷存档/待去重"
    if p.startswith("01-工作与项目\\WorkFiles"):
        if any(k in p for k in ("周报", "指标文件", "DatasListVision", "WorkAnalysis", "CombinePython")):
            return "B站内容源"
        if any(k in p for k in ("finance_translator", "pdf-image-extractor", "Claude code")):
            return "工程与治理"
        return "冷存档/待去重"

    # Hermes 迁移包
    if p.startswith("hermes-migration\\henrry-push\\MoBoBrain-ITPM-Archive"):
        if "\\Goals\\Peoples" in p:
            return "People存档（暂不上站）"
        return "A站内容源"
    if p.startswith("hermes-migration\\henrry-push\\hermes") or p.startswith("hermes-migration\\henrry-push\\\\.git"):
        return "版本库与备份"
    if p.startswith("hermes-migration\\henrry-push"):
        return "运维/内部"
    if p.startswith("hermes-migration\\mobobrain-assets"):
        if "\\fonts\\" in p:
            return "运维/内部"
        return "A站内容源"
    if p.startswith("hermes-migration"):
        return "运维/内部"

    # 根原料
    if row["top"] == "ITPM原稿内容":
        return "冷存档/待去重"
    if row["top"] == "AIGC原稿":
        return "A站内容源"
    return "待定"


# ---------------------------------------------------------------- 工具函数
def fmt_gb(n: int | float) -> float:
    return round(float(n) / 1024 ** 3, 4)


def tree_from_df(df: pd.DataFrame, max_depth: int = 3, min_share: float = 0.0015):
    """构造最多 max_depth 层的空间树；小节点并入“其他”。"""
    total = int(df["size"].sum())

    def node(part: pd.DataFrame, depth: int):
        name = part.attrs.get("label", "")
        if depth >= max_depth or len(part) == 0:
            return {"name": name, "value": int(part["size"].sum())}
        # 按当前层路径聚合
        key = "top" if depth == 1 else f"p{depth}"
        grouped = part.groupby(key, dropna=False)["size"].agg(["sum", "count"]).sort_values("sum", ascending=False)
        children = []
        other_sum = 0
        other_count = 0
        for label, r in grouped.iterrows():
            label = str(label)
            if r["sum"] / max(total, 1) < min_share:
                other_sum += int(r["sum"])
                other_count += int(r["count"])
                continue
            sub = part[part[key] == label]
            sub.attrs["label"] = label
            children.append(node(sub, depth + 1) | {"count": int(r["count"])})
        if other_sum:
            children.append({"name": "其他", "value": other_sum, "count": other_count})
        return {"name": name, "value": int(part["size"].sum()), "count": int(len(part)), "children": children}

    df = df.copy()
    df.attrs["label"] = "全部"
    return node(df, 1)


def main(csv_path: Path):
    df = pd.read_csv(csv_path)
    df["size"] = df["size"].astype("int64")
    df["ext"] = df["ext"].fillna("").astype(str)
    df["name"] = df["name"].fillna("").astype(str)
    df["path"] = df["path"].fillna("").astype(str)
    df["category"] = [category_of_row(r) for _, r in df.iterrows()]
    df["dest"] = [destination(r) for _, r in df.iterrows()]

    # 路径层级
    parts = df["path"].str.split("\\", expand=True)
    depth = pd.to_numeric(df["depth"], errors="coerce").fillna(1)
    df["top"] = [str(parts.iloc[i, 0]) if depth.iloc[i] > 1 else "(root)" for i in range(len(df))]

    def dir_level(parts_row, n):
        """返回文件所在目录（第 n 层）；不足 n 层时返回其父目录。"""
        segs = [str(x) for x in parts_row if not pd.isna(x)]
        if len(segs) <= 1:
            return "(root)"
        if len(segs) > n:
            return "\\".join(segs[:n])
        return "\\".join(segs[:-1])

    df["p2"] = [dir_level(parts.iloc[i].tolist(), 2) for i in range(len(df))]
    df["p3"] = [dir_level(parts.iloc[i].tolist(), 3) for i in range(len(df))]
    df["p4"] = [dir_level(parts.iloc[i].tolist(), 4) for i in range(len(df))]
    df["fname"] = df["name"]
    df["is_temp"] = df["name"].str.startswith("~$") | df["name"].str.startswith("._") | df["name"].isin([".DS_Store", "Thumbs.db", "desktop.ini"])
    df["is_git"] = df["path"].str.lower().str.contains(r"\\\.git\\", regex=True) | df["path"].str.lower().str.startswith(".git\\")
    df["is_cache"] = df["path"].str.lower().str.contains(r"\\__(?:pycache|pytest_cache|mypy_cache)__\\|\\node_modules\\|\\\.venv\\", regex=True)

    total_bytes = int(df["size"].sum())
    total_files = int(len(df))

    # ---------------- 顶层 / 二级 / 三级
    def rollup(key: str, level: int):
        g = df.groupby(key, dropna=False).agg(files=("size", "size"), bytes=("size", "sum")).reset_index()
        g = g.rename(columns={key: "path"})
        g["level"] = level
        g["gb"] = (g["bytes"] / 1024 ** 3).round(3)
        g["share"] = (g["bytes"] / total_bytes * 100).round(2)
        return g.sort_values("bytes", ascending=False)

    top = rollup("top", 1)
    p2 = rollup("p2", 2)
    p3 = rollup("p3", 3)
    p4 = rollup("p4", 4)

    # ---------------- 文件类型
    cat = (df.groupby("category").agg(files=("size", "size"), bytes=("size", "sum")).reset_index())
    cat["gb"] = (cat["bytes"] / 1024 ** 3).round(3)
    cat["share"] = (cat["bytes"] / total_bytes * 100).round(2)
    cat["files_share"] = (cat["files"] / total_files * 100).round(2)
    cat["order"] = cat["category"].map({c: i for i, c in enumerate(CATEGORY_ORDER)})
    cat = cat.sort_values("order")

    ext = (df[df["ext"] != ""].groupby(["ext", "category"]).agg(files=("size", "size"), bytes=("size", "sum")).reset_index())
    ext["gb"] = (ext["bytes"] / 1024 ** 3).round(3)
    ext = ext.sort_values("bytes", ascending=False).head(60)

    # ---------------- 目录 × 类型 交叉矩阵（按二级目录，取前 12）
    top_p2 = p2[
        (~p2["path"].str.startswith(".git"))
        & (p2["path"] != "(root)")
        & (~p2["path"].str.contains(r"\\__pycache__|\\node_modules", regex=True))
    ].head(10)["path"].tolist()
    cross = []
    for path in top_p2:
        sub = df[df["p2"] == path]
        row = {"path": path, "total": int(sub["size"].sum())}
        for c in CATEGORY_ORDER:
            row[c] = int(sub[sub["category"] == c]["size"].sum())
        cross.append(row)

    # ---------------- 最大文件
    top_files = df.sort_values("size", ascending=False).head(40)[["path", "size", "category", "mtime"]].copy()
    top_files["gb"] = (top_files["size"] / 1024 ** 3).round(4)

    # ---------------- 临时 / 缓存
    temp = df[df["is_temp"]]
    cache = df[df["is_cache"]]
    git = df[df["is_git"]]

    # ---------------- 备份快照
    backups = df[df["path"].str.startswith("hermes-migration\\henrry-push\\hermes\\backups\\", na=False)].copy()
    backup_snap = []
    if len(backups):
        backups["snap"] = backups["path"].str.split("\\").str[4]
        gb = backups.groupby("snap").agg(files=("size", "size"), bytes=("size", "sum")).sort_values("bytes", ascending=False)
        backup_snap = [{"snap": k, "files": int(v["files"]), "gb": fmt_gb(v["bytes"])} for k, v in gb.iterrows()]

    # ---------------- 去向汇总
    dest = (df.groupby("dest").agg(files=("size", "size"), bytes=("size", "sum")).reset_index())
    dest["gb"] = (dest["bytes"] / 1024 ** 3).round(3)
    dest["share"] = (dest["bytes"] / total_bytes * 100).round(2)
    dest = dest.sort_values("bytes", ascending=False)

    # ---------------- 去向 × 类型
    dest_cat = (df.groupby(["dest", "category"]).agg(files=("size", "size"), bytes=("size", "sum")).reset_index())
    dest_cat["gb"] = (dest_cat["bytes"] / 1024 ** 3).round(4)
    dest_cat = dest_cat.sort_values(["dest", "bytes"], ascending=[True, False])

    # 业务原料 = 剔除版本库/备份后的体量
    version_bytes = int(df[df["dest"] == "版本库与备份"]["size"].sum())
    effective_bytes = total_bytes - version_bytes

    # ---------------- 每类文件的头部目录
    category_folders = []
    for c in CATEGORY_ORDER:
        sub = df[df["category"] == c]
        if not len(sub):
            continue
        g = sub.groupby("p2").agg(files=("size", "size"), bytes=("size", "sum")).sort_values("bytes", ascending=False).head(8)
        category_folders.append({
            "category": c,
            "total_gb": fmt_gb(sub["size"].sum()),
            "folders": [{"path": str(k), "files": int(v["files"]), "gb": fmt_gb(v["bytes"])} for k, v in g.iterrows()],
        })

    # ---------------- 结构树（顶层 + 二级 + 三级）
    tree = tree_from_df(df, max_depth=3, min_share=0.0012)

    # ---------------- 输出
    summary = {
        "generated_at": "2026-10-22",
        "root": str(Path(csv_path).resolve()),
        "total_bytes": total_bytes,
        "total_gb": fmt_gb(total_bytes),
        "total_files": total_files,
        "top_count": int(len(top)),
        "temp": {"files": int(len(temp)), "bytes": int(temp["size"].sum()), "gb": fmt_gb(temp["size"].sum())},
        "cache": {"files": int(len(cache)), "bytes": int(cache["size"].sum()), "gb": fmt_gb(cache["size"].sum())},
        "git": {"files": int(len(git)), "bytes": int(git["size"].sum()), "gb": fmt_gb(git["size"].sum())},
        "backup": {"files": int(len(backups)), "bytes": int(backups["size"].sum()), "gb": fmt_gb(backups["size"].sum()), "snapshots": len(backup_snap)},
        "categories": cat.drop(columns=["order"]).to_dict("records"),
        "top": top[["path", "files", "bytes", "gb", "share"]].to_dict("records"),
        "p2": p2.head(40)[["path", "files", "bytes", "gb", "share"]].to_dict("records"),
        "p3": p3.head(40)[["path", "files", "bytes", "gb", "share"]].to_dict("records"),
        "p4": p4.head(40)[["path", "files", "bytes", "gb", "share"]].to_dict("records"),
        "dest": dest[["dest", "files", "bytes", "gb", "share"]].to_dict("records"),
        "dest_categories": dest_cat[["dest", "category", "files", "bytes", "gb"]].to_dict("records"),
        "effective_bytes": effective_bytes,
        "effective_gb": fmt_gb(effective_bytes),
        "effective_share": round(effective_bytes / total_bytes * 100, 2),
        "cross": cross,
        "category_folders": category_folders,
        "top_files": top_files.to_dict("records"),
        "backup_snapshots": backup_snap,
        "tree": tree,
        "category_order": CATEGORY_ORDER,
    }

    (HERE / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    top.to_csv(HERE / "folder-size-level1.csv", index=False, encoding="utf-8-sig")
    p2.to_csv(HERE / "folder-size-level2.csv", index=False, encoding="utf-8-sig")
    p3.to_csv(HERE / "folder-size-level3.csv", index=False, encoding="utf-8-sig")
    p4.to_csv(HERE / "folder-size-level4.csv", index=False, encoding="utf-8-sig")
    cat.to_csv(HERE / "filetype-size.csv", index=False, encoding="utf-8-sig")
    ext.to_csv(HERE / "ext-detail.csv", index=False, encoding="utf-8-sig")
    pd.DataFrame(cross).to_csv(HERE / "cross-matrix.csv", index=False, encoding="utf-8-sig")
    top_files.to_csv(HERE / "top-files.csv", index=False, encoding="utf-8-sig")

    print(f"files={total_files:,} total={summary['total_gb']:.2f} GB")
    print("\nTOP:")
    print(top[["path", "files", "gb", "share"]].to_string(index=False))
    print("\nCATEGORY:")
    print(cat[["category", "files", "gb", "share"]].to_string(index=False))
    print("\nDEST:")
    print(dest[["dest", "files", "gb", "share"]].to_string(index=False))
    print(f"\ntemp={len(temp):,} / {fmt_gb(temp['size'].sum()):.3f} GB; git={len(git):,} / {fmt_gb(git['size'].sum()):.3f} GB")
    print(f"backups={len(backups):,} / {summary['backup']['gb']:.3f} GB / {len(backup_snap)} snapshots")


if __name__ == "__main__":
    main(Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_CSV)
