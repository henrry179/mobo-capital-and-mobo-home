-- =============================================================================
-- 09-updated-at-triggers.sql
-- 为 archive / intel / capital 中所有含 updated_at 的表统一挂 BEFORE UPDATE 触发器
-- =============================================================================

\set ON_ERROR_STOP on

-- =============================================================================
-- A. db_archive
-- =============================================================================
\c db_archive

CREATE OR REPLACE FUNCTION archive.fn_touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DO $$
DECLARE
    r RECORD;
    v_trigger_name TEXT;
BEGIN
    FOR r IN
        SELECT c.table_schema, c.table_name
        FROM information_schema.columns c
        JOIN information_schema.tables t
          ON t.table_schema = c.table_schema
         AND t.table_name = c.table_name
        WHERE c.table_schema = 'archive'
          AND c.column_name = 'updated_at'
          AND t.table_type = 'BASE TABLE'
    LOOP
        v_trigger_name := 'trg_touch_updated_at_' || r.table_name;
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I.%I',
                       v_trigger_name, r.table_schema, r.table_name);
        EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON %I.%I FOR EACH ROW EXECUTE FUNCTION archive.fn_touch_updated_at()',
                       v_trigger_name, r.table_schema, r.table_name);
    END LOOP;
END;
$$;

-- =============================================================================
-- B. db_mobobrain
-- =============================================================================
\c db_mobobrain

CREATE OR REPLACE FUNCTION intel.fn_touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DO $$
DECLARE
    r RECORD;
    v_trigger_name TEXT;
BEGIN
    FOR r IN
        SELECT c.table_schema, c.table_name
        FROM information_schema.columns c
        JOIN information_schema.tables t
          ON t.table_schema = c.table_schema
         AND t.table_name = c.table_name
        WHERE c.table_schema = 'intel'
          AND c.column_name = 'updated_at'
          AND t.table_type = 'BASE TABLE'
    LOOP
        v_trigger_name := 'trg_touch_updated_at_' || r.table_name;
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I.%I',
                       v_trigger_name, r.table_schema, r.table_name);
        EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON %I.%I FOR EACH ROW EXECUTE FUNCTION intel.fn_touch_updated_at()',
                       v_trigger_name, r.table_schema, r.table_name);
    END LOOP;
END;
$$;

-- =============================================================================
-- C. db_mobobrain · capital 投研域
-- =============================================================================
\c db_mobobrain

CREATE OR REPLACE FUNCTION capital.fn_touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = capital, public
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DO $$
DECLARE
    r RECORD;
    v_trigger_name TEXT;
BEGIN
    FOR r IN
        SELECT c.table_schema, c.table_name
        FROM information_schema.columns c
        JOIN information_schema.tables t
          ON t.table_schema = c.table_schema
         AND t.table_name = c.table_name
        WHERE c.table_schema = 'capital'
          AND c.column_name = 'updated_at'
          AND t.table_type = 'BASE TABLE'
    LOOP
        v_trigger_name := 'trg_touch_updated_at_' || r.table_name;
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I.%I',
                       v_trigger_name, r.table_schema, r.table_name);
        EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON %I.%I FOR EACH ROW EXECUTE FUNCTION capital.fn_touch_updated_at()',
                       v_trigger_name, r.table_schema, r.table_name);
    END LOOP;
END;
$$;

-- =============================================================================
-- D. 说明
-- =============================================================================
-- n8n 自己的表由 n8n 迁移管理，不挂本项目触发器。
-- 触发器只更新 updated_at，不改变业务字段。
