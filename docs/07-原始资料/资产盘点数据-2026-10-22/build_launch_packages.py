# -*- coding: utf-8 -*-
"""按“上线同步包”口径重新切分：排除视频/音频/Git/状态快照后，剩余资产分类。"""
from __future__ import annotations

import json
import os
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent
CSV = Path(os.environ.get("TEMP", ".")) / "mobo_inventory.csv"

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


def cat(ext: str, name: str) -> str:
    if name.startswith("~$") or name.startswith("._"):
        return "临时/系统"
    return CAT.get((ext or "").lower(), "其他")


def main():
    df = pd.read_csv(CSV)
    df["size"] = df["size"].astype("int64")
    df["name"] = df["name"].fillna("").astype(str)
    df["path"] = df["path"].fillna("").astype(str)
    df["ext"] = df["ext"].fillna("").astype(str)
    df["category"] = [cat(e, n) for e, n in zip(df["ext"], df["name"])]
    p = df["path"].str.replace("/", "\\", regex=False)

    is_video = p.str.contains(r"\\PodcastPlayBooks\\Videos\\|\\07-鬼畜视频系列\\", regex=True)
    is_audio = p.str.contains(r"\\05-MP3-合成音频\\", regex=True)
    is_git = p.str.contains(r"\\\.git\\", regex=True) | p.str.startswith(".git\\")
    is_backup = p.str.startswith("hermes-migration\\henrry-push\\hermes\\backups\\", na=False)
    is_cache = p.str.contains(r"\\__(?:pycache|pytest_cache|mypy_cache)__\\|\\node_modules\\|\\\.venv\\", regex=True)
    is_temp = df["category"].eq("临时/系统")

    df["exclude"] = is_video | is_audio | is_git | is_backup
    df["exclude_reason"] = ""
    df.loc[is_video, "exclude_reason"] = "视频（用户明确排除）"
    df.loc[is_audio, "exclude_reason"] = "音频（用户明确排除）"
    df.loc[is_git, "exclude_reason"] = "Git 版本库（用户明确排除）"
    df.loc[is_backup, "exclude_reason"] = "GitHub/Hermes 状态快照（用户明确排除）"
    # 缓存/临时不进入上线包，但保留在环境清理项
    df["cleanup"] = is_cache | is_temp

    remain = df[~df["exclude"]].copy()
    excl = df[df["exclude"]].copy()

    # 站点包粗分（按目录规则）
    def pkg(row) -> str:
        path = row["path"]
        low = path.lower()
        if row["cleanup"]:
            return "00-清理/临时"
        if path.startswith(("docs\\", "deploy\\", "services\\", "sites\\", "workflows\\", "migrations\\", "seeds\\", "tests\\", "tools\\")) or row["path"] in (".env.example", ".env.local", ".gitignore", "docker-compose.yml", "docker-compose.local.yml", "docker-compose.wsl.yml", "README.md", "CLAUDE.md", "TASK_STATE.md"):
            return "90-工程仓（Git 部署）"
        if path.startswith("ReadingBooks"):
            return "B-public"
        if path.startswith("01-工作与项目\\AutopilotTradeBoMo"):
            if "010-分析报告" in path or "卸载分析报告" in path or "大模型价格" in path:
                return "A-internal"
            if "\\01_原始文档\\" in path:
                return "99-原始归档（不上服务器）"
            return "A-public" if any(k in path for k in ("执行中", "03_内容生产")) else "A-internal"
        if path.startswith("01-工作与项目\\ITPM-PlayBooks"):
            return "99-原始归档（不上服务器）"
        if path.startswith("01-工作与项目\\WorkFiles"):
            if any(k in path for k in ("周报", "指标文件", "DatasListVision", "WorkAnalysis", "CombinePython")):
                return "B-private"
            return "99-原始归档（不上服务器）"
        if path.startswith("hermes-migration\\henrry-push\\MoBoBrain-ITPM-Archive"):
            if "\\Goals\\Peoples" in path:
                return "People-archive"
            if "\\01-MD-深度精读\\" in path:
                return "A-public"
            if "\\06-IMAGES-封面配图\\" in path:
                return "A-public"
            return "A-internal"
        if path.startswith("hermes-migration\\mobobrain-assets"):
            return "A-public" if "\\covers\\" in path else "A-internal"
        if path.startswith("hermes-migration"):
            return "A-internal"
        if path.startswith("ITPM原稿内容"):
            return "99-原始归档（不上服务器）"
        if path.startswith("AIGC原稿"):
            return "A-internal"
        return "99-原始归档（不上服务器）"

    remain["package"] = [pkg(r) for _, r in remain.iterrows()]

    # 汇总
    total = int(df["size"].sum())
    excluded = int(excl["size"].sum())
    remaining = int(remain["size"].sum())

    def group(frame, key):
        g = frame.groupby(key).agg(files=("size", "size"), bytes=("size", "sum")).reset_index()
        g["gb"] = (g["bytes"] / 1024 ** 3).round(4)
        g["share_total"] = (g["bytes"] / total * 100).round(2)
        g["share_remaining"] = (g["bytes"] / remaining * 100).round(2)
        return g.sort_values("bytes", ascending=False)

    out = {
        "total": {"files": len(df), "bytes": total, "gb": round(total / 1024 ** 3, 3)},
        "excluded": {
            "files": len(excl), "bytes": excluded, "gb": round(excluded / 1024 ** 3, 3),
            "share": round(excluded / total * 100, 2),
            "reasons": group(excl, "exclude_reason").to_dict("records"),
        },
        "remaining": {
            "files": len(remain), "bytes": remaining, "gb": round(remaining / 1024 ** 3, 3),
            "share": round(remaining / total * 100, 2),
            "categories": group(remain, "category").to_dict("records"),
            "packages": group(remain, "package").to_dict("records"),
        },
    }
    (HERE / "launch-packages.json").write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    group(df, "category").to_csv(HERE / "launch-category.csv", index=False, encoding="utf-8-sig")
    group(remain, "package").to_csv(HERE / "launch-packages.csv", index=False, encoding="utf-8-sig")

    # 包 × 类型 / 包 × 二级目录
    pc = remain.groupby(["package", "category"]).agg(files=("size", "size"), bytes=("size", "sum")).reset_index()
    pc["gb"] = (pc["bytes"] / 1024 ** 3).round(4)
    pc.sort_values(["package", "bytes"], ascending=[True, False]).to_csv(HERE / "launch-package-category.csv", index=False, encoding="utf-8-sig")

    parts = remain["path"].str.split("\\", expand=True)
    remain["p2"] = [str(parts.iloc[i, 0]) + ("\\" + str(parts.iloc[i, 1]) if pd.notna(parts.iloc[i, 1]) else "") for i in range(len(remain))]
    pp = remain.groupby(["package", "p2"]).agg(files=("size", "size"), bytes=("size", "sum")).reset_index()
    pp["gb"] = (pp["bytes"] / 1024 ** 3).round(4)
    pp.sort_values(["package", "bytes"], ascending=[True, False]).to_csv(HERE / "launch-package-folder.csv", index=False, encoding="utf-8-sig")

    print(f"total {out['total']['gb']:.3f} GiB")
    print(f"excluded {out['excluded']['gb']:.3f} GiB ({out['excluded']['share']:.1f}%)")
    print(f"remaining {out['remaining']['gb']:.3f} GiB ({out['remaining']['share']:.1f}%)")
    print("\nremaining categories:")
    for x in out["remaining"]["categories"]:
        print(f"  {x['category']:<14} {x['gb']:>8.3f} GiB  {x['files']:>7}")
    print("\npackages:")
    for x in out["remaining"]["packages"]:
        print(f"  {x['package']:<28} {x['gb']:>8.3f} GiB  {x['files']:>7}")


if __name__ == "__main__":
    main()
