-- 策展公域人生叙事 → archive.timeline_events (privacy=PUBLIC)
-- 幂等：source_table='site_editorial' + 稳定 source_id (uuid5)
-- docker exec -i mobo-postgres psql -U postgres -d db_archive -v ON_ERROR_STOP=1 < tools/local/seed_public_life_stories.sql

BEGIN;

INSERT INTO archive.timeline_events (
    event_id, title, summary, domain, event_type, occurred_at,
    importance_score, energy_impact, location_name,
    source_table, source_id, tags, metrics_payload, privacy
) VALUES
(
    '1702ddc5-4f49-50a3-ba5a-29c06e07640f',
    '武汉三线融合定稿：主线财务数字化 × Memo × 多资产研究',
    '将学术哲学母本、定居规划、认知机制、内容工业化与 Local-First 第二大脑贯通为同一套人生算法。',
    'FAMILY_LIFE', 'milestone', '2026-10-07 12:00:00+08',
    5, 5, '武汉',
    'site_editorial', '1702ddc5-4f49-50a3-ba5a-29c06e07640f',
    ARRAY['三线融合', '慢就是快', 'Local-First', '时间主权'],
    $json${
      "editorial_slug": "home-2026-1007",
      "life_chapter": "湖北·归航与长期筑基",
      "mood_score": 9,
      "content_markdown": "2036 愿景不是规模崇拜，而是：职业卡位稳、家庭与住房落地、媒体品牌可复利、自营研究可审计。五大账户隔离与健康优先宪法，是一切仓位之上的安全壁垒。\n\n技术基座选择本地优先与端到端加密——把「一人一亿」的镜像倒转成可长期持有的主权数字家园。",
      "attached_media": [
        {
          "asset_type": "photo",
          "title": "长江岸线散步与周期思考",
          "public_thumb_url": "https://images.unsplash.com/photo-1477414348463-c0eb7f1359b6?auto=format&fit=crop&w=800&q=80"
        }
      ]
    }$json$::jsonb,
    'PUBLIC'
),
(
    '8a39f924-17fe-5365-8184-d697b91359d8',
    '从北上深数据战场归航武汉：人生仓位的风险隔离',
    '十余年零售与生鲜供应链数据深耕后，选择湖北作为长期家庭与投研根据地。',
    'FAMILY_LIFE', 'milestone', '2026-02-15 12:00:00+08',
    5, 5, '武汉',
    'site_editorial', '8a39f924-17fe-5365-8184-d697b91359d8',
    ARRAY['归航', '家庭筑基', '莫伯之家'],
    $json${
      "editorial_slug": "home-2026-0215",
      "life_chapter": "湖北·归航与长期筑基",
      "mood_score": 9,
      "content_markdown": "用交易员的风险隔离模型审视人生：真正的复利需要稳定底仓。归航不是撤退，而是把时间主权从高频噪声里夺回来——Slow Empowerment。"
    }$json$::jsonb,
    'PUBLIC'
),
(
    '9d60402e-43b0-56c7-be98-4f71232eefe1',
    '上海深耕：生鲜供应链周转率与多仓协同',
    '多温区仓储网络数字化与呆滞库存压降，训练微观现金流手感。',
    'CAREER_WORK', 'career', '2024-10-10 12:00:00+08',
    4, 5, '上海',
    'site_editorial', '9d60402e-43b0-56c7-be98-4f71232eefe1',
    ARRAY['供应链', '周转率', '业财'],
    $json${
      "editorial_slug": "home-2024-1010",
      "life_chapter": "上海·供应链深耕",
      "mood_score": 8,
      "content_markdown": "生鲜的核心是「鲜」与「转」。SKU 周转预测与动态补货，让微观库存语言后来能对接宏观 PMI 订单-库存差与期权波动率曲面——同一套因果语法。"
    }$json$::jsonb,
    'PUBLIC'
),
(
    '339bac70-9bf5-56fb-a774-e40ee2052b10',
    '北上深历练：物流调度与生鲜 B2B 数据基建',
    '从 BI 分析师走向业务战略操盘，理解规模效应与边际成本。',
    'CAREER_WORK', 'career', '2018-05-20 12:00:00+08',
    4, 5, '北京 / 深圳',
    'site_editorial', '339bac70-9bf5-56fb-a774-e40ee2052b10',
    ARRAY['物流', '数仓', '高强度作战'],
    $json${
      "editorial_slug": "home-2018-0520",
      "life_chapter": "北上深·历练期",
      "mood_score": 8,
      "content_markdown": "公路干线与大仓运营教会了我：没有现金流闭环的叙事都是噪声。这段经历成为后来 ITPM 宏观框架与企业基本面复盘的思维底座。"
    }$json$::jsonb,
    'PUBLIC'
),
(
    'd21776af-2a50-576f-ad4f-7cd97944d229',
    '2015 股灾尾部记忆：宏观因果优先于模式识别',
    '亲历指数急挫后的身体记忆，固化「先机制、后预测」的研究纪律。',
    'INVEST_TRADING', 'reflection', '2015-08-01 12:00:00+08',
    5, 5, '中国',
    'site_editorial', 'd21776af-2a50-576f-ad4f-7cd97944d229',
    ARRAY['股灾', '尾部风险', '研究纪律'],
    $json${
      "editorial_slug": "home-2015-0801",
      "life_chapter": "北上深·历练期",
      "mood_score": 6,
      "content_markdown": "指数从高位回撤的那一周，比任何回测曲线都更清晰地写下：没有证伪条件的信念会杀人。此后所有 Memo 与交易复盘，必须先写清「如果我错了，会因为什么」。"
    }$json$::jsonb,
    'PUBLIC'
)
ON CONFLICT (source_table, source_id) DO UPDATE SET
    title = EXCLUDED.title,
    summary = EXCLUDED.summary,
    domain = EXCLUDED.domain,
    event_type = EXCLUDED.event_type,
    occurred_at = EXCLUDED.occurred_at,
    importance_score = EXCLUDED.importance_score,
    energy_impact = EXCLUDED.energy_impact,
    location_name = EXCLUDED.location_name,
    tags = EXCLUDED.tags,
    metrics_payload = EXCLUDED.metrics_payload,
    privacy = 'PUBLIC',
    updated_at = NOW();

COMMIT;

SELECT privacy, count(*) FROM archive.timeline_events GROUP BY 1 ORDER BY 1;
SELECT metrics_payload->>'editorial_slug' AS slug, metrics_payload->>'life_chapter' AS chapter
FROM archive.timeline_events
WHERE source_table = 'site_editorial'
ORDER BY occurred_at DESC;
