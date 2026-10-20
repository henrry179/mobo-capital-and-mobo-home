"""阿里云 OSS 存储层。"""
from __future__ import annotations

from pathlib import Path

try:
    import oss2
except ImportError:  # pragma: no cover
    oss2 = None  # type: ignore

from .config import Settings


def _endpoint(value: str) -> str:
    value = value.strip()
    if not value:
        return value
    return value if value.startswith(("http://", "https://")) else f"https://{value}"


class Storage:
    def __init__(self, settings: Settings):
        if oss2 is None:
            raise SystemExit("缺少 oss2；请 pip install -e services/mobo-cli")
        if not settings.oss_ready():
            raise SystemExit("OSS 配置不完整：需要 OSS_CLI_ENDPOINT/OSS_PUBLIC_ENDPOINT、Bucket、AK/SK")
        auth = oss2.Auth(settings.oss_access_key_id, settings.oss_access_key_secret)
        self.bucket = oss2.Bucket(auth, _endpoint(settings.oss_endpoint), settings.oss_bucket)
        self.bucket_name = settings.oss_bucket

    def exists(self, key: str) -> bool:
        return bool(self.bucket.object_exists(key))

    def upload_file(self, path: str | Path, key: str, mime: str) -> bool:
        """上传文件；已存在则跳过。返回是否实际上传。"""
        if self.exists(key):
            return False
        self.bucket.put_object_from_file(key, str(path), headers={"Content-Type": mime})
        return True

    def upload_bytes(self, key: str, data: bytes, mime: str) -> None:
        self.bucket.put_object(key, data, headers={"Content-Type": mime})

    def delete(self, key: str) -> None:
        try:
            self.bucket.delete_object(key)
        except Exception:  # noqa: BLE001
            pass

    def signed_url(self, key: str, expires: int = 3600) -> str:
        return self.bucket.sign_url("GET", key, expires, slash_safe=True)

    def acl(self) -> str:
        return self.bucket.get_bucket_acl().acl
