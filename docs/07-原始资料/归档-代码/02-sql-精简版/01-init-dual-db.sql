-- =============================================================================
-- [ARCHIVED / SANITIZED] 归档件：口令已全部替换为占位符，禁止直接用于生产。
-- 与主线 01~09.sql 的差异见 docs/07-原始资料/README.md。
-- =============================================================================
-- 文件路径: /opt/mobo-stack/init-scripts/01-init-dual-db.sql
-- 核心功能: 创建 db_mobobrain (莫伯资本) 与 db_archive (莫伯之家)，实施物理级权限硬隔离
-- ============================================================================

-- 1. 创建独立业务角色
CREATE USER user_mobobrain WITH PASSWORD 'ChangeMe_MoboBrainPass_2026!';
CREATE USER user_archive WITH PASSWORD 'ChangeMe_ArchiveVaultPass_2026!';

-- 2. 创建双数据库并指定 Owner
CREATE DATABASE db_mobobrain OWNER user_mobobrain ENCODING 'UTF8';
CREATE DATABASE db_archive OWNER user_archive ENCODING 'UTF8';

-- 3. 回收 PUBLIC 默认连接权限，杜绝跨库访问
REVOKE CONNECT ON DATABASE db_mobobrain FROM PUBLIC;
REVOKE CONNECT ON DATABASE db_archive FROM PUBLIC;

GRANT CONNECT, TEMPORARY ON DATABASE db_mobobrain TO user_mobobrain;
GRANT CONNECT, TEMPORARY ON DATABASE db_archive TO user_archive;

-- 4. 初始化 db_mobobrain 扩展与 Schema 权限
\connect db_mobobrain postgres
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO user_mobobrain;
ALTER DEFAULT PRIVILEGES FOR ROLE user_mobobrain IN SCHEMA public GRANT ALL ON TABLES TO user_mobobrain;
ALTER DEFAULT PRIVILEGES FOR ROLE user_mobobrain IN SCHEMA public GRANT ALL ON SEQUENCES TO user_mobobrain;

-- 5. 初始化 db_archive 扩展与 Schema 权限
\connect db_archive postgres
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO user_archive;
ALTER DEFAULT PRIVILEGES FOR ROLE user_archive IN SCHEMA public GRANT ALL ON TABLES TO user_archive;
ALTER DEFAULT PRIVILEGES FOR ROLE user_archive IN SCHEMA public GRANT ALL ON SEQUENCES TO user_archive;