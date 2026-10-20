#!/usr/bin/env python3
# =============================================================================
# 阿里云 OSS Guard：生命周期 + 防盗链 + 私有 Bucket 公共访问阻断
#
# 依赖：pip install -r deploy/scripts/requirements.txt
# 运行：在能访问 OSS 公网 Endpoint 的机器上执行
#   set -a; . ./.env; set +a
#   python deploy/scripts/oss_guard_setup.py
#
# 说明：
# - 服务器容器内使用 -internal Endpoint；本脚本默认用公网 Endpoint（本地可跑）。
# - 运行前请确认 Bucket 名称、地域、AK/SK；建议先用 DRY_RUN=1 查看。
# - 阿里云 OSS 的 IA/Archive 有最低存储期与取回费；规则不要盲目提前转换。
# =============================================================================
import os
import sys
from typing import Iterable

try:
    import oss2
    from oss2.models import (
        BucketLifecycle,
        LifecycleExpiration,
        LifecycleRule,
        RefererList,
        StorageTransition,
    )
except ImportError as exc:
    print("ERROR: 缺少 oss2。请先 pip install -r deploy/scripts/requirements.txt", file=sys.stderr)
    raise SystemExit(2) from exc

# 可选 API：不同 oss2 版本可能没有 PublicAccessBlock
try:
    from oss2.models import PublicAccessBlock  # type: ignore
except ImportError:  # pragma: no cover
    PublicAccessBlock = None  # type: ignore


def env(name: str, default: str | None = None, required: bool = False) -> str:
    value = os.getenv(name, default)
    if required and not value:
        raise SystemExit(f"ERROR: 缺少环境变量 {name}")
    return value or ""


def endpoint_with_scheme(value: str) -> str:
    value = value.strip()
    if not value:
        return value
    if value.startswith("http://") or value.startswith("https://"):
        return value
    return "https://" + value


def build_bucket(endpoint: str, bucket_name: str) -> "oss2.Bucket":
    auth = oss2.Auth(
        env("OSS_ACCESS_KEY_ID", required=True),
        env("OSS_ACCESS_KEY_SECRET", required=True),
    )
    return oss2.Bucket(auth, endpoint_with_scheme(endpoint), bucket_name)


def private_lifecycle() -> "BucketLifecycle":
    """私有档案 Bucket：4 条规则。

    注意：
    - photo 先 IA 再 Archive；
    - video 7 天转 Archive（Archive 最低 60 天，提前转也会按最低期计费）；
    - restic 备份只转 IA，不转 Archive，避免 prune 取回/删除失败；
    - thumbnails 保持标准层，保证看板快速加载。
    """
    rules = [
        LifecycleRule(
            "scan-doc-to-ia",
            "scan_doc/",
            status=LifecycleRule.ENABLED,
            transitions=[StorageTransition(days=90, storage_class=oss2.BUCKET_STORAGE_CLASS_IA)],
        ),
        LifecycleRule(
            "photo-to-ia-archive",
            "photo/",
            status=LifecycleRule.ENABLED,
            transitions=[
                StorageTransition(days=30, storage_class=oss2.BUCKET_STORAGE_CLASS_IA),
                StorageTransition(days=180, storage_class=oss2.BUCKET_STORAGE_CLASS_ARCHIVE),
            ],
        ),
        LifecycleRule(
            "video-to-archive",
            "video/",
            status=LifecycleRule.ENABLED,
            transitions=[StorageTransition(days=7, storage_class=oss2.BUCKET_STORAGE_CLASS_ARCHIVE)],
        ),
        LifecycleRule(
            "restic-to-ia",
            "restic-cold-backup/",
            status=LifecycleRule.ENABLED,
            transitions=[StorageTransition(days=30, storage_class=oss2.BUCKET_STORAGE_CLASS_IA)],
        ),
    ]
    return BucketLifecycle(rules)


def public_lifecycle() -> "BucketLifecycle":
    """公开图床：只清理 tmp/，不把公开图片转归档。"""
    rules = [
        LifecycleRule(
            "public-tmp-cleanup",
            "tmp/",
            status=LifecycleRule.ENABLED,
            expiration=LifecycleExpiration(days=7),
        )
    ]
    return BucketLifecycle(rules)


def apply_referer(bucket: "oss2.Bucket", referers: Iterable[str]) -> None:
    items = [x.strip() for x in referers if x.strip()]
    if not items:
        raise SystemExit("ERROR: OSS_REFERER_WHITELIST 为空；公开图床必须配置防盗链")
    # 阿里云 Referer 支持通配符；allow_empty=False 表示禁止空 Referer
    bucket.put_bucket_referer(RefererList(items, allow_empty=False))
    print(f"  referer: {items} (allow_empty=False)")


def block_public_access(bucket: "oss2.Bucket") -> None:
    if PublicAccessBlock is None or not hasattr(bucket, "put_bucket_public_access_block"):
        print("  WARN: 当前 oss2 版本不支持 PublicAccessBlock API，请在控制台手动开启“阻止公共访问”")
        return
    try:
        # 不同版本字段名可能不同；全开是最保守的
        config = PublicAccessBlock(
            block_public_acls=True,
            block_public_policy=True,
            ignore_public_acls=True,
            restrict_public_buckets=True,
        )
        bucket.put_bucket_public_access_block(config)
        print("  公共访问阻断：已开启")
    except Exception as exc:  # noqa: BLE001 - 兼容不同 SDK 版本
        print(f"  WARN: 公共访问阻断 API 调用失败，请在控制台手动确认：{exc}")


def main() -> int:
    dry_run = env("DRY_RUN", "0").lower() in {"1", "true", "yes"}
    public_bucket_name = env("OSS_BUCKET_PUBLIC", required=True)
    private_bucket_name = env("OSS_BUCKET_ARCHIVE", required=True)
    public_ep = env("OSS_GUARD_PUBLIC_ENDPOINT") or env("OSS_PUBLIC_ENDPOINT", required=True)
    private_ep = env("OSS_GUARD_PRIVATE_ENDPOINT") or env("OSS_PUBLIC_ENDPOINT", required=True)
    referers = env("OSS_REFERER_WHITELIST", "").split(",")

    print("OSS Guard 配置")
    print(f"  公网 Endpoint: {endpoint_with_scheme(public_ep)}")
    print(f"  公开 Bucket: {public_bucket_name}")
    print(f"  私有 Bucket: {private_bucket_name}")
    print(f"  DRY_RUN: {dry_run}")

    if dry_run:
        print("\n[DRY RUN] 将执行：")
        print("  public: ACL=public-read, referer=whitelist, lifecycle=tmp/ 7d expire")
        print("  private: ACL=private, block public access, lifecycle=4 rules")
        return 0

    public_bucket = build_bucket(public_ep, public_bucket_name)
    private_bucket = build_bucket(private_ep, private_bucket_name)

    print("\n[1/4] 公开 Bucket：ACL + 防盗链")
    public_bucket.put_bucket_acl(oss2.BUCKET_ACL_PUBLIC_READ)
    apply_referer(public_bucket, referers)

    print("\n[2/4] 公开 Bucket：生命周期（tmp/ 7 天清理）")
    public_bucket.put_bucket_lifecycle(public_lifecycle())

    print("\n[3/4] 私有 Bucket：ACL=private + 公共访问阻断")
    private_bucket.put_bucket_acl(oss2.BUCKET_ACL_PRIVATE)
    block_public_access(private_bucket)

    print("\n[4/4] 私有 Bucket：生命周期（4 条规则）")
    private_bucket.put_bucket_lifecycle(private_lifecycle())

    print("\n完成。请在 OSS 控制台核对：")
    print("  - 公开 Bucket：读写权限=公共读，防盗链 allow_empty=False，无 List 权限")
    print("  - 私有 Bucket：读写权限=私有，阻止公共访问=已开启，4 条生命周期=启用")
    print("  - 备份前缀 restic-cold-backup/ 不要配置转 Archive")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
