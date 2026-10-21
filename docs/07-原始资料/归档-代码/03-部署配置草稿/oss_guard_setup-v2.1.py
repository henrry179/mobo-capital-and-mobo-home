#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
路径: /opt/mobo-stack/scripts/oss_guard_setup.py
功能: 阿里云双 OSS 桶生命周期冷沉降规则 (5条) 与公有图床 Referer 防盗链一键注入脚本
依赖: pip install oss2 python-dotenv
"""

import os
from pathlib import Path
import oss2
from oss2.models import (
    LifecycleRule,
    StorageTransition,
    BucketLifecycle,
    BucketReferer,
)
from dotenv import load_dotenv

ENV_PATH = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(dotenv_path=ENV_PATH)


def apply_oss_guards():
    ak = os.getenv("ALIYUN_ACCESS_KEY_ID")
    sk = os.getenv("ALIYUN_ACCESS_KEY_SECRET")
    endpoint = os.getenv("OSS_PUBLIC_ENDPOINT", "https://oss-cn-hangzhou.aliyuncs.com")
    pub_name = os.getenv("OSS_BUCKET_PUBLIC", "mobobrain-assets-pub")
    priv_name = os.getenv("OSS_BUCKET_PRIVATE", "mobo-archive-private-hz")

    auth = oss2.Auth(ak, sk)
    pub_bucket = oss2.Bucket(auth, endpoint, pub_name)
    priv_bucket = oss2.Bucket(auth, endpoint, priv_name)

    # 1. 公有图床桶：强制开启双站 Referer 白名单且禁止空 Referer (防恶意盗刷流量)
    referer_whitelist = [
        "https://mobocapital.com",
        "https://*.mobocapital.com",
        "https://mobohome.com",
        "https://*.mobohome.com",
    ]
    pub_bucket.put_bucket_referer(
        BucketReferer(allow_empty_referer=False, referers=referer_whitelist)
    )
    print(f"✅ [公有图床防盗链已生效] Bucket: {pub_name} | AllowEmptyReferer: False")

    # 2. 私有档案桶：注入 5 条冷热分层 Lifecycle 规则 (thumbnails/ 不设沉降，永保热读)
    rules = [
        # 规则 1: 莫伯之家原图 (30天转低频 IA, 180天转归档 Archive)
        LifecycleRule(
            id="rule-photo-cold-tiering",
            prefix="photo/",
            status=LifecycleRule.ENABLED,
            storage_transitions=[
                StorageTransition(days=30, storage_class=oss2.BUCKET_STORAGE_CLASS_IA),
                StorageTransition(days=180, storage_class=oss2.BUCKET_STORAGE_CLASS_ARCHIVE),
            ],
        ),
        # 规则 2: 莫伯之家视频原片 (90天直转归档 Archive)
        LifecycleRule(
            id="rule-video-direct-archive",
            prefix="video/",
            status=LifecycleRule.ENABLED,
            storage_transitions=[
                StorageTransition(days=90, storage_class=oss2.BUCKET_STORAGE_CLASS_ARCHIVE),
            ],
        ),
        # 规则 3: 莫伯之家 PDF 扫描件与证书 (30天转低频 IA)
        LifecycleRule(
            id="rule-scandoc-ia",
            prefix="scan_doc/",
            status=LifecycleRule.ENABLED,
            storage_transitions=[
                StorageTransition(days=30, storage_class=oss2.BUCKET_STORAGE_CLASS_IA),
            ],
        ),
        # 规则 4: 莫伯资本实盘交割单加密证据链 (30天转低频 IA, 180天转归档 Archive)
        LifecycleRule(
            id="rule-capital-blotters-cold",
            prefix="blotters/",
            status=LifecycleRule.ENABLED,
            storage_transitions=[
                StorageTransition(days=30, storage_class=oss2.BUCKET_STORAGE_CLASS_IA),
                StorageTransition(days=180, storage_class=oss2.BUCKET_STORAGE_CLASS_ARCHIVE),
            ],
        ),
        # 规则 5: Restic 全栈灾备冷仓库 (30天转低频 IA)
        LifecycleRule(
            id="rule-restic-backup-ia",
            prefix="restic-cold-backup/",
            status=LifecycleRule.ENABLED,
            storage_transitions=[
                StorageTransition(days=30, storage_class=oss2.BUCKET_STORAGE_CLASS_IA),
            ],
        ),
    ]

    priv_bucket.put_bucket_lifecycle(BucketLifecycle(rules))
    print(f"✅ [私有桶 5 条冷沉降规则已注入] Bucket: {priv_name} (thumbnails/ 保持 Standard 热存储)")
    print("[OK] Lifecycle & Referer Guard Applied")


if __name__ == "__main__":
    apply_oss_guards()