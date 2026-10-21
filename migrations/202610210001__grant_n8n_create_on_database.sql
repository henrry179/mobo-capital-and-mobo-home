-- =============================================================================
-- 202610210001__grant_n8n_create_on_database.sql
-- 目的：n8n 镜像入口会执行 CREATE SCHEMA IF NOT EXISTS "n8n"，
--       PostgreSQL 的库级 ACL 检查早于 IF NOT EXISTS 判断，
--       缺少 CREATE 权限会报 "permission denied for database db_mobobrain"。
-- 影响：仅授权，不改表结构；n8n Schema 本体仍由 01-init-dual-db.sql 以
--       AUTHORIZATION user_n8n 创建。
-- 回滚：REVOKE CREATE ON DATABASE db_mobobrain FROM user_n8n;
-- =============================================================================
\set ON_ERROR_STOP on

\c db_mobobrain postgres

GRANT CONNECT, TEMPORARY, CREATE ON DATABASE db_mobobrain TO user_n8n;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'n8n') THEN
        EXECUTE 'CREATE SCHEMA IF NOT EXISTS n8n AUTHORIZATION user_n8n';
    END IF;
END;
$$;

GRANT USAGE, CREATE ON SCHEMA n8n TO user_n8n;
