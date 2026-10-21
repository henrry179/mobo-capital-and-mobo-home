"""数据库连接。CLI 只使用应用账号，不使用 postgres 超级用户。"""
from __future__ import annotations

import psycopg2
from psycopg2.extensions import connection

from .config import Settings


def connect_archive(settings: Settings) -> connection:
    if not settings.archive_password:
        raise SystemExit("缺少 PG_PASS_ARCHIVE（或 CLI_ARCHIVE_DB_PASSWORD）")
    return psycopg2.connect(settings.archive_dsn())


def connect_mobobrain(settings: Settings) -> connection:
    if not settings.mobobrain_password:
        raise SystemExit("缺少 PG_PASS_MOBOBRAIN（或 CLI_MOBOBRAIN_DB_PASSWORD）")
    return psycopg2.connect(settings.mobobrain_dsn())
