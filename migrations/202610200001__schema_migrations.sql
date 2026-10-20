-- =============================================================================
-- 202610200001__schema_migrations.sql
-- 目的：创建迁移版本表（幂等）
-- 影响：public.schema_migrations
-- 回滚：DROP TABLE public.schema_migrations;
-- =============================================================================
\set ON_ERROR_STOP on

CREATE TABLE IF NOT EXISTS public.schema_migrations (
    version     TEXT PRIMARY KEY,
    description TEXT NOT NULL,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    checksum    TEXT NOT NULL
);

COMMENT ON TABLE public.schema_migrations IS '数据库迁移版本；由 migrations/apply.sh 维护';
