"""CLI 配置：优先环境变量，其次当前目录 .env。"""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

try:
    from dotenv import load_dotenv
except ImportError:  # pragma: no cover
    load_dotenv = None  # type: ignore


def load_environment(env_file: str | None = None) -> None:
    if load_dotenv is None:
        return
    path = Path(env_file) if env_file else Path.cwd() / ".env"
    if path.exists():
        load_dotenv(path, override=False)


def _get(name: str, default: str | None = None, required: bool = False) -> str:
    value = os.getenv(name, default)
    if required and not value:
        raise SystemExit(f"缺少环境变量 {name}；请检查 .env 或 export")
    return value or ""


@dataclass(frozen=True)
class Settings:
    db_host: str
    db_port: int
    archive_db: str
    archive_user: str
    archive_password: str
    mobobrain_db: str
    mobobrain_user: str
    mobobrain_password: str
    oss_endpoint: str
    oss_bucket: str
    oss_access_key_id: str
    oss_access_key_secret: str
    llm_api_base: str
    llm_api_key: str
    llm_model: str
    embedding_api_base: str
    embedding_api_key: str
    embedding_model: str
    embedding_dim: int

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            db_host=_get("CLI_DATABASE_HOST", "127.0.0.1"),
            db_port=int(_get("CLI_DATABASE_PORT", "5432")),
            archive_db=_get("CLI_ARCHIVE_DB_NAME", "db_archive"),
            archive_user=_get("CLI_ARCHIVE_DB_USER", "user_archive"),
            archive_password=_get("CLI_ARCHIVE_DB_PASSWORD", ""),
            mobobrain_db=_get("CLI_MOBOBRAIN_DB_NAME", "db_mobobrain"),
            mobobrain_user=_get("CLI_MOBOBRAIN_DB_USER", "user_mobobrain"),
            mobobrain_password=_get("CLI_MOBOBRAIN_DB_PASSWORD", ""),
            # CLI 在宿主机运行，默认用公网 Endpoint；在服务器上可覆盖为内网
            oss_endpoint=_get("OSS_CLI_ENDPOINT") or _get("OSS_PUBLIC_ENDPOINT", ""),
            oss_bucket=_get("OSS_BUCKET_ARCHIVE", ""),
            oss_access_key_id=_get("OSS_ACCESS_KEY_ID", ""),
            oss_access_key_secret=_get("OSS_ACCESS_KEY_SECRET", ""),
            llm_api_base=_get("LLM_API_BASE", ""),
            llm_api_key=_get("LLM_API_KEY", ""),
            llm_model=_get("LLM_MODEL", ""),
            embedding_api_base=_get("EMBEDDING_API_BASE", ""),
            embedding_api_key=_get("EMBEDDING_API_KEY", ""),
            embedding_model=_get("EMBEDDING_MODEL", ""),
            embedding_dim=int(_get("EMBEDDING_DIM", "1536")),
        )

    def archive_dsn(self) -> str:
        return (
            f"host={self.db_host} port={self.db_port} dbname={self.archive_db} "
            f"user={self.archive_user} password={self.archive_password} connect_timeout=5"
        )

    def mobobrain_dsn(self) -> str:
        return (
            f"host={self.db_host} port={self.db_port} dbname={self.mobobrain_db} "
            f"user={self.mobobrain_user} password={self.mobobrain_password} connect_timeout=5"
        )

    def oss_ready(self) -> bool:
        return all([self.oss_endpoint, self.oss_bucket, self.oss_access_key_id, self.oss_access_key_secret])


def get_settings(env_file: str | None = None) -> Settings:
    load_environment(env_file)
    return Settings.from_env()
