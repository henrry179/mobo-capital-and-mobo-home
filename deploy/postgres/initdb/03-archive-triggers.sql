-- =============================================================================
-- 03-archive-triggers.sql
-- 网站 B：四大时间线自动同步触发器 + updated_at 维护函数
-- 目标库：db_archive；Schema：archive
-- =============================================================================

\set ON_ERROR_STOP on
\c db_archive

SET search_path TO archive, public;

-- -----------------------------------------------------------------------------
-- 0. 通用 updated_at
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION archive.fn_touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

-- -----------------------------------------------------------------------------
-- 1. 书籍完读 -> 时间线
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION archive.fn_sync_reading_to_timeline()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_minutes INTEGER := 0;
    v_notes_count   INTEGER := 0;
    v_occurred_at   TIMESTAMPTZ;
    v_ended_at      TIMESTAMPTZ;
    v_importance    SMALLINT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM archive.timeline_events
        WHERE source_table = 'reading_items' AND source_id = OLD.item_id;
        RETURN OLD;
    END IF;

    -- 非 COMPLETED：如果之前是 COMPLETED，清理旧节点
    IF NEW.status <> 'COMPLETED' THEN
        IF TG_OP = 'UPDATE' AND OLD.status = 'COMPLETED' THEN
            DELETE FROM archive.timeline_events
            WHERE source_table = 'reading_items' AND source_id = NEW.item_id;
        END IF;
        RETURN NEW;
    END IF;

    SELECT COALESCE(SUM(duration_minutes) FILTER (WHERE log_type = 'SESSION'), 0),
           COUNT(*) FILTER (WHERE log_type IN ('HIGHLIGHT', 'THOUGHT'))
    INTO v_total_minutes, v_notes_count
    FROM archive.reading_logs
    WHERE item_id = NEW.item_id;

    -- finished_at 是 DATE：默认按当天 20:00 作为结束；无日期则用 NOW()
    v_ended_at := COALESCE(NEW.finished_at::timestamptz + INTERVAL '20 hours', NOW());
    v_occurred_at := LEAST(
        COALESCE(NEW.started_at::timestamptz + INTERVAL '9 hours', v_ended_at),
        v_ended_at
    );
    v_importance := CASE
        WHEN NEW.rating IS NOT NULL THEN GREATEST(1, LEAST(10, ROUND(NEW.rating)::smallint))
        ELSE 6
    END;

    INSERT INTO archive.timeline_events (
        title, summary, domain, event_type, occurred_at, ended_at,
        importance_score, energy_impact, duration_minutes,
        source_table, source_id, tags, metrics_payload, privacy
    ) VALUES (
        '读完《' || NEW.title || '》',
        COALESCE(NEW.core_takeaways, '完成阅读并归档核心笔记。'),
        NEW.domain, 'BOOK_FINISHED', v_occurred_at, v_ended_at,
        v_importance, 2, v_total_minutes,
        'reading_items', NEW.item_id, NEW.tags,
        jsonb_strip_nulls(jsonb_build_object(
            'item_type', NEW.item_type,
            'authors', NEW.authors,
            'total_pages', NEW.total_pages,
            'rating', NEW.rating,
            'notes_count', v_notes_count
        )), 'PRIVATE'
    )
    ON CONFLICT (source_table, source_id) DO UPDATE SET
        title = EXCLUDED.title,
        summary = EXCLUDED.summary,
        domain = EXCLUDED.domain,
        event_type = EXCLUDED.event_type,
        occurred_at = EXCLUDED.occurred_at,
        ended_at = EXCLUDED.ended_at,
        importance_score = EXCLUDED.importance_score,
        energy_impact = EXCLUDED.energy_impact,
        duration_minutes = EXCLUDED.duration_minutes,
        tags = EXCLUDED.tags,
        metrics_payload = EXCLUDED.metrics_payload,
        privacy = EXCLUDED.privacy,
        updated_at = NOW();

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_reading_to_timeline ON archive.reading_items;
CREATE TRIGGER trg_sync_reading_to_timeline
    AFTER INSERT OR UPDATE OR DELETE ON archive.reading_items
    FOR EACH ROW EXECUTE FUNCTION archive.fn_sync_reading_to_timeline();

-- -----------------------------------------------------------------------------
-- 2. 阅读日志变更 -> 刷新时间线统计
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION archive.fn_refresh_reading_timeline_stats()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_target_item_id UUID;
    v_total_minutes  INTEGER := 0;
    v_notes_count    INTEGER := 0;
BEGIN
    -- DELETE 时不能引用 NEW；必须按 TG_OP 取 OLD
    IF TG_OP = 'DELETE' THEN
        v_target_item_id := OLD.item_id;
    ELSE
        v_target_item_id := NEW.item_id;
    END IF;

    IF EXISTS (
        SELECT 1 FROM archive.timeline_events
        WHERE source_table = 'reading_items' AND source_id = v_target_item_id
    ) THEN
        SELECT COALESCE(SUM(duration_minutes) FILTER (WHERE log_type = 'SESSION'), 0),
               COUNT(*) FILTER (WHERE log_type IN ('HIGHLIGHT', 'THOUGHT'))
        INTO v_total_minutes, v_notes_count
        FROM archive.reading_logs
        WHERE item_id = v_target_item_id;

        UPDATE archive.timeline_events
        SET duration_minutes = v_total_minutes,
            metrics_payload = jsonb_set(
                COALESCE(metrics_payload, '{}'::jsonb),
                '{notes_count}',
                to_jsonb(v_notes_count),
                true
            ),
            updated_at = NOW()
        WHERE source_table = 'reading_items' AND source_id = v_target_item_id;
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_refresh_reading_timeline_stats ON archive.reading_logs;
CREATE TRIGGER trg_refresh_reading_timeline_stats
    AFTER INSERT OR UPDATE OR DELETE ON archive.reading_logs
    FOR EACH ROW EXECUTE FUNCTION archive.fn_refresh_reading_timeline_stats();

-- -----------------------------------------------------------------------------
-- 3. 运动训练 -> 时间线
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION archive.fn_sync_workout_to_timeline()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_auto_title VARCHAR(255);
    v_ended_at   TIMESTAMPTZ;
    v_importance SMALLINT := 5;
    v_energy     SMALLINT := 2;
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM archive.timeline_events
        WHERE source_table = 'fitness_workouts' AND source_id = OLD.workout_id;
        RETURN OLD;
    END IF;

    IF NEW.title IS NOT NULL AND btrim(NEW.title) <> '' THEN
        v_auto_title := NEW.title;
    ELSIF NEW.workout_type = 'RUNNING' AND NEW.distance_meters IS NOT NULL THEN
        v_auto_title := FORMAT('跑步训练 · %s km (%s min)',
            ROUND(NEW.distance_meters / 1000.0, 2), NEW.duration_minutes);
    ELSIF NEW.workout_type = 'STRENGTH' AND NEW.total_volume_kg IS NOT NULL THEN
        v_auto_title := FORMAT('力量训练 · 容量 %s 吨 (%s min)',
            ROUND(NEW.total_volume_kg / 1000.0, 2), NEW.duration_minutes);
    ELSE
        v_auto_title := FORMAT('%s 训练 (%s min)',
            UPPER(NEW.workout_type), NEW.duration_minutes);
    END IF;

    v_ended_at := GREATEST(
        NEW.started_at,
        COALESCE(NEW.ended_at, NEW.started_at + (NEW.duration_minutes || ' minutes')::interval)
    );

    IF COALESCE(NEW.distance_meters, 0) >= 15000
       OR COALESCE(NEW.rpe_score, 0) >= 8.5
       OR NEW.duration_minutes >= 90 THEN
        v_importance := 7;
        v_energy := 3;
    END IF;

    INSERT INTO archive.timeline_events (
        title, summary, domain, event_type, occurred_at, ended_at,
        importance_score, energy_impact, duration_minutes,
        source_table, source_id, tags, metrics_payload, privacy
    ) VALUES (
        v_auto_title, NEW.notes, 'FITNESS_HEALTH',
        'WORKOUT_' || UPPER(NEW.workout_type),
        NEW.started_at, v_ended_at, v_importance, v_energy, NEW.duration_minutes,
        'fitness_workouts', NEW.workout_id, NEW.tags,
        jsonb_strip_nulls(jsonb_build_object(
            'workout_type', NEW.workout_type,
            'calories_kcal', NEW.calories_kcal,
            'avg_heart_rate', NEW.avg_heart_rate,
            'rpe_score', NEW.rpe_score,
            'distance_meters', NEW.distance_meters,
            'avg_pace_sec_km', NEW.avg_pace_sec_km,
            'total_volume_kg', NEW.total_volume_kg,
            'total_sets', NEW.total_sets
        )), 'PRIVATE'
    )
    ON CONFLICT (source_table, source_id) DO UPDATE SET
        title = EXCLUDED.title,
        summary = EXCLUDED.summary,
        event_type = EXCLUDED.event_type,
        occurred_at = EXCLUDED.occurred_at,
        ended_at = EXCLUDED.ended_at,
        importance_score = EXCLUDED.importance_score,
        energy_impact = EXCLUDED.energy_impact,
        duration_minutes = EXCLUDED.duration_minutes,
        tags = EXCLUDED.tags,
        metrics_payload = EXCLUDED.metrics_payload,
        privacy = EXCLUDED.privacy,
        updated_at = NOW();

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_workout_to_timeline ON archive.fitness_workouts;
CREATE TRIGGER trg_sync_workout_to_timeline
    AFTER INSERT OR UPDATE OR DELETE ON archive.fitness_workouts
    FOR EACH ROW EXECUTE FUNCTION archive.fn_sync_workout_to_timeline();

-- -----------------------------------------------------------------------------
-- 4. 结构化复盘 -> 时间线
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION archive.fn_sync_retro_to_timeline()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_summary     TEXT;
    v_importance  SMALLINT;
    v_occurred_at TIMESTAMPTZ;
    v_ended_at    TIMESTAMPTZ;
BEGIN
    IF TG_OP = 'DELETE' THEN
        DELETE FROM archive.timeline_events
        WHERE source_table = 'project_retrospectives' AND source_id = OLD.retro_id;
        RETURN OLD;
    END IF;

    v_occurred_at := NEW.period_start::timestamptz;
    v_ended_at := NEW.period_end::timestamptz + INTERVAL '23 hours 59 minutes 59 seconds';

    v_summary := CONCAT_WS(E'\n',
        CASE
            WHEN NEW.codified_principles IS NOT NULL AND btrim(NEW.codified_principles) <> ''
            THEN '【原则迭代】' || NEW.codified_principles
        END,
        CASE
            WHEN NEW.root_cause_analysis IS NOT NULL AND btrim(NEW.root_cause_analysis) <> ''
            THEN '【偏差归因】' || NEW.root_cause_analysis
        END
    );

    v_importance := CASE
        WHEN NEW.retro_type IN ('PROJECT_POSTMORTEM', 'TRADING_PLAYBOOK', 'EXAM_STAGE') THEN 8
        ELSE 6
    END;

    INSERT INTO archive.timeline_events (
        title, summary, domain, event_type, occurred_at, ended_at,
        importance_score, energy_impact, source_table, source_id,
        tags, metrics_payload, privacy
    ) VALUES (
        NEW.title, NULLIF(v_summary, ''), NEW.domain,
        'RETRO_' || UPPER(NEW.retro_type),
        v_occurred_at, v_ended_at, v_importance,
        COALESCE(NEW.execution_score - 5, 1),
        'project_retrospectives', NEW.retro_id, NEW.tags,
        jsonb_strip_nulls(jsonb_build_object(
            'retro_type', NEW.retro_type,
            'execution_score', NEW.execution_score,
            'outcome_score', NEW.outcome_score,
            'kpi_snapshot', NEW.kpi_snapshot
        )), NEW.privacy
    )
    ON CONFLICT (source_table, source_id) DO UPDATE SET
        title = EXCLUDED.title,
        summary = EXCLUDED.summary,
        domain = EXCLUDED.domain,
        event_type = EXCLUDED.event_type,
        occurred_at = EXCLUDED.occurred_at,
        ended_at = EXCLUDED.ended_at,
        importance_score = EXCLUDED.importance_score,
        energy_impact = EXCLUDED.energy_impact,
        tags = EXCLUDED.tags,
        metrics_payload = EXCLUDED.metrics_payload,
        privacy = EXCLUDED.privacy,
        updated_at = NOW();

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_retro_to_timeline ON archive.project_retrospectives;
CREATE TRIGGER trg_sync_retro_to_timeline
    AFTER INSERT OR UPDATE OR DELETE ON archive.project_retrospectives
    FOR EACH ROW EXECUTE FUNCTION archive.fn_sync_retro_to_timeline();

-- -----------------------------------------------------------------------------
-- 5. 说明
-- -----------------------------------------------------------------------------
-- 1) 所有写时间线均使用 ON CONFLICT (source_table, source_id) 幂等。
-- 2) 删除源记录 / 状态回退会清理对应时间线节点。
-- 3) 阅读日志触发器只刷新已存在的时间线节点，不主动创建。
-- 4) updated_at 统一触发器在 06 中挂到所有含该列的表。
