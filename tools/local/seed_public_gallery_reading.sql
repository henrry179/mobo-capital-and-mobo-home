-- 公域图库（PUBLIC assets）+ 公域书单（tags 含 public_portal）
-- docker exec -i mobo-postgres psql -U postgres -d db_archive -v ON_ERROR_STOP=1 < tools/local/seed_public_gallery_reading.sql

BEGIN;

-- 图库：稳定 asset_id / sha256 / oss key（幂等 upsert by oss object）
INSERT INTO archive.archive_assets (
    asset_id, asset_category, title, original_filename, mime_type, file_size_bytes,
    sha256_hash, oss_bucket, oss_object_key, current_tier,
    captured_at, document_date, media_metadata, domain, tags, privacy
) VALUES
(
    'a1111111-1111-5111-8111-111111111101',
    'PHOTO', '武汉东湖晨跑与体能训练', 'donghu-run.jpg', 'image/jpeg', 120000,
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1',
    'mobo-private', 'editorial/gallery/donghu-run.jpg', 'OSS_STANDARD',
    '2026-10-12 07:00:00+08', '2026-10-12',
    '{"public_thumb_url":"https://images.unsplash.com/photo-1517838277536-f5f99be501cd?auto=format&fit=crop&w=800&q=80","editorial_slug":"g1"}'::jsonb,
    'FITNESS_HEALTH', ARRAY['public_portal','武汉'], 'PUBLIC'
),
(
    'a1111111-1111-5111-8111-111111111102',
    'PHOTO', '莫伯之家书房与投研资料', 'study-desk.jpg', 'image/jpeg', 110000,
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa2',
    'mobo-private', 'editorial/gallery/study-desk.jpg', 'OSS_STANDARD',
    '2026-09-28 20:00:00+08', '2026-09-28',
    '{"public_thumb_url":"https://images.unsplash.com/photo-1497633762265-9d179a990aa6?auto=format&fit=crop&w=800&q=80","editorial_slug":"g2"}'::jsonb,
    'FAMILY_LIFE', ARRAY['public_portal','书房'], 'PUBLIC'
),
(
    'a1111111-1111-5111-8111-111111111103',
    'PHOTO', '长江岸线宏观思考', 'yangtze.jpg', 'image/jpeg', 130000,
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa3',
    'mobo-private', 'editorial/gallery/yangtze.jpg', 'OSS_STANDARD',
    '2026-08-15 18:00:00+08', '2026-08-15',
    '{"public_thumb_url":"https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=800&q=80","editorial_slug":"g3"}'::jsonb,
    'FAMILY_LIFE', ARRAY['public_portal','长江'], 'PUBLIC'
),
(
    'a1111111-1111-5111-8111-111111111104',
    'VIDEO', '秋季力量训练突破日', 'strength.jpg', 'image/jpeg', 140000,
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa4',
    'mobo-private', 'editorial/gallery/strength.jpg', 'OSS_STANDARD',
    '2026-10-01 19:00:00+08', '2026-10-01',
    '{"public_thumb_url":"https://images.unsplash.com/photo-1534438327276-14e5300c3a48?auto=format&fit=crop&w=800&q=80","editorial_slug":"g4"}'::jsonb,
    'FITNESS_HEALTH', ARRAY['public_portal','训练'], 'PUBLIC'
),
(
    'a1111111-1111-5111-8111-111111111105',
    'PHOTO', '阅读与跨学科笔记', 'reading-notes.jpg', 'image/jpeg', 100000,
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa5',
    'mobo-private', 'editorial/gallery/reading-notes.jpg', 'OSS_STANDARD',
    '2026-09-05 21:00:00+08', '2026-09-05',
    '{"public_thumb_url":"https://images.unsplash.com/photo-1481627834876-b7833e8f5570?auto=format&fit=crop&w=800&q=80","editorial_slug":"g5"}'::jsonb,
    'LEARNING_EXAM', ARRAY['public_portal','阅读'], 'PUBLIC'
)
ON CONFLICT (oss_bucket, oss_object_key) DO UPDATE SET
    title = EXCLUDED.title,
    media_metadata = EXCLUDED.media_metadata,
    tags = EXCLUDED.tags,
    privacy = 'PUBLIC',
    domain = EXCLUDED.domain,
    captured_at = EXCLUDED.captured_at,
    document_date = EXCLUDED.document_date,
    updated_at = NOW();

-- 书单：用 isbn_or_doi 作幂等键（无 privacy 列，靠 tag public_portal 进公域）
INSERT INTO archive.reading_items (
    item_id, item_type, title, authors, isbn_or_doi, language, status,
    rating, core_takeaways, domain, tags, finished_at
) VALUES
(
    'b2222222-2222-5222-8222-222222222201', 'BOOK', 'The Road to Reality',
    ARRAY['Roger Penrose'], 'editorial:b1', 'en', 'COMPLETED',
    5.0, '几何与物理底层结构，帮助理解复杂系统与非线性波动。',
    'LEARNING_EXAM', ARRAY['public_portal','PHYSICS'], '2024-01-01'
),
(
    'b2222222-2222-5222-8222-222222222202', 'BOOK', '穷查理宝典',
    ARRAY['Charlie Munger'], 'editorial:b2', 'zh-CN', 'COMPLETED',
    5.0, '多元思维模型与逆向思考；慢就是快。',
    'LEARNING_EXAM', ARRAY['public_portal','FINANCE'], '2023-06-01'
),
(
    'b2222222-2222-5222-8222-222222222203', 'BOOK', '原则 / Principles',
    ARRAY['Ray Dalio'], 'editorial:b3', 'zh-CN', 'COMPLETED',
    5.0, '债务周期模板与原则化决策，对接年度宏观旗舰写作。',
    'INVEST_TRADING', ARRAY['public_portal','FINANCE'], '2023-08-01'
),
(
    'b2222222-2222-5222-8222-222222222204', 'BOOK', '周期 / Mastering the Market Cycle',
    ARRAY['Howard Marks'], 'editorial:b4', 'zh-CN', 'COMPLETED',
    5.0, '第二层思维与 Memo 文风底座。',
    'INVEST_TRADING', ARRAY['public_portal','FINANCE'], '2023-09-01'
),
(
    'b2222222-2222-5222-8222-222222222205', 'BOOK', '孙子兵法',
    ARRAY['孙武'], 'editorial:b5', 'zh-CN', 'COMPLETED',
    5.0, '先胜而后求战——风险隔离铁律。',
    'LEARNING_EXAM', ARRAY['public_portal','STRATEGY'], '2022-01-01'
),
(
    'b2222222-2222-5222-8222-222222222206', 'BOOK', 'ITPM / POTM 课程笔记',
    ARRAY['Anton Kreil 体系'], 'editorial:b6', 'zh-CN', 'READING',
    5.0, '记分卡、门禁流程与期权策略筛选，正在双语精读归档。',
    'INVEST_TRADING', ARRAY['public_portal','FINANCE'], NULL
),
(
    'b2222222-2222-5222-8222-222222222207', 'BOOK', 'Trading in the Zone',
    ARRAY['Mark Douglas'], 'editorial:b7', 'en', 'COMPLETED',
    4.0, '概率思维与执行心理学，对接行为教练角色。',
    'INVEST_TRADING', ARRAY['public_portal','FINANCE'], '2024-03-01'
),
(
    'b2222222-2222-5222-8222-222222222208', 'BOOK', 'Local-First & E2EE 笔记',
    ARRAY['MoBo 工程札记'], 'editorial:b8', 'zh-CN', 'READING',
    4.0, '个人主权数字档案：加密、盲中继与第二大脑调度。',
    'SYSTEM_TECH', ARRAY['public_portal','STRATEGY'], NULL
)
ON CONFLICT (item_id) DO UPDATE SET
    title = EXCLUDED.title,
    authors = EXCLUDED.authors,
    status = EXCLUDED.status,
    rating = EXCLUDED.rating,
    core_takeaways = EXCLUDED.core_takeaways,
    domain = EXCLUDED.domain,
    tags = EXCLUDED.tags,
    isbn_or_doi = EXCLUDED.isbn_or_doi,
    finished_at = EXCLUDED.finished_at,
    updated_at = NOW();

COMMIT;

SELECT privacy, count(*) FROM archive.archive_assets WHERE deleted_at IS NULL GROUP BY 1;
SELECT count(*) FILTER (WHERE 'public_portal' = ANY(tags)) AS portal_books,
       count(*) AS all_books
FROM archive.reading_items;
