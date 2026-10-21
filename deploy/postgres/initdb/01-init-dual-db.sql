-- =============================================================================
-- 01-init-dual-db.sql
-- 单 PostgreSQL 16 实例：双数据库 + 四 Schema + 最小权限账号（v2.1）
-- 仅由 docker-entrypoint-initdb.d 在空数据卷首次启动时执行
-- 依赖环境变量：PG_PASS_MOBOBRAIN / PG_PASS_ARCHIVE /
--              N8N_DB_PASSWORD / DASHBOARD_DB_PASSWORD / BACKUP_DB_PASSWORD
-- 数据库名固定为 db_mobobrain / db_archive（后续 SQL 脚本按字面量引用）
-- Schema 划分：
--   db_mobobrain : intel(采集与发布流水) / capital(投研·基金·终端) / n8n
--   db_archive   : archive(个人数字档案)
-- =============================================================================

\set ON_ERROR_STOP on

\getenv mobobrain_pw PG_PASS_MOBOBRAIN
\getenv archive_pw   PG_PASS_ARCHIVE
\getenv n8n_pw       N8N_DB_PASSWORD
\getenv dashboard_pw DASHBOARD_DB_PASSWORD
\getenv backup_pw    BACKUP_DB_PASSWORD

-- -----------------------------------------------------------------------------
-- 1. 角色（幂等：存在则改密，不存在则创建）
-- -----------------------------------------------------------------------------
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', 'user_mobobrain', :'mobobrain_pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'user_mobobrain')
\gexec

SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', 'user_archive', :'archive_pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'user_archive')
\gexec

SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', 'user_n8n', :'n8n_pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'user_n8n')
\gexec

SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', 'user_dashboard_ro', :'dashboard_pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'user_dashboard_ro')
\gexec

SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', 'user_backup', :'backup_pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'user_backup')
\gexec

ALTER ROLE user_mobobrain    PASSWORD :'mobobrain_pw';
ALTER ROLE user_archive      PASSWORD :'archive_pw';
ALTER ROLE user_n8n          PASSWORD :'n8n_pw';
ALTER ROLE user_dashboard_ro PASSWORD :'dashboard_pw';
ALTER ROLE user_backup       PASSWORD :'backup_pw';

-- 备份账号只读全库；不授予超级用户
GRANT pg_read_all_data TO user_backup;

-- -----------------------------------------------------------------------------
-- 2. 数据库（CREATE DATABASE 不能放在事务/DO 块中）
-- -----------------------------------------------------------------------------
SELECT 'CREATE DATABASE db_mobobrain OWNER user_mobobrain ENCODING ''UTF8'''
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'db_mobobrain')
\gexec

SELECT 'CREATE DATABASE db_archive OWNER user_archive ENCODING ''UTF8'''
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'db_archive')
\gexec

REVOKE ALL ON DATABASE db_mobobrain FROM PUBLIC;
REVOKE ALL ON DATABASE db_archive   FROM PUBLIC;

GRANT CONNECT, TEMPORARY ON DATABASE db_mobobrain TO user_mobobrain;
-- n8n 需要库级 CREATE 权限：镜像入口会执行 CREATE SCHEMA IF NOT EXISTS "n8n"，
-- 而 PostgreSQL 的 ACL 检查早于 IF NOT EXISTS 的存在性判断，缺 CREATE 会报
-- "permission denied for database"。Schema 本体已由本脚本以 AUTHORIZATION 建好。
GRANT CONNECT, TEMPORARY, CREATE ON DATABASE db_mobobrain TO user_n8n;
GRANT CONNECT           ON DATABASE db_mobobrain TO user_backup;

GRANT CONNECT, TEMPORARY ON DATABASE db_archive TO user_archive;
GRANT CONNECT           ON DATABASE db_archive TO user_dashboard_ro;
GRANT CONNECT           ON DATABASE db_archive TO user_backup;

-- -----------------------------------------------------------------------------
-- 3. db_mobobrain：intel 采集 Schema + capital 投研 Schema + n8n 自动化 Schema
-- -----------------------------------------------------------------------------
\c db_mobobrain

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS vector;

CREATE SCHEMA IF NOT EXISTS intel   AUTHORIZATION user_mobobrain;
CREATE SCHEMA IF NOT EXISTS capital AUTHORIZATION user_mobobrain;
CREATE SCHEMA IF NOT EXISTS n8n     AUTHORIZATION user_n8n;

GRANT USAGE, CREATE ON SCHEMA intel   TO user_mobobrain;
GRANT USAGE, CREATE ON SCHEMA capital TO user_mobobrain;
GRANT USAGE, CREATE ON SCHEMA n8n     TO user_n8n;

-- n8n 需要读写自己的 Schema；业务账号不在 n8n Schema 建表
GRANT USAGE ON SCHEMA n8n TO user_mobobrain;

-- 备份账号对三张业务 Schema 只读
GRANT USAGE ON SCHEMA intel   TO user_backup;
GRANT USAGE ON SCHEMA capital TO user_backup;
GRANT USAGE ON SCHEMA n8n     TO user_backup;

-- -----------------------------------------------------------------------------
-- 4. db_archive：archive Schema
-- -----------------------------------------------------------------------------
\c db_archive

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS vector;

CREATE SCHEMA IF NOT EXISTS archive AUTHORIZATION user_archive;

GRANT USAGE, CREATE ON SCHEMA archive TO user_archive;
GRANT USAGE ON SCHEMA archive TO user_dashboard_ro;

-- 看板只读：默认权限 + 已有表（05 中再补一次）
ALTER DEFAULT PRIVILEGES FOR ROLE user_archive IN SCHEMA archive
    GRANT SELECT ON TABLES TO user_dashboard_ro;

-- -----------------------------------------------------------------------------
-- 5. 说明
-- -----------------------------------------------------------------------------
-- 1) 本文件只负责“空库初始化”。后续 DDL 变更必须走 migrations/。
-- 2) 应用账号不得使用 postgres 超级用户。
-- 3) 密码通过 .env 注入；不要把真实密码写入本文件或 Git。
-- 4) 若需重建数据库，先备份，再删除数据卷；不要在生产直接 DROP。
