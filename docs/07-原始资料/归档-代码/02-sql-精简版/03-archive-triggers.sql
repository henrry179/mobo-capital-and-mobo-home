-- ============================================================================
-- 文件路径: /opt/mobo-stack/init-scripts/03-archive-triggers.sql
-- 目标数据库: db_archive (执行角色: user_archive)
-- 核心功能: 完读书籍、补录笔记、运动打卡、周期复盘自动幂等同步至 timeline_events
-- ============================================================================

\connect db_archive user_archive;

-- 1. 书籍状态变为 COMPLETED 时自动写入时间线
CREATE OR REPLACE FUNCTION fn_sync_reading_to_timeline()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'COMPLETED' AND (OLD.status IS DISTINCT FROM 'COMPLETED' OR TG_OP = 'INSERT') THEN
        INSERT INTO timeline_events (
            event_date, category, title, summary, importance, tags,
            source_table, source_record_id, is_sensitive
        ) VALUES (
            COALESCE(NEW.completed_date, CURRENT_DATE),
            'reading',
            '读完《' || NEW.title || '》',
            COALESCE(NEW.core_takeaway, '完成全书阅读与核心洞察归档。'),
            COALESCE(NEW.rating, 4),
            NEW.tags,
            'reading_items',
            NEW.id,
            FALSE
        )
        ON CONFLICT (source_table, source_record_id) DO UPDATE SET
            event_date = EXCLUDED.event_date,
            title = EXCLUDED.title,
            summary = EXCLUDED.summary,
            importance = EXCLUDED.importance;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_reading_to_timeline ON reading_items;
CREATE TRIGGER trg_sync_reading_to_timeline
AFTER INSERT OR UPDATE ON reading_items
FOR EACH ROW EXECUTE FUNCTION fn_sync_reading_to_timeline();

-- 2. 事后补改 reading_items.core_takeaway 时自动回刷时间线摘要
CREATE OR REPLACE FUNCTION fn_update_reading_takeaway_timeline()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.core_takeaway IS DISTINCT FROM OLD.core_takeaway THEN
        UPDATE timeline_events
        SET summary = NEW.core_takeaway
        WHERE source_table = 'reading_items' AND source_record_id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_reading_takeaway ON reading_items;
CREATE TRIGGER trg_update_reading_takeaway
AFTER UPDATE ON reading_items
FOR EACH ROW EXECUTE FUNCTION fn_update_reading_takeaway_timeline();

-- 3. 录入运动训练 (fitness_workouts) 时自动同步至时间线
CREATE OR REPLACE FUNCTION fn_sync_workout_to_timeline()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO timeline_events (
        event_date, category, title, summary, importance,
        mood_score, energy_score, tags, source_table, source_record_id, is_sensitive
    ) VALUES (
        NEW.workout_date,
        'fitness',
        '自律训练：' || upper(NEW.workout_type) || ' (' || NEW.duration_minutes || ' 分钟)',
        COALESCE(NEW.notes, '完成日常体能与抗阻训练打卡。'),
        3,
        8,
        8,
        ARRAY['健身自律', NEW.workout_type],
        'fitness_workouts',
        NEW.id,
        FALSE
    )
    ON CONFLICT (source_table, source_record_id) DO UPDATE SET
        title = EXCLUDED.title,
        summary = EXCLUDED.summary;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_workout_to_timeline ON fitness_workouts;
CREATE TRIGGER trg_sync_workout_to_timeline
AFTER INSERT OR UPDATE ON fitness_workouts
FOR EACH ROW EXECUTE FUNCTION fn_sync_workout_to_timeline();

-- 4. 录入周期复盘 (project_retrospectives) 时自动同步至时间线
CREATE OR REPLACE FUNCTION fn_sync_retro_to_timeline()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO timeline_events (
        event_date, category, title, summary, importance,
        tags, source_table, source_record_id, is_sensitive
    ) VALUES (
        NEW.review_date,
        'reflection',
        '[' || upper(NEW.period_type) || ' 复盘] ' || NEW.title,
        COALESCE(NEW.achievements, left(NEW.content_markdown, 200)),
        4,
        ARRAY['周期复盘', NEW.period_type],
        'project_retrospectives',
        NEW.id,
        NEW.is_sensitive
    )
    ON CONFLICT (source_table, source_record_id) DO UPDATE SET
        title = EXCLUDED.title,
        summary = EXCLUDED.summary,
        is_sensitive = EXCLUDED.is_sensitive;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_retro_to_timeline ON project_retrospectives;
CREATE TRIGGER trg_sync_retro_to_timeline
AFTER INSERT OR UPDATE ON project_retrospectives
FOR EACH ROW EXECUTE FUNCTION fn_sync_retro_to_timeline();