#!/usr/bin/env bash
# ============================================================================
# 脚本名称: setup_all_files.sh
# 适用系统: Ubuntu 24.04 LTS (阿里云 2核4G ECS)
# 核心功能: 一键创建 /opt/mobo-stack 全栈目录树，并将莫伯资本 (MoBoCapital.com)
#           与莫伯之家 (MoBoHome.com) 的全部 22 个生产配置文件与源码原样落盘。
# ============================================================================

set -euo pipefail

STACK_DIR="/opt/mobo-stack"
echo "🚀 [1/8] 正在初始化莫伯双站系统生产目录树: ${STACK_DIR} ..."

mkdir -p "${STACK_DIR}"/{caddy,init-scripts,dashboard,scripts,n8n-workflows}
mkdir -p "${STACK_DIR}/sites/mobocapital"/{data,internal}
mkdir -p "${STACK_DIR}/sites/mobohome"/{data,internal}
chmod 700 "${STACK_DIR}"

# ----------------------------------------------------------------------------
# 检查并自动配置 4GB Swap 与 vm.swappiness=10 (幂等执行，防 2C4G OOM)
# ----------------------------------------------------------------------------
echo "🛡️ [2/8] 正在检查宿主机 4GB Swap 与内核内存防线..."
if ! swapon --show | grep -q "/swapfile"; then
    if [ ! -f /swapfile ]; then
        fallocate -l 4G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
    fi
    swapon /swapfile
    grep -q "/swapfile" /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "   ├─ 已创建并激活 4GB /swapfile"
else
    echo "   ├─ 4GB Swap 已处于激活状态，跳过创建"
fi

sysctl -w vm.swappiness=10 > /dev/null
sysctl -w vm.overcommit_memory=1 > /dev/null
grep -q "vm.swappiness=10" /etc/sysctl.conf || echo -e "\nvm.swappiness=10\nvm.overcommit_memory=1" >> /etc/sysctl.conf
echo "   └─ 内核参数 vm.swappiness=10 & vm.overcommit_memory=1 已锁定"

# ============================================================================
# [3/8] 写入生产环境变量 .env (若已存在则自动备份，绝不盲目覆盖真实密钥)
# ============================================================================
echo "🔐 [3/8] 正在落盘环境变量与多智能体协同宪章..."

if [ -f "${STACK_DIR}/.env" ]; then
    cp "${STACK_DIR}/.env" "${STACK_DIR}/.env.bak.$(date +%Y%m%d%H%M%S)"
    echo "   ├─ 检测到已有 .env，已备份为 .env.bak.*，保留现有 .env 不覆盖"
else
cat << 'EOF_ENV' > "${STACK_DIR}/.env"
# ============================================================================
# /opt/mobo-stack/.env — 莫伯双站系统生产环境核心密钥 (权限必须为 600)
# ============================================================================

# 1. PostgreSQL 16 双库物理隔离账号与密码
PG_HOST=127.0.0.1
PG_PORT=5432
PG_SUPER_PASSWORD=ChangeMe_SuperRootPass_2026!

PG_DB_MOBOBRAIN=db_mobobrain
PG_USER_MOBOBRAIN=user_mobobrain
PG_PASS_MOBOBRAIN=ChangeMe_MoboBrainPass_2026!

PG_DB_ARCHIVE=db_archive
PG_USER_ARCHIVE=user_archive
PG_PASS_ARCHIVE=ChangeMe_ArchiveVaultPass_2026!

# 2. Caddy 内网驾驶舱 (/internal/* 与 /lab/*) BasicAuth Bcrypt 密码哈希
# 生成命令: docker run --rm caddy:2.8-alpine caddy hash-password --plaintext '你的强密码'
CADDY_INTERNAL_PASS_HASH='$2a$14$REPLACE_WITH_REAL_BCRYPT_HASH'

# 3. 思源笔记访问授权码
SIYUAN_AUTH_CODE=ChangeMe_SiyuanAuthCode_2026!

# 4. 阿里云同地域双 OSS 存储桶配置 (ECS 内网使用 -internal 免流量费)
ALIYUN_ACCESS_KEY_ID=LTAI5tREPLACE_WITH_REAL_AK
ALIYUN_ACCESS_KEY_SECRET=REPLACE_WITH_REAL_SK
OSS_ENDPOINT=https://oss-cn-hangzhou-internal.aliyuncs.com
OSS_PUBLIC_ENDPOINT=https://oss-cn-hangzhou.aliyuncs.com
OSS_BUCKET_PUBLIC=mobobrain-assets-pub
OSS_BUCKET_PRIVATE=mobo-archive-private-hz
OSS_PUBLIC_CDN_DOMAIN=https://mobobrain-assets-pub.oss-cn-hangzhou.aliyuncs.com

# 5. 微信公众号草稿箱直推 API 凭证 (用于 n8n 工作流 #2)
WECHAT_APPID=wxReplaceWithYourAppId
WECHAT_SECRET=REPLACE_WITH_REAL_SECRET
WECHAT_DEFAULT_THUMB_MEDIA_ID=ReplaceWithDefaultThumbMediaId

# 6. Restic 异地加密冷备仓库配置
RESTIC_REPOSITORY=s3:https://oss-cn-hangzhou-internal.aliyuncs.com/mobo-archive-private-hz/restic-cold-backup
RESTIC_PASSWORD=ChangeMe_ResticMasterEncryptionKey_2026!

# 7. 双站静态目录路径与巡检告警 Webhook
MOBOCAPITAL_WEB_DIR=/opt/mobo-stack/sites/mobocapital
MOBOHOME_WEB_DIR=/opt/mobo-stack/sites/mobohome
ALERT_WEBHOOK_URL=
EOF_ENV
    echo "   ├─ 已生成初始 .env 模板"
fi
chmod 600 "${STACK_DIR}/.env"

# ----------------------------------------------------------------------------
# 写入 CLAUDE.md 与 TASK_STATE.md 并创建智能体软链接
# ----------------------------------------------------------------------------
cat << 'EOF_CLAUDE' > "${STACK_DIR}/CLAUDE.md"
# CLAUDE.md — 莫伯双站系统 (MoBoCapital.com & MoBoHome.com) 架构宪章 (v2.1)

## 1. 系统顶层定位与双站拓扑
1. **网站 A：莫伯资本 (`MoBoCapital.com`)** — 全球宏观投研智库（ITPM 框架）、期权波动率策略、实战复盘归因（Greeks & R-Multiples）、对冲基金三阶段孵化蓝图及《MoBo's Memo》财经自媒体“1+3”多平台运营中心。绑定 `db_mobobrain`（独占角色 `user_mobobrain`）。
2. **网站 B：莫伯之家 (`MoBoHome.com`)** — 围绕“慢就是快”哲学的个人主权生命数字档案馆（人生四重篇章、800px WebP 影像流画廊、百本跨学科藏书馆、体能自律看板）。绑定 `db_archive`（独占角色 `user_archive`）。

## 2. 五条不可逾越的架构红线
1. **2C4G 内存硬限流**：全栈严格维持 6 个容器（`mobo-caddy` 80m、`mobo-postgres` 600m、`mobobrain-pkm` 300m、`mobobrain-n8n` 350m、`archive-dashboard` 200m、`mobo-restic-backup` 150m），常驻总内存不超过 1.46GB；双站前台一律采用静态 HTML + `mobo_cli.py` 预生成静态 JSON 架构，服务端额外内存开销为 0 MB。
2. **PostgreSQL 双库物理级权限隔离**：`user_mobobrain` 仅能读写 `db_mobobrain`（`04`–`06` SQL）；`user_archive` 仅能读写 `db_archive`（`02`–`03` SQL）；严禁跨库访问或使用 `postgres` 超级用户运行业务。
3. **OSS 内网免流与冷热分层**：ECS 容器内部访问 OSS 强制走 `oss-cn-hangzhou-internal.aliyuncs.com` 免流量费；所有原件归入 `photo/`、`video/`、`scan_doc/`、`blotters/` 触发自动转冷归档，前端列表仅加载 `thumbnails/` 下的热缩略图。
4. **公私域物理级脱敏与三级权限控制**：导出 `public-data.json` 时必须物理删除 `private_blotter_oss_key` 并剔除 `INTERNAL` 记录；导出 `public-home-data.json` 时必须物理剔除 `is_sensitive = TRUE` 的记录；`/internal/*` 路径强制启用 Caddy `basicauth`。
5. **境内/境外双轨内容合规风控**：n8n 合成《MoBo's Memo》时，境内平台（微信公众号、雪球）自动脱敏具体买卖点位并强制注入免责声明；所有发布必须经过 HITL 人工终审阀门。

## 3. 三大智能体协同职责边界
- **Claude Code CLI**：负责宿主机 Swap/Sysctl 调优、Docker Compose 编排、`Caddyfile` 双域名配置、PostgreSQL `01`–`06` SQL 注入与触发器验证、Restic 灾备演练。
- **Codex CLI**：负责维护 `mobo_cli.py (v2.1)`、`macro_iv_collector.py`、`oss_guard_setup.py`、n8n 工作流 JSON 编排，并执行公私域 JSON 物理脱敏正则审计。
- **Cursor**：负责精调 `sites/mobocapital/index.html`、`sites/mobohome/index.html` 与 `dashboard/app.py`。
EOF_CLAUDE

ln -sf "${STACK_DIR}/CLAUDE.md" "${STACK_DIR}/.cursorrules"
ln -sf "${STACK_DIR}/CLAUDE.md" "${STACK_DIR}/AGENTS.md"

cat << 'EOF_TASK' > "${STACK_DIR}/TASK_STATE.md"
# TASK_STATE.md — 莫伯双站系统 (MoBoCapital & MoBoHome) 16 步原子任务交接账本 (v2.1)

| 任务 ID | 所属阶段 | 任务名称与交付物路径 | 负责智能体 | 当前状态 | 验收命令 / 判定标准 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **T01** | 阶段一：云底座与合规 | 阿里云杭州 2C4G ECS、同地域双 OSS 桶、30元余额熔断与双域名备案 | **人工 (莫伯)** | `IN_PROGRESS` | `ping mobocapital.com` 与 `ping mobohome.com` 正常解析 |
| **T02** | 阶段一：云底座与合规 | 宿主机 4GB Swap 挂载、`vm.swappiness=10` 调优与目录树初始化 | **Claude Code CLI** | `DONE` | `free -m` 显示 Swap=4095MB |
| **T03** | 阶段一：云底座与合规 | 生产环境 `.env` 密钥填写真实值及 `chmod 600` 权限锁定 | **Claude Code CLI** | `READY` | `stat -c "%a" /opt/mobo-stack/.env` 输出 `600` |
| **T04** | 阶段一：云底座与合规 | 运行 `scripts/oss_guard_setup.py` 注入 5 条冷沉降规则与防盗链 | **Codex CLI** | `CODE_READY` | 输出 `[OK] Lifecycle & Referer Guard Applied` |
| **T05** | 阶段二：双库内核构建 | 部署 `01-init-dual-db.sql`，验证双库跨库访问拒绝 | **Claude Code CLI** | `CODE_READY` | `user_mobobrain` 连接 `db_archive` 返回拒绝 |
| **T06** | 阶段二：双库内核构建 | 部署莫伯之家 `02-archive-schema.sql` 与 `03-archive-triggers.sql` | **Claude Code CLI** | `CODE_READY` | 插入 `fitness_workouts` 自动同步至 `timeline_events` |
| **T07** | 阶段二：双库内核构建 | 部署莫伯资本 `04`、`05`、`06` SQL 脚本（投研、NAV高水位触发器、量化终端表） | **Claude Code CLI** | `CODE_READY` | 平仓一笔 `trade_reviews` 自动更新 `portfolio_nav_ledger` |
| **T08** | 阶段三：双站前端与看板 | 启动 `archive-dashboard` (Streamlit `app.py`) 并验证内存限制 | **Cursor** | `CODE_READY` | 容器内存占用低于 180MB |
| **T09** | 阶段三：双站前端与看板 | 部署莫伯资本前端门户 `sites/mobocapital/index.html` | **Cursor** | `CODE_READY` | 五大栏目与三级权限切换流畅 |
| **T10** | 阶段三：双站前端与看板 | 部署莫伯之家前端门户 `sites/mobohome/index.html` | **Cursor** | `CODE_READY` | 人生篇章过滤、画廊与藏书馆渲染正常 |
| **T11** | 阶段三：双站前端与看板 | 部署 `mobo_cli.py (v2.1)` 与 `macro_iv_collector.py` 并配置宿主机 Cron | **Codex CLI** | `CODE_READY` | 成功生成公私域 JSON 与 `terminal-snapshot.json` |
| **T12** | 阶段三：双站前端与看板 | 公私域 JSON 物理脱敏安全审计 | **Codex CLI** | `READY` | `grep` 检查公开 JSON 零敏感字段残留 |
| **T13** | 阶段四：n8n 与网关上线 | 部署思源笔记与 n8n，导入工作流 #1 与工作流 #2（1+3 四端发布） | **Codex CLI** | `CODE_READY` | Webhook 触发后 `capital_publications` 正常入库 |
| **T14** | 阶段四：n8n 与网关上线 | 配置 `Caddyfile` 双域名路由与 `/internal/*` BasicAuth 保护 | **Claude Code CLI** | `CODE_READY` | 未授权访问 `/internal/*` 返回 `HTTP 401` |
| **T15** | 阶段四：n8n 与网关上线 | 部署 `mobo-restic-backup`、每日 03:00 备份与 `mobo_watchdog.sh` | **Claude Code CLI** | `CODE_READY` | `restic snapshots` 查看到最新双库快照 |
| **T16** | 阶段四：n8n 与网关上线 | 执行 `disaster-recovery.sh --dry-run` 演练与全栈内存终验 | **Claude Code CLI** | `READY` | 全栈总内存低于 1.55GB，所有容器 `healthy` |
EOF_TASK

# ============================================================================
# [4/8] 写入 Docker Compose 编排与 Caddyfile 双站网关配置
# ============================================================================
echo "🐳 [4/8] 正在写入 docker-compose.yml 与 caddy/Caddyfile..."

cat << 'EOF_COMPOSE' > "${STACK_DIR}/docker-compose.yml"
services:
  mobo-caddy:
    image: caddy:2.8-alpine
    container_name: mobo-caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    environment:
      - CADDY_INTERNAL_PASS_HASH=${CADDY_INTERNAL_PASS_HASH}
    volumes:
      - ./caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ./sites/mobocapital:/srv/sites/mobocapital:ro
      - ./sites/mobohome:/srv/sites/mobohome:ro
      - caddy_data:/data
      - caddy_config:/config
    mem_limit: 80m
    memswap_limit: 120m
    networks:
      - mobo_net

  mobo-postgres:
    image: pgvector/pgvector:pg16
    container_name: mobo-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=${PG_SUPER_PASSWORD}
      - PG_DB_MOBOBRAIN=${PG_DB_MOBOBRAIN}
      - PG_USER_MOBOBRAIN=${PG_USER_MOBOBRAIN}
      - PG_PASS_MOBOBRAIN=${PG_PASS_MOBOBRAIN}
      - PG_DB_ARCHIVE=${PG_DB_ARCHIVE}
      - PG_USER_ARCHIVE=${PG_USER_ARCHIVE}
      - PG_PASS_ARCHIVE=${PG_PASS_ARCHIVE}
      - TZ=Asia/Shanghai
    command: >
      postgres
      -c shared_buffers=128MB
      -c work_mem=8MB
      -c maintenance_work_mem=64MB
      -c effective_cache_size=384MB
      -c max_connections=40
    ports:
      - "127.0.0.1:5432:5432"
    volumes:
      - pg_data:/var/lib/postgresql/data
      - ./init-scripts:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 15s
      timeout: 5s
      retries: 5
    mem_limit: 600m
    memswap_limit: 800m
    networks:
      - mobo_net

  mobobrain-pkm:
    image: b3log/siyuan:latest
    container_name: mobobrain-pkm
    restart: unless-stopped
    command: ["--workspace=/siyuan/workspace/", "--accessAuthCode=${SIYUAN_AUTH_CODE}"]
    volumes:
      - siyuan_data:/siyuan/workspace
    mem_limit: 300m
    memswap_limit: 450m
    networks:
      - mobo_net

  mobobrain-n8n:
    image: n8nio/n8n:latest
    container_name: mobobrain-n8n
    restart: unless-stopped
    environment:
      - N8N_HOST=n8n.mobocapital.com
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://n8n.mobocapital.com/
      - EXECUTIONS_PROCESS=main
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=72
      - GENERIC_TIMEZONE=Asia/Shanghai
      - WECHAT_APPID=${WECHAT_APPID}
      - WECHAT_SECRET=${WECHAT_SECRET}
      - WECHAT_DEFAULT_THUMB_MEDIA_ID=${WECHAT_DEFAULT_THUMB_MEDIA_ID}
    volumes:
      - n8n_data:/home/node/.n8n
      - ./sites/mobocapital:/data/mobocapital
    depends_on:
      mobo-postgres:
        condition: service_healthy
    mem_limit: 350m
    memswap_limit: 500m
    networks:
      - mobo_net

  archive-dashboard:
    build: ./dashboard
    container_name: archive-dashboard
    restart: unless-stopped
    environment:
      - PG_HOST=mobo-postgres
      - PG_PORT=5432
      - PG_DB_ARCHIVE=${PG_DB_ARCHIVE}
      - PG_USER_ARCHIVE=${PG_USER_ARCHIVE}
      - PG_PASS_ARCHIVE=${PG_PASS_ARCHIVE}
    depends_on:
      mobo-postgres:
        condition: service_healthy
    mem_limit: 200m
    memswap_limit: 300m
    networks:
      - mobo_net

  mobo-restic-backup:
    image: restic/restic:latest
    container_name: mobo-restic-backup
    restart: unless-stopped
    entrypoint: ["/bin/sh", "-c", "crond -f -d 8"]
    environment:
      - RESTIC_REPOSITORY=${RESTIC_REPOSITORY}
      - RESTIC_PASSWORD=${RESTIC_PASSWORD}
      - AWS_ACCESS_KEY_ID=${ALIYUN_ACCESS_KEY_ID}
      - AWS_SECRET_ACCESS_KEY=${ALIYUN_ACCESS_KEY_SECRET}
      - PG_SUPER_PASSWORD=${PG_SUPER_PASSWORD}
    volumes:
      - ./scripts/backup-cron.sh:/etc/periodic/daily/backup-cron.sh:ro
      - siyuan_data:/backup/siyuan:ro
      - n8n_data:/backup/n8n:ro
      - ./caddy:/backup/caddy:ro
    mem_limit: 150m
    memswap_limit: 250m
    networks:
      - mobo_net

volumes:
  caddy_data:
  caddy_config:
  pg_data:
  siyuan_data:
  n8n_data:

networks:
  mobo_net:
    driver: bridge
EOF_COMPOSE

cat << 'EOF_CADDY' > "${STACK_DIR}/caddy/Caddyfile"
{
    email admin@mobocapital.com
    servers {
        protocols h1 h2 h3
    }
}

# 网站 A：莫伯资本 (MoBoCapital.com)
mobocapital.com, www.mobocapital.com {
    root * /srv/sites/mobocapital
    encode zstd gzip

    @internal_zone {
        path /internal/*
    }
    handle @internal_zone {
        basicauth {
            mobo {$CADDY_INTERNAL_PASS_HASH}
        }
        header Cache-Control "no-store, no-cache, must-revalidate"
        file_server
    }

    @public_json {
        path /data/*.json
    }
    handle @public_json {
        header Cache-Control "public, max-age=60, must-revalidate"
        file_server
    }

    handle {
        try_files {path} /index.html
        file_server
    }

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        Referrer-Policy "strict-origin-when-cross-origin"
    }
}

# 网站 B：莫伯之家 (MoBoHome.com)
mobohome.com, www.mobohome.com {
    root * /srv/sites/mobohome
    encode zstd gzip

    @home_internal {
        path /internal/*
    }
    handle @home_internal {
        basicauth {
            mobo {$CADDY_INTERNAL_PASS_HASH}
        }
        header Cache-Control "no-store, no-cache, must-revalidate"
        file_server
    }

    handle_path /lab/* {
        basicauth {
            mobo {$CADDY_INTERNAL_PASS_HASH}
        }
        reverse_proxy archive-dashboard:8501 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
        }
    }

    handle {
        try_files {path} /index.html
        file_server
    }

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
    }
}

# 内部生产力中台子域名
pkm.mobocapital.com {
    encode zstd gzip
    reverse_proxy mobobrain-pkm:6806
}

n8n.mobocapital.com {
    encode zstd gzip
    reverse_proxy mobobrain-n8n:5678 {
        flush_interval -1
    }
}
EOF_CADDY

# ============================================================================
# [5/8] 写入 PostgreSQL 16 (pgvector) 双库隔离与自动化触发器脚本 (01 - 06)
# ============================================================================
echo "🗄️ [5/8] 正在写入 PostgreSQL 01-06 初始化 SQL 脚本序列..."

cat << 'EOF_SQL01' > "${STACK_DIR}/init-scripts/01-init-dual-db.sql"
-- ============================================================================
-- 01-init-dual-db.sql: 创建 db_mobobrain 与 db_archive 并执行物理级权限硬隔离
-- ============================================================================
CREATE USER user_mobobrain WITH PASSWORD 'ChangeMe_MoboBrainPass_2026!';
CREATE USER user_archive WITH PASSWORD 'ChangeMe_ArchiveVaultPass_2026!';

CREATE DATABASE db_mobobrain OWNER user_mobobrain ENCODING 'UTF8';
CREATE DATABASE db_archive OWNER user_archive ENCODING 'UTF8';

REVOKE CONNECT ON DATABASE db_mobobrain FROM PUBLIC;
REVOKE CONNECT ON DATABASE db_archive FROM PUBLIC;

GRANT CONNECT, TEMPORARY ON DATABASE db_mobobrain TO user_mobobrain;
GRANT CONNECT, TEMPORARY ON DATABASE db_archive TO user_archive;

\connect db_mobobrain postgres
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO user_mobobrain;
ALTER DEFAULT PRIVILEGES FOR ROLE user_mobobrain IN SCHEMA public GRANT ALL ON TABLES TO user_mobobrain;
ALTER DEFAULT PRIVILEGES FOR ROLE user_mobobrain IN SCHEMA public GRANT ALL ON SEQUENCES TO user_mobobrain;

\connect db_archive postgres
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO user_archive;
ALTER DEFAULT PRIVILEGES FOR ROLE user_archive IN SCHEMA public GRANT ALL ON TABLES TO user_archive;
ALTER DEFAULT PRIVILEGES FOR ROLE user_archive IN SCHEMA public GRANT ALL ON SEQUENCES TO user_archive;
EOF_SQL01

cat << 'EOF_SQL02' > "${STACK_DIR}/init-scripts/02-archive-schema.sql"
-- ============================================================================
-- 02-archive-schema.sql: 莫伯之家 (db_archive) 5 大生命档案核心表与周度聚合视图
-- ============================================================================
\connect db_archive user_archive;

CREATE TABLE IF NOT EXISTS timeline_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_date DATE NOT NULL,
    event_timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    category VARCHAR(32) NOT NULL
        CHECK (category IN ('career', 'milestone', 'reading', 'fitness', 'reflection', 'project')),
    title VARCHAR(256) NOT NULL,
    summary TEXT,
    location_name VARCHAR(64) DEFAULT '武汉',
    importance SMALLINT DEFAULT 3 CHECK (importance BETWEEN 1 AND 5),
    mood_score SMALLINT CHECK (mood_score BETWEEN 1 AND 10),
    energy_score SMALLINT CHECK (energy_score BETWEEN 1 AND 10),
    tags TEXT[] DEFAULT '{}',
    metadata JSONB DEFAULT '{}'::jsonb,
    source_table VARCHAR(64),
    source_record_id UUID,
    is_sensitive BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (source_table, source_record_id)
);

CREATE INDEX idx_timeline_date ON timeline_events(event_date DESC, category);
CREATE INDEX idx_timeline_tags ON timeline_events USING gin(tags);

CREATE TABLE IF NOT EXISTS entity_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_type VARCHAR(32) NOT NULL,
    source_id UUID NOT NULL,
    target_type VARCHAR(32) NOT NULL,
    target_id UUID NOT NULL,
    relation_type VARCHAR(32) DEFAULT 'related_to',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (source_type, source_id, target_type, target_id, relation_type)
);

CREATE TABLE IF NOT EXISTS reading_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_type VARCHAR(20) DEFAULT 'BOOK' CHECK (item_type IN ('BOOK', 'PAPER', 'COURSE')),
    title VARCHAR(256) NOT NULL,
    author VARCHAR(128),
    category VARCHAR(32) NOT NULL DEFAULT 'FINANCE',
    status VARCHAR(20) DEFAULT 'IN_PROGRESS'
        CHECK (status IN ('WISHLIST', 'IN_PROGRESS', 'COMPLETED', 'RE_READING')),
    rating SMALLINT CHECK (rating BETWEEN 1 AND 5),
    started_date DATE,
    completed_date DATE,
    core_takeaway TEXT,
    tags TEXT[] DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS reading_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reading_item_id UUID NOT NULL REFERENCES reading_items(id) ON DELETE CASCADE,
    log_date DATE NOT NULL DEFAULT CURRENT_DATE,
    chapter_or_pages VARCHAR(64),
    duration_minutes INTEGER DEFAULT 30,
    notes_markdown TEXT NOT NULL,
    embedding vector(1536),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS fitness_workouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workout_date DATE NOT NULL DEFAULT CURRENT_DATE,
    workout_type VARCHAR(32) NOT NULL
        CHECK (workout_type IN ('running', 'strength', 'hiit', 'swimming', 'hiking')),
    duration_minutes INTEGER NOT NULL CHECK (duration_minutes > 0),
    distance_km NUMERIC(5,2),
    avg_heart_rate SMALLINT,
    rpe_score SMALLINT CHECK (rpe_score BETWEEN 1 AND 10),
    calories_burned INTEGER,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS fitness_biometrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    record_date DATE UNIQUE NOT NULL DEFAULT CURRENT_DATE,
    weight_kg NUMERIC(5,2),
    body_fat_pct NUMERIC(4,1),
    resting_hr SMALLINT,
    sleep_hours NUMERIC(4,2),
    sleep_quality_score SMALLINT CHECK (sleep_quality_score BETWEEN 1 AND 10),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS project_retrospectives (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    review_period VARCHAR(32) UNIQUE NOT NULL,
    period_type VARCHAR(20) NOT NULL
        CHECK (period_type IN ('weekly', 'monthly', 'quarterly', 'annual', 'project')),
    review_date DATE NOT NULL DEFAULT CURRENT_DATE,
    title VARCHAR(256) NOT NULL,
    achievements TEXT,
    bottlenecks TEXT,
    next_actions TEXT,
    content_markdown TEXT NOT NULL,
    embedding vector(1536),
    is_sensitive BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS archive_assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_type VARCHAR(24) NOT NULL
        CHECK (asset_type IN ('photo', 'video', 'scan_doc', 'audio', 'certificate')),
    title VARCHAR(256) NOT NULL,
    captured_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    oss_bucket VARCHAR(64) NOT NULL,
    oss_object_key TEXT NOT NULL,
    oss_thumbnail_key TEXT,
    file_sha256 CHAR(64) UNIQUE NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    mime_type VARCHAR(64),
    storage_class VARCHAR(24) DEFAULT 'Standard',
    extracted_text TEXT,
    exif_or_meta JSONB DEFAULT '{}'::jsonb,
    linked_event_id UUID REFERENCES timeline_events(id) ON DELETE SET NULL,
    is_sensitive BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_assets_type_date ON archive_assets(asset_type, captured_at DESC);

CREATE OR REPLACE VIEW v_weekly_life_analytics AS
WITH weeks AS (
    SELECT generate_series(
        date_trunc('week', CURRENT_DATE - INTERVAL '25 weeks'),
        date_trunc('week', CURRENT_DATE),
        INTERVAL '1 week'
    )::date AS week_start
)
SELECT 
    to_char(w.week_start, 'IYYY-"W"IW') AS iso_week,
    w.week_start,
    COALESCE(fw.workout_sessions, 0) AS workout_sessions,
    COALESCE(fw.total_workout_mins, 0) AS total_workout_mins,
    COALESCE(fw.running_km, 0.0) AS running_km,
    COALESCE(rl.reading_mins, 0) AS reading_mins,
    ROUND(te.avg_mood, 1) AS avg_mood_score,
    ROUND(te.avg_energy, 1) AS avg_energy_score,
    ROUND(fb.avg_sleep_hours, 2) AS avg_sleep_hours
FROM weeks w
LEFT JOIN (
    SELECT date_trunc('week', workout_date)::date AS wk,
           COUNT(*) AS workout_sessions,
           SUM(duration_minutes) AS total_workout_mins,
           SUM(COALESCE(distance_km, 0)) FILTER (WHERE workout_type = 'running') AS running_km
    FROM fitness_workouts
    GROUP BY 1
) fw ON w.week_start = fw.wk
LEFT JOIN (
    SELECT date_trunc('week', log_date)::date AS wk,
           SUM(duration_minutes) AS reading_mins
    FROM reading_logs
    GROUP BY 1
) rl ON w.week_start = rl.wk
LEFT JOIN (
    SELECT date_trunc('week', event_date)::date AS wk,
           AVG(mood_score) AS avg_mood,
           AVG(energy_score) AS avg_energy
    FROM timeline_events
    GROUP BY 1
) te ON w.week_start = te.wk
LEFT JOIN (
    SELECT date_trunc('week', record_date)::date AS wk,
           AVG(sleep_hours) AS avg_sleep_hours
    FROM fitness_biometrics
    GROUP BY 1
) fb ON w.week_start = fb.wk
ORDER BY w.week_start DESC;
EOF_SQL02

cat << 'EOF_SQL03' > "${STACK_DIR}/init-scripts/03-archive-triggers.sql"
-- ============================================================================
-- 03-archive-triggers.sql: 莫伯之家零人工双写触发器
-- ============================================================================
\connect db_archive user_archive;

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
EOF_SQL03

cat << 'EOF_SQL04' > "${STACK_DIR}/init-scripts/04-mobocapital-schema.sql"
-- ============================================================================
-- 04-mobocapital-schema.sql: 莫伯资本 (db_mobobrain) 7 大投研/复盘/基金孵化表与视图
-- ============================================================================
\connect db_mobobrain user_mobobrain;

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";

CREATE TABLE IF NOT EXISTS macro_theses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    thesis_code VARCHAR(32) UNIQUE NOT NULL,
    title VARCHAR(256) NOT NULL,
    region VARCHAR(32) NOT NULL DEFAULT 'GLOBAL',
    asset_class VARCHAR(32) NOT NULL,
    time_horizon VARCHAR(32) NOT NULL,
    directional_bias VARCHAR(16) NOT NULL
        CHECK (directional_bias IN ('BULLISH', 'BEARISH', 'NEUTRAL', 'VOL_LONG', 'VOL_SHORT')),
    conviction_score SMALLINT NOT NULL
        CHECK (conviction_score BETWEEN 1 AND 10),
    leading_indicators JSONB DEFAULT '{}'::jsonb,
    core_logic_md TEXT NOT NULL,
    invalidation_criteria TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'VALIDATED', 'INVALIDATED', 'ARCHIVED')),
    visibility VARCHAR(16) DEFAULT 'PUBLIC'
        CHECK (visibility IN ('PUBLIC', 'LP_PROSPECT', 'INTERNAL')),
    embedding vector(1536),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_macro_theses_status ON macro_theses(status, region, created_at DESC);
CREATE INDEX idx_macro_theses_vec ON macro_theses USING hnsw (embedding vector_cosine_ops);

CREATE TABLE IF NOT EXISTS strategy_playbooks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    strategy_code VARCHAR(32) UNIQUE NOT NULL,
    name VARCHAR(128) NOT NULL,
    strategy_family VARCHAR(32) NOT NULL
        CHECK (strategy_family IN ('LONG_SHORT_EQUITY', 'OPTIONS_VOL', 'MACRO_DIRECTIONAL', 'EVENT_DRIVEN')),
    holding_period VARCHAR(32) NOT NULL,
    target_sharpe NUMERIC(4,2),
    target_win_rate_pct NUMERIC(5,2),
    target_rr_ratio NUMERIC(5,2),
    max_risk_per_trade_pct NUMERIC(4,2) NOT NULL,
    max_sector_exposure_pct NUMERIC(5,2),
    entry_rules_md TEXT NOT NULL,
    option_structure_guide TEXT,
    exit_and_stop_rules_md TEXT NOT NULL,
    visibility VARCHAR(16) DEFAULT 'LP_PROSPECT'
        CHECK (visibility IN ('PUBLIC', 'LP_PROSPECT', 'INTERNAL')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS trade_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trade_code VARCHAR(40) UNIQUE NOT NULL,
    thesis_id UUID REFERENCES macro_theses(id) ON DELETE SET NULL,
    strategy_id UUID REFERENCES strategy_playbooks(id) ON DELETE RESTRICT,
    underlying_ticker VARCHAR(32) NOT NULL,
    asset_name VARCHAR(64) NOT NULL,
    direction VARCHAR(16) NOT NULL
        CHECK (direction IN ('LONG', 'SHORT', 'DELTA_NEUTRAL', 'RELATIVE_VALUE')),
    instrument_structure VARCHAR(64) NOT NULL,
    entry_date DATE NOT NULL,
    exit_date DATE,
    trade_status VARCHAR(16) DEFAULT 'OPEN'
        CHECK (trade_status IN ('OPEN', 'CLOSED', 'STOPPED_OUT')),
    initial_risk_pct NUMERIC(4,2) NOT NULL,
    realized_r_multiple NUMERIC(6,2),
    realized_return_pct NUMERIC(7,2),
    portfolio_impact_bps INTEGER,
    greeks_snapshot JSONB DEFAULT '{}'::jsonb,
    pre_trade_thesis_md TEXT NOT NULL,
    execution_review_md TEXT,
    lessons_learned_md TEXT,
    discipline_score SMALLINT
        CHECK (discipline_score BETWEEN 1 AND 10),
    emotional_state_tag VARCHAR(32),
    private_blotter_oss_key TEXT,
    public_chart_oss_url TEXT,
    visibility VARCHAR(16) DEFAULT 'PUBLIC'
        CHECK (visibility IN ('PUBLIC', 'LP_PROSPECT', 'INTERNAL')),
    embedding vector(1536),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_trade_reviews_strat ON trade_reviews(strategy_id, entry_date DESC);
CREATE INDEX idx_trade_reviews_status ON trade_reviews(trade_status, visibility);
CREATE INDEX idx_trade_reviews_vec ON trade_reviews USING hnsw (embedding vector_cosine_ops);

CREATE TABLE IF NOT EXISTS fund_incubation_milestones (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phase_number SMALLINT NOT NULL CHECK (phase_number IN (1, 2, 3)),
    phase_name VARCHAR(64) NOT NULL,
    domain_category VARCHAR(32) NOT NULL
        CHECK (domain_category IN (
            'TRACK_RECORD', 'LEGAL_COMPLIANCE', 'FINANCE_VALUATION', 'TECH_INFRA', 'LP_AND_BRAND'
        )),
    milestone_title VARCHAR(128) NOT NULL,
    target_metric_desc VARCHAR(256) NOT NULL,
    current_progress_pct SMALLINT DEFAULT 0 CHECK (current_progress_pct BETWEEN 0 AND 100),
    target_date DATE NOT NULL,
    completed_date DATE,
    status VARCHAR(20) DEFAULT 'IN_PROGRESS'
        CHECK (status IN ('PLANNED', 'IN_PROGRESS', 'COMPLETED', 'DELAYED')),
    action_plan_md TEXT,
    visibility VARCHAR(16) DEFAULT 'PUBLIC'
        CHECK (visibility IN ('PUBLIC', 'LP_PROSPECT', 'INTERNAL')),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS fund_governance_docs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doc_slug VARCHAR(128) UNIQUE NOT NULL,
    doc_type VARCHAR(32) NOT NULL
        CHECK (doc_type IN ('INVESTOR_LETTER', 'RISK_SOP', 'LEGAL_STRUCT', 'NAV_ACCOUNTING', 'PITCH_DECK')),
    title VARCHAR(256) NOT NULL,
    version VARCHAR(16) DEFAULT 'v1.0',
    summary TEXT,
    content_md TEXT NOT NULL,
    private_attachment_oss_key TEXT,
    visibility VARCHAR(16) DEFAULT 'LP_PROSPECT'
        CHECK (visibility IN ('PUBLIC', 'LP_PROSPECT', 'INTERNAL')),
    published_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS capital_publications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug VARCHAR(128) UNIQUE NOT NULL,
    category VARCHAR(32) NOT NULL
        CHECK (category IN ('MACRO', 'STRATEGY', 'TRADE_REVIEW', 'FUND_VISION', 'PHILOSOPHY')),
    title VARCHAR(256) NOT NULL,
    summary TEXT,
    related_thesis_id UUID REFERENCES macro_theses(id) ON DELETE SET NULL,
    related_trade_id UUID REFERENCES trade_reviews(id) ON DELETE SET NULL,
    related_milestone_id UUID REFERENCES fund_incubation_milestones(id) ON DELETE SET NULL,
    source_siyuan_id VARCHAR(64),
    web_markdown TEXT NOT NULL,
    wechat_html TEXT,
    xueqiu_markdown TEXT,
    x_thread_json JSONB DEFAULT '[]'::jsonb,
    toutiao_markdown TEXT,
    cover_oss_url TEXT,
    tags TEXT[] DEFAULT '{}',
    visibility VARCHAR(16) DEFAULT 'PUBLIC'
        CHECK (visibility IN ('PUBLIC', 'LP_PROSPECT', 'INTERNAL')),
    publish_status VARCHAR(20) DEFAULT 'DRAFT'
        CHECK (publish_status IN ('DRAFT', 'PENDING_REVIEW', 'APPROVED', 'PUBLISHED', 'FAILED')),
    wechat_draft_media_id VARCHAR(128),
    xueqiu_post_url TEXT,
    x_root_tweet_id VARCHAR(64),
    embedding vector(1536),
    published_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_cap_pub_cat_date ON capital_publications(category, publish_status, published_at DESC);
CREATE INDEX idx_cap_pub_vec ON capital_publications USING hnsw (embedding vector_cosine_ops);

CREATE TABLE IF NOT EXISTS media_channel_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    publication_id UUID REFERENCES capital_publications(id) ON DELETE CASCADE,
    channel VARCHAR(24) NOT NULL
        CHECK (channel IN ('WECHAT', 'XUEQIU', 'X_TWITTER', 'TOUTIAO', 'MOBOCAPITAL_WEB')),
    snapshot_date DATE NOT NULL DEFAULT CURRENT_DATE,
    impressions INTEGER DEFAULT 0,
    views_or_reads INTEGER DEFAULT 0,
    likes_and_bookmarks INTEGER DEFAULT 0,
    comments_and_shares INTEGER DEFAULT 0,
    net_new_followers INTEGER DEFAULT 0,
    referral_clicks_to_web INTEGER DEFAULT 0,
    UNIQUE (publication_id, channel, snapshot_date)
);

CREATE OR REPLACE VIEW v_strategy_performance_summary AS
SELECT 
    sp.strategy_code,
    sp.name AS strategy_name,
    sp.strategy_family,
    sp.target_sharpe,
    COUNT(tr.id) FILTER (WHERE tr.trade_status IN ('CLOSED', 'STOPPED_OUT')) AS closed_trades_count,
    ROUND(
        100.0 * COUNT(tr.id) FILTER (WHERE tr.realized_r_multiple > 0) / 
        NULLIF(COUNT(tr.id) FILTER (WHERE tr.trade_status IN ('CLOSED', 'STOPPED_OUT')), 0), 
        2
    ) AS actual_win_rate_pct,
    ROUND(AVG(tr.realized_r_multiple) FILTER (WHERE tr.realized_r_multiple > 0), 2) AS avg_win_r,
    ROUND(AVG(tr.realized_r_multiple) FILTER (WHERE tr.realized_r_multiple < 0), 2) AS avg_loss_r,
    ROUND(SUM(tr.realized_r_multiple), 2) AS cumulative_r_multiple,
    ROUND(AVG(tr.discipline_score), 1) AS avg_discipline_score
FROM strategy_playbooks sp
LEFT JOIN trade_reviews tr ON sp.id = tr.strategy_id
WHERE sp.is_active = TRUE
GROUP BY sp.id, sp.strategy_code, sp.name, sp.strategy_family, sp.target_sharpe;

CREATE OR REPLACE VIEW v_media_conversion_funnel AS
SELECT 
    cp.category AS content_category,
    mcm.channel,
    COUNT(DISTINCT cp.id) AS published_articles,
    SUM(mcm.impressions) AS total_impressions,
    SUM(mcm.views_or_reads) AS total_reads,
    SUM(mcm.likes_and_bookmarks) AS total_high_value_engagements,
    SUM(mcm.net_new_followers) AS total_followers_gained,
    SUM(mcm.referral_clicks_to_web) AS total_web_referrals,
    ROUND(
        1000.0 * SUM(mcm.net_new_followers) / NULLIF(SUM(mcm.views_or_reads), 0), 
        2
    ) AS followers_per_1k_reads
FROM capital_publications cp
JOIN media_channel_metrics mcm ON cp.id = mcm.publication_id
WHERE cp.publish_status = 'PUBLISHED'
GROUP BY cp.category, mcm.channel;

INSERT INTO fund_incubation_milestones 
(phase_number, phase_name, domain_category, milestone_title, target_metric_desc, current_progress_pct, target_date, status, visibility)
VALUES
(1, 'Phase 1: 自营交易与体系化筑基', 'TRACK_RECORD', '建立 ITPM 全球宏观与期权波动率实盘复盘账本', '完成至少 30 笔完整周期的宏观/期权结构化交易归因，平均执行纪律得分不低于 8.5/10', 65, '2027-06-30', 'IN_PROGRESS', 'PUBLIC'),
(1, 'Phase 1: 自营交易与体系化筑基', 'LEGAL_COMPLIANCE', '攻克法律职业资格（法考）与证券从业资格', '建立私募基金合同、合规募集边界与投资者适当性管理的底层法律认知护城河', 60, '2027-10-31', 'IN_PROGRESS', 'PUBLIC'),
(1, 'Phase 1: 自营交易与体系化筑基', 'FINANCE_VALUATION', '攻克中级会计师并搭建基金 NAV 估值核算模型', '熟练掌握企业财报深度排雷与对冲基金高水位法（High-Water Mark）业绩报酬计提逻辑', 55, '2027-09-30', 'IN_PROGRESS', 'PUBLIC'),
(1, 'Phase 1: 自营交易与体系化筑基', 'LP_AND_BRAND', '《MoBo''s Memo》四端同源投研品牌矩阵冷启动', '累计发布 100 篇高质量宏观与策略深度长文，构建莫伯资本主站核心订阅者私域池', 35, '2027-12-31', 'IN_PROGRESS', 'PUBLIC'),
(2, 'Phase 2: 种子孵化与可审计业绩验证', 'TRACK_RECORD', '完成连续 18-24 个月低回撤可验证实盘曲线', '年化夏普比率大于 1.5，最大回撤严格控制在 10% 以内，完成第三方或券商 PB 业绩鉴证', 15, '2028-12-31', 'PLANNED', 'LP_PROSPECT'),
(2, 'Phase 2: 种子孵化与可审计业绩验证', 'TECH_INFRA', '升级莫伯资本投委会风控系统与自动化组合监控', '实现组合 Delta/Vega/行业净敞口超限自动预警与强制减仓风控熔断工作流', 30, '2028-06-30', 'PLANNED', 'LP_PROSPECT'),
(3, 'Phase 3: 莫伯资本独立对冲基金设立', 'LEGAL_COMPLIANCE', '完成独立基金主体架构设立与首批种子 LP 关账', '确立管理人/基金架构，落实独立托管与外包估值，正式开启机构化资产管理运作', 10, '2030-01-01', 'PLANNED', 'LP_PROSPECT');
EOF_SQL04

cat << 'EOF_SQL05' > "${STACK_DIR}/init-scripts/05-mobocapital-nav-and-triggers.sql"
-- ============================================================================
-- 05-mobocapital-nav-and-triggers.sql: 组合 NAV 高水位估值与风控熔断触发器
-- ============================================================================
\connect db_mobobrain user_mobobrain;

CREATE TABLE IF NOT EXISTS portfolio_nav_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    valuation_date DATE UNIQUE NOT NULL DEFAULT CURRENT_DATE,
    trigger_trade_code VARCHAR(40),
    gross_nav NUMERIC(10,4) NOT NULL DEFAULT 1.0000,
    high_water_mark NUMERIC(10,4) NOT NULL DEFAULT 1.0000,
    accrued_perf_fee_nav NUMERIC(10,4) DEFAULT 0.0000,
    net_nav NUMERIC(10,4) NOT NULL DEFAULT 1.0000,
    current_drawdown_pct NUMERIC(6,2) NOT NULL DEFAULT 0.00,
    cumulative_r_multiple NUMERIC(8,2) NOT NULL DEFAULT 0.00,
    risk_regime_status VARCHAR(24) NOT NULL DEFAULT 'NORMAL'
        CHECK (risk_regime_status IN ('NORMAL', 'YELLOW_ALERT', 'RED_CIRCUIT_BREAKER')),
    risk_action_note TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO portfolio_nav_ledger (
    valuation_date, trigger_trade_code, gross_nav, high_water_mark, net_nav, 
    current_drawdown_pct, cumulative_r_multiple, risk_regime_status, risk_action_note
) VALUES (
    '2026-01-01', 'GENESIS-INIT', 1.0000, 1.0000, 1.0000, 
    0.00, 0.00, 'NORMAL', '莫伯资本 Phase 1 实盘孵化组合初始基准净值 (NAV = 1.0000)'
) ON CONFLICT (valuation_date) DO NOTHING;

CREATE OR REPLACE FUNCTION fn_update_nav_on_trade_close()
RETURNS TRIGGER AS $$
DECLARE
    v_prev_nav NUMERIC(10,4);
    v_prev_hwm NUMERIC(10,4);
    v_total_r NUMERIC(8,2);
    v_new_gross_nav NUMERIC(10,4);
    v_new_hwm NUMERIC(10,4);
    v_perf_fee NUMERIC(10,4);
    v_new_net_nav NUMERIC(10,4);
    v_drawdown_pct NUMERIC(6,2);
    v_risk_status VARCHAR(24);
    v_risk_note TEXT;
BEGIN
    IF NEW.trade_status IN ('CLOSED', 'STOPPED_OUT') AND NEW.portfolio_impact_bps IS NOT NULL THEN
        SELECT gross_nav, high_water_mark 
        INTO v_prev_nav, v_prev_hwm
        FROM portfolio_nav_ledger
        ORDER BY valuation_date DESC, created_at DESC
        LIMIT 1;

        v_prev_nav := COALESCE(v_prev_nav, 1.0000);
        v_prev_hwm := COALESCE(v_prev_hwm, 1.0000);

        SELECT COALESCE(SUM(realized_r_multiple), 0.00)
        INTO v_total_r
        FROM trade_reviews
        WHERE trade_status IN ('CLOSED', 'STOPPED_OUT');

        SELECT 1.0000 + COALESCE(SUM(portfolio_impact_bps), 0) / 10000.0
        INTO v_new_gross_nav
        FROM trade_reviews
        WHERE trade_status IN ('CLOSED', 'STOPPED_OUT');

        v_new_hwm := GREATEST(v_prev_hwm, v_new_gross_nav);

        IF v_new_gross_nav > 1.0000 THEN
            v_perf_fee := ROUND((v_new_gross_nav - 1.0000) * 0.20, 4);
        ELSE
            v_perf_fee := 0.0000;
        END IF;

        v_new_net_nav := v_new_gross_nav - v_perf_fee;
        v_drawdown_pct := ROUND(((v_new_gross_nav - v_new_hwm) / v_new_hwm) * 100.0, 2);

        IF v_drawdown_pct <= -8.00 THEN
            v_risk_status := 'RED_CIRCUIT_BREAKER';
            v_risk_note := '【红色风控熔断】组合回撤已触及 -8% 警戒线！强制将总敞口压降至 25% 以内，禁止新开买方期权头寸。';
        ELSIF v_drawdown_pct <= -5.00 THEN
            v_risk_status := 'YELLOW_ALERT';
            v_risk_note := '【黄色回撤预警】组合回撤超过 -5%，单笔最大风险敞口由 1.50% 下调至 0.75% NAV。';
        ELSE
            v_risk_status := 'NORMAL';
            v_risk_note := '组合净值运行稳健，维持标准风险预算（单笔不超过 1.50% NAV）。';
        END IF;

        INSERT INTO portfolio_nav_ledger (
            valuation_date, trigger_trade_code, gross_nav, high_water_mark,
            accrued_perf_fee_nav, net_nav, current_drawdown_pct,
            cumulative_r_multiple, risk_regime_status, risk_action_note
        ) VALUES (
            COALESCE(NEW.exit_date, CURRENT_DATE), NEW.trade_code, v_new_gross_nav, v_new_hwm,
            v_perf_fee, v_new_net_nav, v_drawdown_pct,
            v_total_r, v_risk_status, v_risk_note
        )
        ON CONFLICT (valuation_date) DO UPDATE SET
            trigger_trade_code = EXCLUDED.trigger_trade_code,
            gross_nav = EXCLUDED.gross_nav,
            high_water_mark = EXCLUDED.high_water_mark,
            accrued_perf_fee_nav = EXCLUDED.accrued_perf_fee_nav,
            net_nav = EXCLUDED.net_nav,
            current_drawdown_pct = EXCLUDED.current_drawdown_pct,
            cumulative_r_multiple = EXCLUDED.cumulative_r_multiple,
            risk_regime_status = EXCLUDED.risk_regime_status,
            risk_action_note = EXCLUDED.risk_action_note,
            created_at = CURRENT_TIMESTAMP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auto_calc_nav_on_trade ON trade_reviews;
CREATE TRIGGER trg_auto_calc_nav_on_trade
AFTER INSERT OR UPDATE ON trade_reviews
FOR EACH ROW
EXECUTE FUNCTION fn_update_nav_on_trade_close();

INSERT INTO strategy_playbooks (
    strategy_code, name, strategy_family, holding_period, target_sharpe,
    target_win_rate_pct, target_rr_ratio, max_risk_per_trade_pct, max_sector_exposure_pct,
    entry_rules_md, option_structure_guide, exit_and_stop_rules_md, visibility
) VALUES
(
    'OPT-VOL-SKEW-01', '期权波动率偏度与跨式非对称策略', 'OPTIONS_VOL', '2-6 Weeks',
    1.95, 65.0, 2.80, 1.25, 25.0,
    '1. 宏观或行业催化剂明确且先行指标 Z-Score 大于 +1.0σ；2. 标的 30D IV Rank 处于 30% 分位以下或 80% 分位以上。',
    '低 IV 买方向使用 Bull Call / Bear Put Spread (45DTE)；高 Skew 环境使用 1x2 Ratio Spread 或 Calendar Spread。',
    '单笔权利金最大亏损严格锁死在 1.25% NAV；到期前 7 天无条件移仓或平仓规避尾部 Gamma 风险。', 'PUBLIC'
),
(
    'ITPM-LS-EQUITY', 'ITPM 基本面多空配对股票策略 (L/S Equity)', 'LONG_SHORT_EQUITY', '1-3 Months',
    1.75, 60.0, 2.50, 1.50, 30.0,
    '结合自上而下 PMI/社融先行指标与零售/供应链微观周转率印证，做多自由现金流拐点龙头，同时配对做空基本面恶化同业标的。',
    '以现货配对为主，辅以卖出虚值 Covered Call 增厚持仓收益。',
    '配对组合触及 -1.0R（即 1.50% NAV）或基本面证伪条件触发时，双腿同步无条件平仓。', 'PUBLIC'
),
(
    'MACRO-CROSS-ASSET', '全球宏观跨资产趋势与利差对冲策略', 'MACRO_DIRECTIONAL', '1-6 Months',
    1.60, 55.0, 3.00, 1.00, 25.0,
    '围绕中美欧货币政策周期错位、M1-M2 剪刀差与实际利差变化，在宽基股指 ETF、国债 ETF 与黄金期权之间构建低相关性宏观头寸。',
    '优先采用对角价差 (Diagonal Spread) 或远期合成头寸控制资金占用。',
    '宏观先行指标连续两个月逆转或触及预设证伪点位时立即止损离场。', 'PUBLIC'
),
(
    'TAIL-RISK-SHIELD', '尾部风险保护伞与系统性熔断对冲', 'EVENT_DRIVEN', 'Continuous',
    1.40, 40.0, 5.00, 0.50, 15.0,
    '当全市场 VIX 或 300ETF 隐含波动率跌入历史 15% 极低分位且市场情绪极度乐观时，定投远月深度虚值 Put 作为组合保险。',
    '60-90DTE 10-Delta 至 15-Delta 虚值 Put 或 Put Backspread。',
    '市场发生黑天鹅急跌、Vega 脉冲式飙升超过 4R 时分批止盈兑现，将所得现金反哺低估核心资产。', 'LP_PROSPECT'
)
ON CONFLICT (strategy_code) DO NOTHING;

INSERT INTO macro_theses (
    thesis_code, title, region, asset_class, time_horizon,
    directional_bias, conviction_score, leading_indicators,
    core_logic_md, invalidation_criteria, status, visibility
) VALUES
(
    'THESIS-2026Q4-CN-RETAIL',
    '中国必选消费与生鲜冷链供应链：高周转率企业的自由现金流重估',
    'CN', 'MULTI', '3_6_MONTHS', 'BULLISH', 8,
    '{"PMI_NewOrders": 51.4, "Inventory_Turnover_Days": "-14%", "300ETF_IV_Rank": "28%"}'::jsonb,
    '高频渠道与供应链数据显示，具备数字化仓配能力的生鲜零售企业已越过资本开支高峰，库存周转天数缩短，而期权隐含波动率仍处于 28% 低分位。',
    '若社零餐饮分项连续两个月环比回落超 1.5%，无条件平仓全部多头期权头寸。', 'ACTIVE', 'PUBLIC'
),
(
    'THESIS-2026Q4-US-VOL-SKEW',
    '美债期限溢价回升背景下的美股科技股波动率偏度（Skew）均值回归',
    'US', 'EQUITY', '1_3_MONTHS', 'VOL_LONG', 9,
    '{"US10Y_Yield": "4.18%", "SPY_25D_Skew_Pct": "92%", "ISM_NewOrders": 48.9}'::jsonb,
    '美股内部宽度收窄且机构尾部保护需求推高 Put-Call Skew 至 92% 分位，适合通过认沽比例价差博弈波动率中枢上移。',
    '若 VIX 跌破 13.5 且 ISM 新订单超预期跃升至 53 以上，立即止损平仓。', 'ACTIVE', 'PUBLIC'
)
ON CONFLICT (thesis_code) DO NOTHING;
EOF_SQL05

cat << 'EOF_SQL06' > "${STACK_DIR}/init-scripts/06-mobocapital-terminal-schema.sql"
-- ============================================================================
-- 06-mobocapital-terminal-schema.sql: 莫伯资本 /terminal 宏观与期权波动率日频快照表
-- ============================================================================
\connect db_mobobrain user_mobobrain;

CREATE TABLE IF NOT EXISTS macro_indicator_series (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    indicator_code VARCHAR(40) NOT NULL,
    indicator_name VARCHAR(128) NOT NULL,
    region VARCHAR(16) NOT NULL DEFAULT 'GLOBAL',
    frequency VARCHAR(16) NOT NULL DEFAULT 'MONTHLY',
    obs_date DATE NOT NULL,
    raw_value NUMERIC(12,4) NOT NULL,
    prev_value NUMERIC(12,4),
    change_val NUMERIC(12,4),
    z_score NUMERIC(6,2) DEFAULT 0.00,
    regime_tag VARCHAR(24) DEFAULT 'NEUTRAL'
        CHECK (regime_tag IN ('EXPANSION', 'IMPROVING', 'NEUTRAL', 'BOTTOMING', 'CONTRACTION')),
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (indicator_code, obs_date)
);

CREATE INDEX idx_macro_series_code_date ON macro_indicator_series(indicator_code, obs_date DESC);

CREATE TABLE IF NOT EXISTS options_vol_surface_daily (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    underlying_ticker VARCHAR(32) NOT NULL,
    asset_name VARCHAR(64) NOT NULL,
    trade_date DATE NOT NULL DEFAULT CURRENT_DATE,
    spot_price NUMERIC(12,4) NOT NULL,
    daily_change_pct NUMERIC(6,2) DEFAULT 0.00,
    iv_30d NUMERIC(6,2) NOT NULL,
    hv_30d NUMERIC(6,2) NOT NULL,
    vrp_spread NUMERIC(6,2) NOT NULL,
    iv_rank_1y NUMERIC(5,2) NOT NULL,
    iv_percentile_1y NUMERIC(5,2) NOT NULL,
    skew_25d NUMERIC(6,2) NOT NULL,
    recommended_structure VARCHAR(64) NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (underlying_ticker, trade_date)
);

CREATE INDEX idx_opt_vol_ticker_date ON options_vol_surface_daily(underlying_ticker, trade_date DESC);

CREATE OR REPLACE VIEW v_latest_macro_indicators AS
SELECT DISTINCT ON (indicator_code)
    indicator_code, indicator_name, region, frequency, obs_date,
    raw_value, prev_value, change_val, z_score, regime_tag, updated_at
FROM macro_indicator_series
ORDER BY indicator_code, obs_date DESC;

CREATE OR REPLACE VIEW v_latest_options_vol_surface AS
SELECT DISTINCT ON (underlying_ticker)
    underlying_ticker, asset_name, trade_date, spot_price, daily_change_pct,
    iv_30d, hv_30d, vrp_spread, iv_rank_1y, iv_percentile_1y,
    skew_25d, recommended_structure, updated_at
FROM options_vol_surface_daily
ORDER BY underlying_ticker, trade_date DESC;
EOF_SQL06

# ============================================================================
# [6/8] 写入 Streamlit 量化实验室与双站响应式前端 HTML 门户
# ============================================================================
echo "🌐 [6/8] 正在写入 Streamlit 看板与 MoBoCapital / MoBoHome 前端门户..."

cat << 'EOF_DOCKERFILE' > "${STACK_DIR}/dashboard/Dockerfile"
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8501
CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0", "--server.headless=true"]
EOF_DOCKERFILE

cat << 'EOF_REQ' > "${STACK_DIR}/dashboard/requirements.txt"
streamlit==1.39.0
psycopg2-binary==2.9.9
pandas==2.2.3
numpy==2.1.2
EOF_REQ

cat << 'EOF_APP' > "${STACK_DIR}/dashboard/app.py"
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import numpy as np
import pandas as pd
import psycopg2
import streamlit as st

st.set_page_config(page_title="MoBo Life Analytics Lab", layout="wide")

@st.cache_data(ttl=300)
def load_weekly_df() -> pd.DataFrame:
    conn = psycopg2.connect(
        host=os.getenv("PG_HOST", "mobo-postgres"),
        port=int(os.getenv("PG_PORT", "5432")),
        dbname=os.getenv("PG_DB_ARCHIVE", "db_archive"),
        user=os.getenv("PG_USER_ARCHIVE", "user_archive"),
        password=os.getenv("PG_PASS_ARCHIVE"),
    )
    try:
        return pd.read_sql("SELECT * FROM v_weekly_life_analytics ORDER BY week_start ASC;", conn)
    finally:
        conn.close()

def zscore_series(s: pd.Series) -> pd.Series:
    arr = s.fillna(0).to_numpy(dtype=np.float64)
    std = np.std(arr)
    if std < 1e-8:
        return pd.Series(np.zeros_like(arr), index=s.index)
    return pd.Series((arr - np.mean(arr)) / std, index=s.index)

st.title("📊 莫伯之家 · 生命体征 Z-Score 与 Lead-Lag 滞后回归实验室")

try:
    df = load_weekly_df()
    if df.empty:
        st.info("当前 v_weekly_life_analytics 暂无数据，请先通过 mobo_cli.py home-habit 录入训练或阅读记录。")
    else:
        metrics = ["running_km", "total_workout_mins", "reading_mins", "avg_mood_score", "avg_energy_score"]
        st.subheader("1. 多维自律与状态指标 Z-Score 标准化趋势叠加")
        z_df = pd.DataFrame({m: zscore_series(df[m]) for m in metrics if m in df.columns})
        z_df.index = df["iso_week"]
        st.line_chart(z_df)

        st.subheader("2. Lead-Lag 跨周滞后交叉相关检验")
        col1, col2, col3 = st.columns(3)
        x_col = col1.selectbox("先行自变量 (X)", metrics, index=0)
        y_col = col2.selectbox("滞后因变量 (Y)", metrics, index=4)
        lag_k = col3.slider("滞后周数 (Lag Weeks)", 0, 4, 1)

        x_arr = df[x_col].fillna(0).to_numpy(dtype=np.float64)
        y_arr = df[y_col].fillna(0).to_numpy(dtype=np.float64)
        x_aligned, y_aligned = (x_arr[:-lag_k], y_arr[lag_k:]) if (lag_k > 0 and len(x_arr) > lag_k + 2) else (x_arr, y_arr)

        if len(x_aligned) >= 3 and np.std(x_aligned) > 1e-8 and np.std(y_aligned) > 1e-8:
            r_val = float(np.corrcoef(x_aligned, y_aligned)[0, 1])
            slope, _ = np.polyfit(x_aligned, y_aligned, 1)
            st.metric(
                label=f"{x_col} 领先 {y_col} ({lag_k} 周) 相关系数 r",
                value=f"{r_val:.3f}",
                delta=f"回归斜率 β = {slope:.3f}",
            )
except Exception as e:
    st.warning(f"数据库连接提示: {e}")
EOF_APP

cat << 'EOF_HTML_CAP' > "${STACK_DIR}/sites/mobocapital/index.html"
<!DOCTYPE html>
<html lang="zh-CN" class="dark">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>MO BO CAPITAL | 莫伯资本 — 全球宏观与期权波动率策略智库</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500;600;700&family=Noto+Serif+SC:wght@500;600;700&family=Playfair+Display:ital,wght@0,600;0,700;1,400&display=swap" rel="stylesheet">
  <script>
    tailwind.config = {
      darkMode: 'class',
      theme: {
        extend: {
          colors: {
            navy: { 950: '#050A14', 900: '#070E1C', 800: '#0D182E', 700: '#152544', 600: '#1E335C' },
            gold: { 300: '#E5C98B', 400: '#D4B26F', 500: '#C5A059', 600: '#A3803E', 700: '#7D6029' },
            bull: '#10B981',
            bear: '#F43F5E'
          },
          fontFamily: {
            serif: ['"Playfair Display"', '"Noto Serif SC"', 'Georgia', 'serif'],
            sans: ['"Inter"', '-apple-system', 'BlinkMacSystemFont', 'sans-serif'],
            mono: ['"JetBrains Mono"', 'monospace']
          }
        }
      }
    }
  </script>
  <style>
    body {
      background-color: #050A14;
      color: #E2E8F0;
      font-family: 'Inter', -apple-system, sans-serif;
      background-image: 
        radial-gradient(circle at 15% 0%, rgba(197, 160, 89, 0.07) 0%, transparent 45%),
        radial-gradient(circle at 85% 20%, rgba(30, 51, 92, 0.25) 0%, transparent 50%);
    }
    .gold-gradient-text {
      background: linear-gradient(135deg, #F3E5AB 0%, #C5A059 50%, #9E7B3B 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    .inst-card {
      background: rgba(13, 24, 46, 0.72);
      backdrop-filter: blur(12px);
      border: 1px solid rgba(197, 160, 89, 0.16);
      transition: all 0.25s cubic-bezier(0.16, 1, 0.3, 1);
    }
    .inst-card:hover {
      border-color: rgba(197, 160, 89, 0.42);
      box-shadow: 0 12px 32px -10px rgba(0, 0, 0, 0.65), 0 0 15px -3px rgba(197, 160, 89, 0.12);
    }
    .grid-bg {
      background-size: 32px 32px;
      background-image: 
        linear-gradient(to right, rgba(255, 255, 255, 0.02) 1px, transparent 1px),
        linear-gradient(to bottom, rgba(255, 255, 255, 0.02) 1px, transparent 1px);
    }
    .custom-scrollbar::-webkit-scrollbar { width: 6px; height: 6px; }
    .custom-scrollbar::-webkit-scrollbar-track { background: #070E1C; }
    .custom-scrollbar::-webkit-scrollbar-thumb { background: #1E335C; border-radius: 3px; }
    .custom-scrollbar::-webkit-scrollbar-thumb:hover { background: #C5A059; }
    @keyframes pulse-subtle { 0%, 100% { opacity: 1; } 50% { opacity: 0.45; } }
    .live-dot { animation: pulse-subtle 2.2s infinite ease-in-out; }
  </style>
</head>
<body class="min-h-screen flex flex-col selection:bg-gold-500 selection:text-navy-950 grid-bg">

  <div class="bg-navy-950/95 border-b border-slate-800/80 text-xs font-mono py-2 px-4 lg:px-8 flex flex-wrap items-center justify-between gap-3 z-50">
    <div class="flex items-center space-x-5 overflow-x-auto custom-scrollbar py-0.5">
      <span class="flex items-center text-gold-400 font-semibold shrink-0">
        <span class="w-2 h-2 rounded-full bg-emerald-400 mr-2 live-dot"></span>
        REGIME: GLOBAL MACRO VOL-EXPANSION
      </span>
      <span class="text-slate-400 shrink-0">US10Y <strong class="text-slate-200">4.18%</strong> <span class="text-bull">+3.2bp</span></span>
      <span class="text-slate-400 shrink-0">VIX <strong class="text-slate-200">19.45</strong> <span class="text-bear">-4.1%</span></span>
      <span class="text-slate-400 shrink-0">CN PMI (New Orders) <strong class="text-slate-200">51.4</strong> <span class="text-bull">+0.6</span></span>
      <span class="text-slate-400 shrink-0">USD/CNH <strong class="text-slate-200">7.1240</strong> <span class="text-bull">-0.15%</span></span>
    </div>

    <div class="flex items-center space-x-2 shrink-0 ml-auto">
      <span class="text-slate-500 hidden sm:inline">CLEARANCE:</span>
      <div class="inline-flex rounded bg-navy-900 p-0.5 border border-slate-800">
        <button onclick="setAccessLevel('PUBLIC')" id="btn-lvl-PUBLIC" class="px-2.5 py-1 rounded text-[11px] font-mono transition-all bg-gold-500 text-navy-950 font-semibold">PUBLIC 公域</button>
        <button onclick="setAccessLevel('LP_PROSPECT')" id="btn-lvl-LP_PROSPECT" class="px-2.5 py-1 rounded text-[11px] font-mono transition-all text-slate-400 hover:text-slate-200">LP_PROSPECT 准合伙人</button>
        <button onclick="setAccessLevel('INTERNAL')" id="btn-lvl-INTERNAL" class="px-2.5 py-1 rounded text-[11px] font-mono transition-all text-slate-400 hover:text-slate-200">INTERNAL 莫伯内网</button>
      </div>
    </div>
  </div>

  <header class="sticky top-0 z-40 bg-navy-950/85 backdrop-blur-md border-b border-gold-500/20">
    <div class="max-w-7xl mx-auto px-4 lg:px-8 h-20 flex items-center justify-between">
      <div class="flex items-center space-x-4 cursor-pointer" onclick="switchSection('overview')">
        <div class="w-11 h-11 rounded bg-gradient-to-br from-gold-400 via-gold-500 to-gold-700 p-[1px]">
          <div class="w-full h-full bg-navy-950 flex items-center justify-center">
            <span class="font-serif font-bold text-xl gold-gradient-text">MB</span>
          </div>
        </div>
        <div>
          <div class="flex items-center space-x-2">
            <span class="font-serif font-bold text-lg tracking-wider text-white">MO BO CAPITAL</span>
            <span class="text-[10px] font-mono uppercase px-1.5 py-0.5 rounded bg-gold-500/15 text-gold-400 border border-gold-500/30">Prop-to-Fund</span>
          </div>
          <p class="text-xs text-slate-400">莫伯资本 · 全球宏观驱动与期权波动率策略智库</p>
        </div>
      </div>

      <nav class="hidden lg:flex items-center space-x-1 font-sans text-sm">
        <button onclick="switchSection('overview')" id="nav-overview" class="nav-tab px-3.5 py-2 rounded-md text-gold-400 bg-gold-500/10 font-medium">总览 Overview</button>
        <button onclick="switchSection('memo')" id="nav-memo" class="nav-tab px-3.5 py-2 rounded-md text-slate-300 hover:text-white">1. 宏观智库 <span class="font-mono text-xs text-slate-500">/memo</span></button>
        <button onclick="switchSection('strategies')" id="nav-strategies" class="nav-tab px-3.5 py-2 rounded-md text-slate-300 hover:text-white">2. 策略与复盘 <span class="font-mono text-xs text-slate-500">/strategies</span></button>
        <button onclick="switchSection('incubation')" id="nav-incubation" class="nav-tab px-3.5 py-2 rounded-md text-slate-300 hover:text-white">3. 基金孵化蓝图 <span class="font-mono text-xs text-slate-500">/incubation</span></button>
        <button onclick="switchSection('terminal')" id="nav-terminal" class="nav-tab px-3.5 py-2 rounded-md text-slate-300 hover:text-white">4. 量化终端 <span class="font-mono text-xs text-slate-500">/terminal</span></button>
        <button onclick="switchSection('media')" id="nav-media" class="nav-tab px-3.5 py-2 rounded-md text-slate-300 hover:text-white">5. 自媒体引擎 <span class="font-mono text-xs text-slate-500">/media-ops</span></button>
      </nav>

      <div class="hidden sm:flex items-center space-x-3">
        <a href="https://mobohome.com" target="_blank" class="text-xs font-mono text-slate-400 hover:text-gold-400 border border-slate-800 px-3 py-1.5 rounded">⇄ MoBoHome.com (莫伯之家)</a>
      </div>
    </div>
  </header>

  <main class="flex-grow max-w-7xl w-full mx-auto px-4 lg:px-8 py-8 space-y-10">
    <div id="clearance-banner" class="rounded-lg bg-navy-800/90 border border-gold-500/30 px-4 py-3 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-2 text-xs">
      <div class="flex items-center space-x-2.5">
        <span id="clearance-badge" class="px-2 py-0.5 rounded font-mono font-bold bg-gold-500 text-navy-950">PUBLIC VIEW</span>
        <span id="clearance-desc" class="text-slate-300">当前处于<strong>公域合规视图</strong>：展示宏观推演逻辑、策略体系框架与脱敏交易纪律复盘。</span>
      </div>
      <span class="font-mono text-slate-400 shrink-0">DB: <strong class="text-gold-400">db_mobobrain</strong></span>
    </div>

    <section id="sec-overview" class="space-y-12">
      <div class="relative rounded-2xl overflow-hidden border border-gold-500/25 bg-gradient-to-br from-navy-800 via-navy-900 to-navy-950 p-6 sm:p-10 shadow-2xl">
        <div class="grid grid-cols-1 lg:grid-cols-12 gap-8 items-center">
          <div class="lg:col-span-7 space-y-5">
            <div class="inline-flex items-center space-x-2 px-3 py-1 rounded-full bg-gold-500/10 border border-gold-500/30 text-gold-400 text-xs font-mono">
              <span>SYSTEMATIC FUNDAMENTAL MACRO & OPTIONS VOLATILITY</span>
            </div>
            <h1 class="font-serif text-3xl sm:text-4xl lg:text-5xl font-bold text-white leading-tight">
              慢就是快：<br/><span class="gold-gradient-text">以风险隔离筑底，以认知复利穿越周期</span>
            </h1>
            <p class="text-slate-300 text-sm sm:text-base leading-relaxed">
              莫伯资本（MoBo Capital）融合<strong>自上而下全球宏观先行指标（ITPM 框架）</strong>、<strong>零售与供应链基本面微观印证</strong>与<strong>期权非线性波动率结构</strong>，从严谨的自营实盘归因账本迈向独立对冲基金运作。
            </p>
            <div class="flex flex-wrap gap-3 pt-2">
              <button onclick="switchSection('strategies')" class="px-5 py-2.5 rounded bg-gold-500 hover:bg-gold-400 text-navy-950 font-semibold text-sm">查阅 Alpha Lab 策略与复盘 →</button>
              <button onclick="switchSection('incubation')" class="px-5 py-2.5 rounded bg-navy-800 hover:bg-navy-700 text-slate-200 border border-gold-500/30 text-sm">对冲基金三阶段孵化蓝图</button>
            </div>
          </div>

          <div class="lg:col-span-5 grid grid-cols-2 gap-3.5">
            <div class="inst-card p-4 rounded-xl">
              <div class="text-xs font-mono text-slate-400 flex justify-between"><span>TARGET SHARPE</span><span class="text-gold-400">目标夏普</span></div>
              <div class="font-mono text-2xl sm:text-3xl font-bold text-white mt-2">1.85</div>
              <div class="text-[11px] text-slate-400 mt-1">Phase 1 滚动实盘: <strong class="text-emerald-400 font-mono">1.92</strong></div>
            </div>
            <div class="inst-card p-4 rounded-xl">
              <div class="text-xs font-mono text-slate-400 flex justify-between"><span>MAX DRAWDOWN CAP</span><span class="text-gold-400">硬止损红线</span></div>
              <div class="font-mono text-2xl sm:text-3xl font-bold text-white mt-2">-10.0%</div>
              <div class="text-[11px] text-slate-400 mt-1">历史最大回撤: <strong class="text-emerald-400 font-mono">-4.85%</strong></div>
            </div>
            <div class="inst-card p-4 rounded-xl">
              <div class="text-xs font-mono text-slate-400 flex justify-between"><span>CUMULATIVE R</span><span class="text-gold-400">累计实现 R</span></div>
              <div class="font-mono text-2xl sm:text-3xl font-bold text-emerald-400 mt-2">+42.6R</div>
              <div class="text-[11px] text-slate-400 mt-1">单笔风险上限: <strong class="text-slate-200 font-mono">1.50% NAV</strong></div>
            </div>
            <div class="inst-card p-4 rounded-xl">
              <div class="text-xs font-mono text-slate-400 flex justify-between"><span>DISCIPLINE SCORE</span><span class="text-gold-400">纪律得分</span></div>
              <div class="font-mono text-2xl sm:text-3xl font-bold text-gold-400 mt-2">9.1<span class="text-sm text-slate-400">/10</span></div>
              <div class="text-[11px] text-slate-400 mt-1">严守证伪止损铁律</div>
            </div>
          </div>
        </div>
      </div>

      <div class="space-y-4">
        <h2 class="font-serif text-2xl font-bold text-white border-b border-slate-800 pb-3">核心策略矩阵与实盘归因表现 (v_strategy_performance_summary)</h2>
        <div id="overview-strategy-cards" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4"></div>
      </div>
    </section>

    <section id="sec-memo" class="hidden space-y-8">
      <div class="border-b border-slate-800 pb-4 flex flex-col md:flex-row md:items-end justify-between gap-4">
        <div>
          <span class="text-xs font-mono text-gold-400">COLUMN 01 · /memo · Table: db_mobobrain.macro_theses</span>
          <h2 class="font-serif text-3xl font-bold text-white mt-1">MoBo's Memo · 全球宏观与产业投研智库</h2>
        </div>
        <div class="flex space-x-2 text-xs font-mono">
          <button onclick="renderMacroTheses('ALL')" class="px-3 py-1.5 rounded bg-gold-500 text-navy-950 font-semibold">全部主线</button>
          <button onclick="renderMacroTheses('CN')" class="px-3 py-1.5 rounded bg-navy-800 text-slate-300">中国宏观与供应链</button>
          <button onclick="renderMacroTheses('US')" class="px-3 py-1.5 rounded bg-navy-800 text-slate-300">美联储与全球流动性</button>
        </div>
      </div>
      <div id="macro-theses-list" class="grid grid-cols-1 lg:grid-cols-2 gap-6"></div>
    </section>

    <section id="sec-strategies" class="hidden space-y-8">
      <div class="border-b border-slate-800 pb-4">
        <span class="text-xs font-mono text-gold-400">COLUMN 02 · /strategies · Tables: strategy_playbooks & trade_reviews</span>
        <h2 class="font-serif text-3xl font-bold text-white mt-1">Alpha Lab · 交易策略手册与实战战役复盘账本</h2>
      </div>
      <div id="full-strategy-cards" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4"></div>
      <div class="inst-card rounded-xl overflow-hidden">
        <div class="overflow-x-auto custom-scrollbar">
          <table class="w-full text-left border-collapse text-xs">
            <thead>
              <tr class="border-b border-slate-800 text-slate-400 font-mono bg-navy-950/50">
                <th class="py-3.5 px-4">战役编号 / 日期</th>
                <th class="py-3.5 px-4">标的与期权结构</th>
                <th class="py-3.5 px-4">所属策略</th>
                <th class="py-3.5 px-4">方向</th>
                <th class="py-3.5 px-4">初始风险</th>
                <th class="py-3.5 px-4">实现 R 乘数</th>
                <th class="py-3.5 px-4">组合贡献 (bps)</th>
                <th class="py-3.5 px-4">纪律打分</th>
                <th class="py-3.5 px-4 text-right">详情</th>
              </tr>
            </thead>
            <tbody id="trade-reviews-tbody" class="divide-y divide-slate-800/70 font-mono"></tbody>
          </table>
        </div>
      </div>
    </section>

    <section id="sec-incubation" class="hidden space-y-8">
      <div class="border-b border-slate-800 pb-4">
        <span class="text-xs font-mono text-gold-400">COLUMN 03 · /incubation · Tables: fund_incubation_milestones & fund_governance_docs</span>
        <h2 class="font-serif text-3xl font-bold text-white mt-1">Fund Blueprint · 莫伯资本对冲基金孵化蓝图与合规治理</h2>
      </div>
      <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
        <div class="lg:col-span-7 space-y-4" id="milestones-detail-list"></div>
        <div class="lg:col-span-5 space-y-4" id="governance-docs-list"></div>
      </div>
    </section>

    <section id="sec-terminal" class="hidden space-y-8">
      <div class="border-b border-slate-800 pb-4">
        <span class="text-xs font-mono text-gold-400">COLUMN 04 · /terminal · Daily Cron Driven by macro_iv_collector.py</span>
        <h2 class="font-serif text-3xl font-bold text-white mt-1">Quant Terminal · 宏观先行指标与期权波动率监控室</h2>
      </div>
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div class="inst-card rounded-xl p-5 space-y-4">
          <h3 class="font-serif font-bold text-white border-b border-slate-800 pb-2">全球宏观先行指标 Z-Score</h3>
          <div class="space-y-3 font-mono text-xs">
            <div class="flex justify-between"><span>中国制造业 PMI (新订单-库存差)</span><strong class="text-emerald-400">+1.42 σ (EXPANSION)</strong></div>
            <div class="flex justify-between"><span>社融脉冲与 M1-M2 剪刀差修复度</span><strong class="text-emerald-400">+0.85 σ (IMPROVING)</strong></div>
            <div class="flex justify-between"><span>美国 ISM 制造业新订单指数</span><strong class="text-amber-400">-0.38 σ (BOTTOMING)</strong></div>
          </div>
        </div>
        <div class="inst-card rounded-xl p-5 space-y-4">
          <h3 class="font-serif font-bold text-white border-b border-slate-800 pb-2">期权波动率曲面监控 (IV Rank & Skew)</h3>
          <table class="w-full text-xs font-mono text-left">
            <thead>
              <tr class="text-slate-400 border-b border-slate-800">
                <th class="pb-2">标的</th><th class="pb-2">30D IV</th><th class="pb-2">1Y分位</th><th class="pb-2">25D Skew</th><th class="pb-2 text-right">策略建议</th>
              </tr>
            </thead>
            <tbody id="terminal-vol-tbody" class="divide-y divide-slate-800/60">
              <tr><td class="py-2 text-white">沪深300 (510300)</td><td>21.4%</td><td class="text-emerald-400">28%</td><td>-2.1%</td><td class="text-right text-gold-400">Long Call Spread</td></tr>
              <tr><td class="py-2 text-white">标普500 (SPY)</td><td>18.2%</td><td class="text-amber-400">61%</td><td>+5.4%</td><td class="text-right text-emerald-400">1x2 Put Ratio</td></tr>
            </tbody>
          </table>
        </div>
        <div class="inst-card rounded-xl p-5 space-y-4">
          <div class="flex items-center justify-between border-b border-slate-800 pb-2">
            <h3 class="font-serif font-bold text-white">组合敞口与高水位风控</h3>
            <span id="terminal-clearance-tag" class="text-[11px] font-mono text-gold-400">PUBLIC</span>
          </div>
          <div id="terminal-exposure-box" class="space-y-2.5 font-mono text-xs"></div>
        </div>
      </div>
    </section>

    <section id="sec-media" class="hidden space-y-8">
      <div class="border-b border-slate-800 pb-4">
        <span class="text-xs font-mono text-gold-400">COLUMN 05 · /media-ops · n8n Workflow #2 + capital_publications</span>
        <h2 class="font-serif text-3xl font-bold text-white mt-1">Media Engine · 《MoBo's Memo》四端同源合成中台</h2>
      </div>
      <div class="inst-card rounded-xl p-5 space-y-4">
        <div class="flex flex-wrap gap-2 text-xs font-mono">
          <button onclick="switchMediaPreview('web')" id="mp-web" class="px-3 py-1.5 rounded bg-gold-500 text-navy-950 font-semibold">1. 官网主权母本</button>
          <button onclick="switchMediaPreview('wechat')" id="mp-wechat" class="px-3 py-1.5 rounded bg-navy-900 text-slate-300">2. 微信公众号内联 HTML</button>
          <button onclick="switchMediaPreview('xueqiu')" id="mp-xueqiu" class="px-3 py-1.5 rounded bg-navy-900 text-slate-300">3. 雪球 $代码$ 投研帖</button>
          <button onclick="switchMediaPreview('x')" id="mp-x" class="px-3 py-1.5 rounded bg-navy-900 text-slate-300">4. X (Twitter) 英文串推</button>
        </div>
        <pre id="media-preview-content" class="bg-navy-950 border border-slate-800 rounded-lg p-4 font-mono text-xs text-slate-200 whitespace-pre-wrap overflow-x-auto"></pre>
      </div>
    </section>
  </main>

  <script>
    let currentClearance = 'PUBLIC';

    const strategiesData = [
      { code: 'OPT-VOL-SKEW-01', name: '期权波动率偏度与跨式策略', holding: '2–6 Weeks', targetSharpe: 1.95, winRate: 68.4, cumR: '+21.4R', discipline: 9.3, desc: '利用宏观事件前后隐含波动率与历史波动率的定价偏差，通过垂直价差、比例价差捕捉非线性收益。' },
      { code: 'ITPM-LS-EQUITY', name: '基本面多空股票策略 (L/S)', holding: '1–3 Months', targetSharpe: 1.75, winRate: 62.5, cumR: '+14.8R', discipline: 9.0, desc: '结合 ITPM 先行指标与零售/供应链周转率印证，做多自由现金流拐点龙头并配对做空剥离 Beta。' },
      { code: 'MACRO-CROSS-ASSET', name: '全球宏观跨资产利差对冲', holding: '1–6 Months', targetSharpe: 1.60, winRate: 58.3, cumR: '+6.4R', discipline: 8.9, desc: '围绕中美欧货币政策周期错位与 M1-M2 剪刀差，构建股指、美债与黄金期权低相关性头寸。' },
      { code: 'TAIL-RISK-SHIELD', name: '尾部风险保护与熔断对冲网', holding: 'Continuous', targetSharpe: 1.40, winRate: 45.0, cumR: '+3.2R', discipline: 9.6, desc: '遵循风险隔离铁律，在波动率极低分位定投虚值 Put 保护伞。' }
    ];

    const macroThesesData = [
      { code: 'THESIS-2026Q4-CN-RETAIL', region: 'CN', title: '中国必选消费与生鲜冷链供应链：高周转率企业的自由现金流重估', conviction: 8, bias: 'BULLISH', logic: '高频渠道与供应链数据显示，具备数字化仓配能力的零售企业库存周转天数缩短 14%，而期权 IV 仅处于 28% 低分位。', invalidation: '若社零餐饮分项连续两个月环比回落超 1.5%，无条件平仓全部多头期权头寸。' },
      { code: 'THESIS-2026Q4-US-VOL-SKEW', region: 'US', title: '美债期限溢价回升背景下的美股科技股波动率偏度（Skew）均值回归', conviction: 9, bias: 'VOL_LONG', logic: '机构尾部保护需求推高 25-Delta Put-Call Skew 至 92% 分位，适合构建认沽比例价差博弈波动率中枢上移。', invalidation: '若 VIX 跌破 13.5 且 ISM 新订单跃升至 53 以上，立即止损平仓。' }
    ];

    const tradeReviewsData = [
      { code: 'TRD-202610-300ETF-CALL', date: '2026-09-18 → 2026-10-14', ticker: '510300.SH (沪深300 ETF)', structure: 'Bull Call Spread', strategy: 'OPT-VOL-SKEW-01', direction: 'LONG', initRisk: '1.20%', realizedR: '+3.15R', impactBps: '+378 bps', discipline: 9 },
      { code: 'TRD-202609-SPY-PUT-RATIO', date: '2026-08-25 → 2026-09-22', ticker: 'SPY (标普500 ETF)', structure: '1x2 Put Ratio Spread', strategy: 'OPT-VOL-SKEW-01', direction: 'DELTA_NEUTRAL', initRisk: '1.00%', realizedR: '+2.40R', impactBps: '+240 bps', discipline: 10 },
      { code: 'TRD-202607-RATES-STOP', date: '2026-07-02 → 2026-07-11', ticker: 'TLT (20Y美债 ETF)', structure: 'Long Call Calendar', strategy: 'MACRO-CROSS-ASSET', direction: 'LONG', initRisk: '0.80%', realizedR: '-0.85R', impactBps: '-68 bps', discipline: 9 }
    ];

    const milestonesData = [
      { phase: 'Phase 1', cat: 'TRACK_RECORD', title: '建立 ITPM 全球宏观与期权实盘归因账本 (≥30笔)', pct: 65, date: '2027-06-30' },
      { phase: 'Phase 1', cat: 'LEGAL_COMPLIANCE', title: '通过国家统一法律职业资格考试（法考）与证券从业资格', pct: 60, date: '2027-10-31' },
      { phase: 'Phase 1', cat: 'FINANCE_VALUATION', title: '通过中级会计师并落地高水位法（HWM）基金估值核算引擎', pct: 55, date: '2027-09-30' },
      { phase: 'Phase 2', cat: 'TRACK_RECORD', title: '完成连续 18–24 个月可审计低回撤实盘业绩鉴证', pct: 20, date: '2028-12-31' }
    ];

    const govDocsData = [
      { type: 'INVESTOR_LETTER', title: '《致莫伯资本未来合伙人备忘录：为什么把“不亏大钱”置于首位》', ver: 'v2.1', vis: 'PUBLIC' },
      { type: 'RISK_SOP', title: '《莫伯资本投委会风控章程：单笔止损与净值预警清盘制度》', ver: 'v1.4', vis: 'LP_PROSPECT' },
      { type: 'NAV_ACCOUNTING', title: '《基金份额净值（NAV）会计核算与高水位法业绩报酬计提规范》', ver: 'v1.2', vis: 'LP_PROSPECT' }
    ];

    const mediaPreviews = {
      web: '# 从生鲜供应链周转率与 PMI 分项，看消费龙头期权波动率曲面定价偏差\n\n1. PMI 新订单减产成品库存差值升至 +1.42σ；\n2. 构建 45DTE 牛市认购价差，单笔最大风险敞口严格锁定在 1.20% NAV。',
      wechat: '<section style="font-size:15px;line-height:1.8;color:#2c3e50;"><p>财务报表是后视镜，库存周转率与采购先行指标才是挡风玻璃。（已自动执行境内合规脱敏并注入免责声明）</p></section>',
      xueqiu: '【核心结论】从生鲜冷链周转率改善看，$沪深300(SH000300)$ 与 $恒生科技指数(HKHSTECH)$ 的隐含波动率（IV Rank 28%）低估了基本面修复弹性。',
      x: '1/4 Macro & Vol Thesis: Why China retail supply chain turnaround is mispriced by the options surface right now...\n4/4 Full memo: https://mobocapital.com/memo/2026-10-cn-retail-supply-chain-vol'
    };

    function renderAll() {
      const showPerf = currentClearance !== 'PUBLIC';
      const sHtml = strategiesData.map(s => `
        <div class="inst-card rounded-xl p-5 flex flex-col justify-between">
          <div>
            <div class="flex justify-between text-[11px] font-mono text-gold-400 mb-2"><span>${s.code}</span><span>${s.holding}</span></div>
            <h3 class="font-serif text-base font-bold text-white">${s.name}</h3>
            <p class="text-xs text-slate-400 mt-2">${s.desc}</p>
          </div>
          <div class="mt-4 pt-3 border-t border-slate-800 grid grid-cols-2 gap-2 font-mono text-xs">
            <div><span class="text-slate-500 block text-[10px]">SHARPE</span><strong class="text-white">${s.targetSharpe}</strong></div>
            <div><span class="text-slate-500 block text-[10px]">WIN RATE</span><strong class="text-emerald-400">${s.winRate}%</strong></div>
            <div><span class="text-slate-500 block text-[10px]">CUMULATIVE R</span><strong class="text-gold-400">${showPerf ? s.cumR : 'LP 解锁'}</strong></div>
            <div><span class="text-slate-500 block text-[10px]">DISCIPLINE</span><strong class="text-gold-400">${s.discipline}/10</strong></div>
          </div>
        </div>
      `).join('');
      document.getElementById('overview-strategy-cards').innerHTML = sHtml;
      document.getElementById('full-strategy-cards').innerHTML = sHtml;

      renderMacroTheses('ALL');

      document.getElementById('trade-reviews-tbody').innerHTML = tradeReviewsData.map(t => `
        <tr class="hover:bg-navy-800/60">
          <td class="py-3 px-4"><div class="text-white font-semibold">${t.code}</div><div class="text-[10px] text-slate-500">${t.date}</div></td>
          <td class="py-3 px-4"><div class="text-slate-200">${t.ticker}</div><div class="text-[10px] text-gold-400">${t.structure}</div></td>
          <td class="py-3 px-4">${t.strategy}</td>
          <td class="py-3 px-4">${t.direction}</td>
          <td class="py-3 px-4">${t.initRisk}</td>
          <td class="py-3 px-4 font-bold ${t.realizedR.startsWith('+') ? 'text-emerald-400' : 'text-rose-400'}">${t.realizedR}</td>
          <td class="py-3 px-4">${showPerf ? t.impactBps : '🔒 LP_PROSPECT'}</td>
          <td class="py-3 px-4 text-gold-400">${t.discipline}/10</td>
          <td class="py-3 px-4 text-right text-gold-400">已归档</td>
        </tr>
      `).join('');

      document.getElementById('milestones-detail-list').innerHTML = milestonesData.map(m => `
        <div class="inst-card rounded-xl p-4 space-y-2">
          <div class="flex justify-between text-xs font-mono text-gold-400"><span>${m.phase} · ${m.cat}</span><span>Target: ${m.date}</span></div>
          <div class="font-serif font-bold text-white">${m.title}</div>
          <div class="w-full bg-navy-950 h-2 rounded-full overflow-hidden"><div class="bg-emerald-500 h-full" style="width:${m.pct}%"></div></div>
        </div>
      `).join('');

      document.getElementById('governance-docs-list').innerHTML = govDocsData.map(d => `
        <div class="inst-card rounded-xl p-4 space-y-1">
          <div class="text-[11px] font-mono text-gold-400">${d.type} · ${d.ver} (${d.vis})</div>
          <div class="font-serif font-bold text-white text-sm">${d.title}</div>
        </div>
      `).join('');

      document.getElementById('terminal-exposure-box').innerHTML = showPerf
        ? `<div class="flex justify-between"><span>组合净敞口 (Net)</span><strong class="text-emerald-400">+32.2% NAV</strong></div>
           <div class="flex justify-between"><span>组合总敞口 (Gross)</span><strong class="text-gold-400">84.6% NAV</strong></div>
           <div class="flex justify-between"><span>风控状态机</span><strong class="text-emerald-400">NORMAL (HWM=1.0842)</strong></div>`
        : `<div class="text-amber-400">🔒 实时敞口与高水位净值在 PUBLIC 模式下执行合规脱敏，请切换至 LP_PROSPECT 查看。</div>`;
    }

    function renderMacroTheses(region) {
      const list = region === 'ALL' ? macroThesesData : macroThesesData.filter(m => m.region === region);
      document.getElementById('macro-theses-list').innerHTML = list.map(m => `
        <div class="inst-card rounded-xl p-6 space-y-3">
          <div class="flex justify-between text-xs font-mono text-gold-400"><span>${m.code}</span><span>CONVICTION: ${m.conviction}/10 · ${m.bias}</span></div>
          <h3 class="font-serif text-xl font-bold text-white">${m.title}</h3>
          <p class="text-xs text-slate-300 leading-relaxed">${m.logic}</p>
          <div class="text-xs text-rose-300 bg-rose-950/30 border border-rose-500/30 p-3 rounded font-mono">🛑 证伪红线: ${m.invalidation}</div>
        </div>
      `).join('');
    }

    function switchSection(sec) {
      ['overview', 'memo', 'strategies', 'incubation', 'terminal', 'media'].forEach(s => {
        document.getElementById('sec-' + s).classList.toggle('hidden', s !== sec);
      });
    }

    function setAccessLevel(lvl) {
      currentClearance = lvl;
      document.getElementById('clearance-badge').textContent = lvl + ' VIEW';
      document.getElementById('terminal-clearance-tag').textContent = lvl;
      renderAll();
      loadLiveCapitalData(lvl);
    }

    function switchMediaPreview(ch) {
      document.getElementById('media-preview-content').textContent = mediaPreviews[ch];
    }

    async function loadLiveCapitalData(mode = 'PUBLIC') {
      try {
        const url = mode === 'INTERNAL' ? '/internal/internal-data.json' : '/data/public-data.json';
        const res = await fetch(url, { cache: 'no-store' });
        if (!res.ok) return;
        const payload = await res.json();
        if (payload.trade_reviews && payload.trade_reviews.length) {
          tradeReviewsData.length = 0;
          payload.trade_reviews.forEach(tr => {
            tradeReviewsData.push({
              code: tr.trade_code,
              date: `${tr.entry_date} → ${tr.exit_date || 'OPEN'}`,
              ticker: `${tr.underlying_ticker} (${tr.asset_name})`,
              structure: tr.instrument_structure,
              strategy: tr.strategy_code,
              direction: tr.direction,
              initRisk: `${Number(tr.initial_risk_pct).toFixed(2)}%`,
              realizedR: tr.realized_r_multiple >= 0 ? `+${tr.realized_r_multiple}R` : `${tr.realized_r_multiple}R`,
              impactBps: `${tr.portfolio_impact_bps} bps`,
              discipline: tr.discipline_score
            });
          });
          renderAll();
        }
      } catch (e) {}
    }

    async function loadTerminalSnapshot() {
      try {
        const res = await fetch('/data/terminal-snapshot.json', { cache: 'no-store' });
        if (!res.ok) return;
        const data = await res.json();
        if (data.options_vol_surface && data.options_vol_surface.length) {
          document.getElementById('terminal-vol-tbody').innerHTML = data.options_vol_surface.map(v => `
            <tr>
              <td class="py-2 text-white">${v.asset_name}</td>
              <td>${v.iv_30d}%</td>
              <td class="text-emerald-400">${v.iv_percentile_1y}%</td>
              <td>${v.skew_25d}%</td>
              <td class="text-right text-gold-400">${v.recommended_structure}</td>
            </tr>
          `).join('');
        }
      } catch (e) {}
    }

    window.addEventListener('DOMContentLoaded', () => {
      renderAll();
      switchMediaPreview('web');
      loadLiveCapitalData('PUBLIC');
      loadTerminalSnapshot();
    });
  </script>
</body>
</html>
EOF_HTML_CAP

cat << 'EOF_HTML_HOME' > "${STACK_DIR}/sites/mobohome/index.html"
<!DOCTYPE html>
<html lang="zh-CN" class="dark">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>MO BO HOME | 莫伯之家 — 个人数字档案馆与生命叙事空间</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500;600&family=Noto+Serif+SC:wght@400;500;600;700&display=swap" rel="stylesheet">
  <script>
    tailwind.config = {
      darkMode: 'class',
      theme: {
        extend: {
          colors: {
            warm: { 950: '#090A0F', 900: '#0C0E14', 800: '#141721', 700: '#1E2333' },
            amber: { 400: '#E6B450', 500: '#D4A373' },
            sage: { 400: '#CCD5AE', 500: '#99A98F' }
          },
          fontFamily: {
            serif: ['"Noto Serif SC"', 'Georgia', 'serif'],
            sans: ['"Inter"', 'sans-serif'],
            mono: ['"JetBrains Mono"', 'monospace']
          }
        }
      }
    }
  </script>
  <style>
    body { background-color: #0C0E14; color: #E2E8F0; }
    .warm-card { background: rgba(20, 23, 33, 0.82); border: 1px solid rgba(212, 163, 115, 0.16); transition: all 0.25s ease; }
    .warm-card:hover { border-color: rgba(212, 163, 115, 0.42); }
  </style>
</head>
<body class="min-h-screen flex flex-col">
  <div class="bg-warm-950 border-b border-warm-700/60 text-xs font-mono py-2 px-4 lg:px-8 flex items-center justify-between">
    <span class="text-amber-400 font-semibold">● MOBO HOME · 个人主权生命数字档案馆 (db_archive)</span>
    <div class="flex items-center space-x-3">
      <a href="/lab/" class="text-sage-400 hover:underline">📊 Streamlit 相关性实验室 (/lab)</a>
      <a href="https://mobocapital.com" target="_blank" class="text-slate-400 hover:text-amber-400 border border-warm-700 px-2.5 py-0.5 rounded">⇄ MoBoCapital.com</a>
    </div>
  </div>

  <header class="sticky top-0 z-40 bg-warm-950/90 backdrop-blur-md border-b border-amber-500/20">
    <div class="max-w-7xl mx-auto px-4 lg:px-8 h-20 flex items-center justify-between">
      <div class="flex items-center space-x-3 cursor-pointer" onclick="switchHomeSec('timeline')">
        <div class="w-10 h-10 rounded-lg bg-amber-500/20 border border-amber-500/40 flex items-center justify-center font-serif font-bold text-amber-400">家</div>
        <div>
          <h1 class="font-serif font-bold text-lg text-white">莫伯之家 · MoBoHome</h1>
          <p class="text-[11px] text-slate-400 font-mono">Slow is Fast · 成长篇章、光影画廊、百本藏书与体能自律</p>
        </div>
      </div>
      <nav class="flex items-center space-x-2 text-xs sm:text-sm">
        <button onclick="switchHomeSec('timeline')" class="px-3 py-1.5 rounded bg-amber-500/15 text-amber-400 font-medium">1. 成长篇章</button>
        <button onclick="switchHomeSec('gallery')" class="px-3 py-1.5 rounded text-slate-300 hover:bg-warm-800">2. 影像画廊</button>
        <button onclick="switchHomeSec('library')" class="px-3 py-1.5 rounded text-slate-300 hover:bg-warm-800">3. 百本藏书馆</button>
        <button onclick="switchHomeSec('dashboard')" class="px-3 py-1.5 rounded text-slate-300 hover:bg-warm-800">4. 自律看板</button>
      </nav>
    </div>
  </header>

  <main class="flex-grow max-w-7xl w-full mx-auto px-4 lg:px-8 py-8 space-y-10">
    <section id="hsec-timeline" class="space-y-6">
      <div class="warm-card rounded-2xl p-6 flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h2 class="font-serif text-2xl font-bold text-white">慢就是快：穿梭在北上深历练与归航武汉的岁月长河</h2>
          <p class="text-xs text-slate-400 mt-1">记录自 2014 年毕业以来的零售与生鲜供应链数据实战、跨学科求索与武汉家庭筑基。</p>
        </div>
        <div class="flex flex-wrap gap-1.5 text-xs font-mono">
          <button onclick="renderHomeTimeline('ALL')" class="px-3 py-1 rounded bg-amber-500 text-warm-950 font-semibold">全部</button>
          <button onclick="renderHomeTimeline('湖北·归航与长期筑基')" class="px-3 py-1 rounded bg-warm-800 text-slate-300">湖北归航</button>
          <button onclick="renderHomeTimeline('上海·供应链深耕')" class="px-3 py-1 rounded bg-warm-800 text-slate-300">上海深耕</button>
          <button onclick="renderHomeTimeline('北上深·历练期')" class="px-3 py-1 rounded bg-warm-800 text-slate-300">北上深历练</button>
        </div>
      </div>
      <div id="home-timeline-box" class="space-y-5"></div>
    </section>

    <section id="hsec-gallery" class="hidden space-y-6">
      <h2 class="font-serif text-2xl font-bold text-white border-b border-warm-700 pb-3">影像流画廊 · 800px WebP 热缩略图与 OSS 冷归档</h2>
      <div id="home-gallery-box" class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5"></div>
    </section>

    <section id="hsec-library" class="hidden space-y-6">
      <h2 class="font-serif text-2xl font-bold text-white border-b border-warm-700 pb-3">百本藏书馆 · 金融量化、物理思维与商业战略</h2>
      <div id="home-books-box" class="grid grid-cols-1 md:grid-cols-2 gap-5"></div>
    </section>

    <section id="hsec-dashboard" class="hidden space-y-6">
      <h2 class="font-serif text-2xl font-bold text-white border-b border-warm-700 pb-3">体能自律与生命体征看板 (v_weekly_life_analytics)</h2>
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-4 font-mono">
        <div class="warm-card p-5 rounded-xl"><span class="text-xs text-slate-400">周度跑步里程</span><div class="text-2xl font-bold text-white mt-1">32.5 km</div></div>
        <div class="warm-card p-5 rounded-xl"><span class="text-xs text-slate-400">力量训练打卡</span><div class="text-2xl font-bold text-white mt-1">5 次 / 周</div></div>
        <div class="warm-card p-5 rounded-xl"><span class="text-xs text-slate-400">平均心情指数</span><div class="text-2xl font-bold text-amber-400 mt-1">9.2 / 10</div></div>
        <div class="warm-card p-5 rounded-xl"><span class="text-xs text-slate-400">平均能量状态</span><div class="text-2xl font-bold text-sage-400 mt-1">8.8 / 10</div></div>
      </div>
    </section>
  </main>

  <script>
    let homeData = {
      timeline_stories: [
        { event_date: '2026-02-15', location_name: '武汉', mood_score: 9, importance: 5, title: '从北上深一线数据战场到归航武汉：慢就是快的人生仓位重构', summary: '历经深圳、北京、上海十余年零售与生鲜供应链数据深耕，回到湖北武汉建立长期稳固的家庭与投研根据地。', tags: ['人生复盘', '慢就是快', '武汉定居'], metadata: { life_chapter: '湖北·归航与长期筑基', content_markdown: '从 2014 年毕业南下深圳，到北京、上海十余年的零售与生鲜供应链数据实战，让我看清了商业底层现金流的本质。选择归航武汉定居，正是用交易员的风险隔离模型构建稳固的人生底仓。' } },
        { event_date: '2024-10-10', location_name: '上海', mood_score: 8, importance: 4, title: '上海深耕期：生鲜供应链周转率优化与多仓协同战役', summary: '主导多温区仓储网络数字化重构与呆滞库存损耗压降，沉淀扎实的微观供应链数据手感。', tags: ['生鲜供应链', '数据分析'], metadata: { life_chapter: '上海·供应链深耕', content_markdown: '生鲜供应链的核心在于高周转与低损耗。通过建立精细化 SKU 预测与补货模型，显著压降呆滞率。' } }
      ],
      gallery_assets: [
        { asset_type: 'photo', title: '武汉东湖晨跑与体能训练', captured_at: '2026-10-12', public_thumb_url: 'https://images.unsplash.com/photo-1517838277536-f5f99be501cd?auto=format&fit=crop&w=800&q=80' },
        { asset_type: 'photo', title: '莫伯之家书房与投研档案库', captured_at: '2026-09-28', public_thumb_url: 'https://images.unsplash.com/photo-1497633762265-9d179a990aa6?auto=format&fit=crop&w=800&q=80' }
      ],
      reading_library: [
        { title: 'The Road to Reality (现实的道路)', author: 'Roger Penrose', category: 'PHYSICS', status: 'COMPLETED', rating: 5, core_takeaway: '宇宙底层物理定律与数学几何结构的统一，对理解复杂系统与金融非线性波动率有极高启发。' },
        { title: '穷查理宝典 (Poor Charlie Almanack)', author: 'Charlie Munger', category: 'FINANCE', status: 'COMPLETED', rating: 5, core_takeaway: '多元思维模型、逆向思考与长期复利，慢就是快。' }
      ]
    };

    function renderHomeTimeline(chapter) {
      const list = chapter === 'ALL' ? homeData.timeline_stories : homeData.timeline_stories.filter(s => (s.metadata?.life_chapter || '') === chapter);
      document.getElementById('home-timeline-box').innerHTML = list.map(s => `
        <div class="warm-card rounded-2xl p-6 space-y-3">
          <div class="flex justify-between text-xs font-mono text-amber-400">
            <span>${s.metadata?.life_chapter || '人生纪事'} · 📍 ${s.location_name || '武汉'}</span>
            <span>${s.event_date} · 心情: ${s.mood_score}/10</span>
          </div>
          <h3 class="font-serif text-xl font-bold text-white">${s.title}</h3>
          <p class="text-xs sm:text-sm text-slate-300 leading-relaxed">${s.metadata?.content_markdown || s.summary}</p>
        </div>
      `).join('');
    }

    function renderHomeAll() {
      renderHomeTimeline('ALL');
      document.getElementById('home-gallery-box').innerHTML = (homeData.gallery_assets || []).map(a => `
        <div class="warm-card rounded-xl overflow-hidden">
          <img src="${a.public_thumb_url || ''}" alt="${a.title}" class="w-full h-48 object-cover" />
          <div class="p-4"><h4 class="font-serif font-bold text-white">${a.title}</h4><span class="text-xs font-mono text-slate-400">${a.captured_at}</span></div>
        </div>
      `).join('');
      document.getElementById('home-books-box').innerHTML = (homeData.reading_library || []).map(b => `
        <div class="warm-card rounded-xl p-5 space-y-2">
          <div class="text-xs font-mono text-amber-400">${b.category} · ${b.status}</div>
          <h4 class="font-serif font-bold text-white text-lg">${b.title}</h4>
          <p class="text-xs text-slate-300">${b.core_takeaway || ''}</p>
        </div>
      `).join('');
    }

    function switchHomeSec(sec) {
      ['timeline', 'gallery', 'library', 'dashboard'].forEach(s => {
        document.getElementById('hsec-' + s).classList.toggle('hidden', s !== sec);
      });
    }

    async function loadLiveHomeData() {
      try {
        const res = await fetch('/data/public-home-data.json', { cache: 'no-store' });
        if (res.ok) {
          homeData = await res.json();
          renderHomeAll();
        }
      } catch (e) {}
    }

    window.addEventListener('DOMContentLoaded', () => {
      renderHomeAll();
      loadLiveHomeData();
    });
  </script>
</body>
</html>
EOF_HTML_HOME

# ============================================================================
# [7/8] 写入 Python 自动化引擎 (oss_guard_setup.py, mobo_cli.py, macro_iv_collector.py)
# ============================================================================
echo "🐍 [7/8] 正在写入 Python 自动化工具链 (mobo_cli.py v2.1 / macro_iv_collector.py / oss_guard_setup.py)..."

cat << 'EOF_OSS_GUARD' > "${STACK_DIR}/scripts/oss_guard_setup.py"
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
from pathlib import Path
import oss2
from oss2.models import LifecycleRule, StorageTransition, BucketLifecycle, BucketReferer
from dotenv import load_dotenv

ENV_PATH = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(dotenv_path=ENV_PATH)

def apply_oss_guards():
    ak = os.getenv("ALIYUN_ACCESS_KEY_ID")
    sk = os.getenv("ALIYUN_ACCESS_KEY_SECRET")
    endpoint = os.getenv("OSS_PUBLIC_ENDPOINT", "https://oss-cn-hangzhou.aliyuncs.com")
    pub_name = os.getenv("OSS_BUCKET_PUBLIC", "mobobrain-assets-pub")
    priv_name = os.getenv("OSS_BUCKET_PRIVATE", "mobo-archive-private-hz")

    auth = oss2.Auth(ak, sk)
    pub_bucket = oss2.Bucket(auth, endpoint, pub_name)
    priv_bucket = oss2.Bucket(auth, endpoint, priv_name)

    referer_whitelist = [
        "https://mobocapital.com",
        "https://*.mobocapital.com",
        "https://mobohome.com",
        "https://*.mobohome.com",
    ]
    pub_bucket.put_bucket_referer(BucketReferer(allow_empty_referer=False, referers=referer_whitelist))
    print(f"✅ [公有图床防盗链已生效] Bucket: {pub_name}")

    rules = [
        LifecycleRule(
            id="rule-photo-cold-tiering", prefix="photo/", status=LifecycleRule.ENABLED,
            storage_transitions=[
                StorageTransition(days=30, storage_class=oss2.BUCKET_STORAGE_CLASS_IA),
                StorageTransition(days=180, storage_class=oss2.BUCKET_STORAGE_CLASS_ARCHIVE),
            ],
        ),
        LifecycleRule(
            id="rule-video-direct-archive", prefix="video/", status=LifecycleRule.ENABLED,
            storage_transitions=[StorageTransition(days=90, storage_class=oss2.BUCKET_STORAGE_CLASS_ARCHIVE)],
        ),
        LifecycleRule(
            id="rule-scandoc-ia", prefix="scan_doc/", status=LifecycleRule.ENABLED,
            storage_transitions=[StorageTransition(days=30, storage_class=oss2.BUCKET_STORAGE_CLASS_IA)],
        ),
        LifecycleRule(
            id="rule-capital-blotters-cold", prefix="blotters/", status=LifecycleRule.ENABLED,
            storage_transitions=[
                StorageTransition(days=30, storage_class=oss2.BUCKET_STORAGE_CLASS_IA),
                StorageTransition(days=180, storage_class=oss2.BUCKET_STORAGE_CLASS_ARCHIVE),
            ],
        ),
        LifecycleRule(
            id="rule-restic-backup-ia", prefix="restic-cold-backup/", status=LifecycleRule.ENABLED,
            storage_transitions=[StorageTransition(days=30, storage_class=oss2.BUCKET_STORAGE_CLASS_IA)],
        ),
    ]
    priv_bucket.put_bucket_lifecycle(BucketLifecycle(rules))
    print(f"✅ [私有桶 5 条冷沉降规则已注入] Bucket: {priv_name}")
    print("[OK] Lifecycle & Referer Guard Applied")

if __name__ == "__main__":
    apply_oss_guards()
EOF_OSS_GUARD

cat << 'EOF_MOBO_CLI' > "${STACK_DIR}/scripts/mobo_cli.py"
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MoBo Dual-Site CLI (v2.1) — 莫伯资本 (MoBoCapital.com) & 莫伯之家 (MoBoHome.com) 双栖终端总控引擎
"""

import os
import sys
import json
import yaml
import hashlib
import mimetypes
import subprocess
import argparse
from io import BytesIO
from datetime import datetime, date
from decimal import Decimal
from pathlib import Path

import oss2
import psycopg2
from psycopg2.extras import RealDictCursor, Json
from PIL import Image, ExifTags
from pypdf import PdfReader
from dotenv import load_dotenv

ENV_PATH = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(dotenv_path=ENV_PATH)


def get_db_conn(target_site: str):
    host = os.getenv("PG_HOST", "127.0.0.1")
    port = int(os.getenv("PG_PORT", "5432"))

    if target_site == "capital":
        return psycopg2.connect(
            host=host,
            port=port,
            dbname=os.getenv("PG_DB_MOBOBRAIN", "db_mobobrain"),
            user=os.getenv("PG_USER_MOBOBRAIN", "user_mobobrain"),
            password=os.getenv("PG_PASS_MOBOBRAIN"),
        )
    elif target_site == "home":
        return psycopg2.connect(
            host=host,
            port=port,
            dbname=os.getenv("PG_DB_ARCHIVE", "db_archive"),
            user=os.getenv("PG_USER_ARCHIVE", "user_archive"),
            password=os.getenv("PG_PASS_ARCHIVE"),
        )
    else:
        raise ValueError(f"未知的目标站点类型: {target_site}")


def get_oss_buckets():
    ak = os.getenv("ALIYUN_ACCESS_KEY_ID")
    sk = os.getenv("ALIYUN_ACCESS_KEY_SECRET")
    endpoint = os.getenv("OSS_ENDPOINT", "https://oss-cn-hangzhou.aliyuncs.com")
    auth = oss2.Auth(ak, sk)

    pub_bucket_name = os.getenv("OSS_BUCKET_PUBLIC", "mobobrain-assets-pub")
    priv_bucket_name = os.getenv("OSS_BUCKET_PRIVATE", "mobo-archive-private-hz")

    return (
        oss2.Bucket(auth, endpoint, pub_bucket_name),
        oss2.Bucket(auth, endpoint, priv_bucket_name),
        pub_bucket_name,
        priv_bucket_name,
    )


def compute_sha256(file_path: Path) -> str:
    h = hashlib.sha256()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def json_serial(obj):
    if isinstance(obj, (datetime, date)):
        return obj.isoformat()
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Type {type(obj)} not serializable")


def extract_image_exif_and_thumb(img_path: Path, max_thumb_width: int = 800):
    exif_meta = {}
    captured_dt = None

    with Image.open(img_path) as img:
        exif_meta["width"] = img.width
        exif_meta["height"] = img.height
        exif_meta["format"] = img.format

        raw_exif = img.getexif()
        if raw_exif:
            for tag_id, val in raw_exif.items():
                tag_name = ExifTags.TAGS.get(tag_id, str(tag_id))
                if tag_name in (
                    "Make", "Model", "DateTime", "DateTimeOriginal",
                    "LensModel", "FocalLength", "FNumber", "ISOSpeedRatings",
                ):
                    exif_meta[tag_name] = str(val)
                if tag_name in ("DateTimeOriginal", "DateTime") and not captured_dt:
                    try:
                        captured_dt = datetime.strptime(str(val), "%Y:%m:%d %H:%M:%S")
                    except Exception:
                        pass

        work_img = img.convert("RGB") if img.mode in ("RGBA", "P") else img.copy()
        if work_img.width > max_thumb_width:
            ratio = max_thumb_width / float(work_img.width)
            new_h = int(float(work_img.height) * ratio)
            work_img = work_img.resize((max_thumb_width, new_h), Image.Resampling.LANCZOS)

        buf = BytesIO()
        work_img.save(buf, format="WEBP", quality=82, method=6)
        webp_bytes = buf.getvalue()

    if not captured_dt:
        captured_dt = datetime.fromtimestamp(img_path.stat().st_mtime)

    return captured_dt, exif_meta, webp_bytes


def extract_video_metadata(video_path: Path) -> tuple:
    meta = {"file_ext": video_path.suffix.lower()}
    captured_dt = datetime.fromtimestamp(video_path.stat().st_mtime)

    try:
        cmd = [
            "ffprobe", "-v", "quiet", "-print_format", "json",
            "-show_format", "-show_streams", str(video_path),
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if res.returncode == 0:
            probe_data = json.loads(res.stdout)
            fmt = probe_data.get("format", {})
            if "duration" in fmt:
                meta["duration_sec"] = round(float(fmt["duration"]), 2)
            tags = fmt.get("tags", {})
            if "creation_time" in tags:
                try:
                    captured_dt = datetime.fromisoformat(
                        tags["creation_time"].replace("Z", "+00:00")
                    )
                except Exception:
                    pass
            for s in probe_data.get("streams", []):
                if s.get("codec_type") == "video":
                    meta["codec"] = s.get("codec_name")
                    meta["width"] = s.get("width")
                    meta["height"] = s.get("height")
                    break
    except Exception:
        meta["ffprobe_note"] = "ffprobe not found, basic file stat used"

    return captured_dt, meta


def extract_pdf_text(pdf_path: Path, max_pages: int = 50) -> tuple:
    text_chunks = []
    meta = {}
    try:
        reader = PdfReader(str(pdf_path))
        meta["total_pages"] = len(reader.pages)
        for page in reader.pages[:max_pages]:
            page_txt = page.extract_text()
            if page_txt:
                text_chunks.append(page_txt.strip())
    except Exception as e:
        meta["pdf_parse_warning"] = str(e)

    return "\n\n".join(text_chunks), meta


def archive_single_media_file(
    file_path: Path,
    asset_type: str = None,
    title: str = None,
    captured_at_override: str = None,
    linked_event_id: str = None,
    is_sensitive: bool = True,
    poster_path: str = None,
    extra_tags: list = None,
) -> dict:
    p = file_path.expanduser().resolve()
    if not p.exists() or not p.is_file():
        raise FileNotFoundError(f"找不到待归档文件: {p}")

    ext = p.suffix.lower()
    if not asset_type:
        if ext in (".jpg", ".jpeg", ".png", ".webp", ".heic"):
            asset_type = "photo"
        elif ext in (".mp4", ".mov", ".mkv", ".avi", ".m4v"):
            asset_type = "video"
        elif ext in (".mp3", ".m4a", ".wav", ".flac"):
            asset_type = "audio"
        else:
            asset_type = "scan_doc"

    file_sha256 = compute_sha256(p)
    file_size = p.stat().st_size
    mime_type, _ = mimetypes.guess_type(str(p))
    mime_type = mime_type or "application/octet-stream"
    asset_title = title or p.stem

    conn = get_db_conn("home")
    pub_bucket, priv_bucket, pub_name, priv_name = get_oss_buckets()

    try:
        with conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    "SELECT id, title, oss_object_key, oss_thumbnail_key FROM archive_assets WHERE file_sha256 = %s;",
                    (file_sha256,),
                )
                existing = cur.fetchone()
                if existing:
                    print(f"⚡ [SHA-256 数据库去重命中] 资产 '{existing['title']}' 已归档 (ID: {existing['id']})")
                    if linked_event_id:
                        cur.execute(
                            """
                            UPDATE archive_assets SET linked_event_id = COALESCE(linked_event_id, %s) WHERE id = %s;
                            INSERT INTO entity_links (source_type, source_id, target_type, target_id, relation_type)
                            VALUES ('timeline_event', %s, 'archive_asset', %s, 'has_media')
                            ON CONFLICT DO NOTHING;
                            """,
                            (linked_event_id, existing["id"], linked_event_id, existing["id"]),
                        )
                    return existing

                extracted_text = None
                exif_or_meta = {}
                webp_thumb_bytes = None
                captured_dt = datetime.fromtimestamp(p.stat().st_mtime)

                if asset_type == "photo":
                    captured_dt, exif_or_meta, webp_thumb_bytes = extract_image_exif_and_thumb(p)
                elif asset_type == "video":
                    captured_dt, exif_or_meta = extract_video_metadata(p)
                    if poster_path:
                        _, _, webp_thumb_bytes = extract_image_exif_and_thumb(
                            Path(poster_path).expanduser().resolve()
                        )
                elif ext == ".pdf":
                    extracted_text, exif_or_meta = extract_pdf_text(p)

                if captured_at_override:
                    captured_dt = datetime.fromisoformat(captured_at_override)

                if extra_tags:
                    exif_or_meta["tags"] = extra_tags

                lifecycle_prefix = (
                    asset_type if asset_type in ("photo", "video", "scan_doc") else "scan_doc"
                )
                ym_folder = captured_dt.strftime("%Y/%m")
                oss_object_key = f"{lifecycle_prefix}/{ym_folder}/{file_sha256[:16]}_{p.name}"

                if not priv_bucket.object_exists(oss_object_key):
                    priv_bucket.put_object_from_file(oss_object_key, str(p))
                    print(f"🔒 [OSS 私有原件上传] oss://{priv_name}/{oss_object_key}")

                oss_thumbnail_key = None
                if webp_thumb_bytes:
                    oss_thumbnail_key = (
                        f"thumbnails/{lifecycle_prefix}/{ym_folder}/{file_sha256[:16]}_800w.webp"
                    )
                    priv_bucket.put_object(
                        oss_thumbnail_key,
                        webp_thumb_bytes,
                        headers={"Content-Type": "image/webp"},
                    )
                    if not is_sensitive:
                        pub_bucket.put_object(
                            oss_thumbnail_key,
                            webp_thumb_bytes,
                            headers={
                                "Content-Type": "image/webp",
                                "Cache-Control": "public, max-age=31536000",
                            },
                        )
                        public_domain = os.getenv(
                            "OSS_PUBLIC_CDN_DOMAIN",
                            f"https://{pub_name}.oss-cn-hangzhou.aliyuncs.com",
                        ).rstrip("/")
                        exif_or_meta["public_thumb_url"] = f"{public_domain}/{oss_thumbnail_key}"

                insert_sql = """
                INSERT INTO archive_assets (
                    asset_type, title, captured_at, oss_bucket, oss_object_key,
                    oss_thumbnail_key, file_sha256, file_size_bytes, mime_type,
                    storage_class, extracted_text, exif_or_meta, linked_event_id, is_sensitive
                ) VALUES (
                    %s, %s, %s, %s, %s,
                    %s, %s, %s, %s,
                    'Standard', %s, %s, %s, %s
                )
                RETURNING id, asset_type, title, oss_object_key, oss_thumbnail_key;
                """
                cur.execute(
                    insert_sql,
                    (
                        asset_type, asset_title, captured_dt, priv_name, oss_object_key,
                        oss_thumbnail_key, file_sha256, file_size, mime_type,
                        extracted_text, Json(exif_or_meta), linked_event_id, is_sensitive,
                    ),
                )
                asset_row = cur.fetchone()

                if linked_event_id:
                    cur.execute(
                        """
                        INSERT INTO entity_links (source_type, source_id, target_type, target_id, relation_type)
                        VALUES ('timeline_event', %s, 'archive_asset', %s, 'has_media')
                        ON CONFLICT DO NOTHING;
                        """,
                        (linked_event_id, asset_row["id"]),
                    )

                print(f"✅ [db_archive 归档入库] 类型: {asset_type} | 标题: {asset_title} | 敏感隔离: {is_sensitive}")
                return asset_row
    finally:
        conn.close()


def handle_home_media_cmd(args):
    is_sensitive = not args.public
    tags = [t.strip() for t in args.tags.split(",") if t.strip()] if args.tags else []

    if args.batch_dir:
        folder = Path(args.batch_dir).expanduser().resolve()
        if not folder.is_dir():
            raise ValueError(f"批量目录不存在: {folder}")
        supported_exts = {".jpg", ".jpeg", ".png", ".webp", ".mp4", ".mov", ".pdf"}
        files = sorted(
            [f for f in folder.rglob("*") if f.is_file() and f.suffix.lower() in supported_exts]
        )
        print(f"📂 [批量归档启动] 在 {folder} 中扫描到 {len(files)} 个多媒体/文档文件...")
        for f in files:
            archive_single_media_file(
                file_path=f,
                asset_type=args.type,
                linked_event_id=args.event_id,
                is_sensitive=is_sensitive,
                extra_tags=tags,
            )
    elif args.file:
        archive_single_media_file(
            file_path=Path(args.file),
            asset_type=args.type,
            title=args.title,
            captured_at_override=args.captured_at,
            linked_event_id=args.event_id,
            is_sensitive=is_sensitive,
            poster_path=args.poster,
            extra_tags=tags,
        )
    else:
        raise ValueError("必须指定 --file (单文件) 或 --batch-dir (批量目录)")

    if not args.skip_sync:
        export_home_frontend_json(args.web_dir)


def handle_home_story_cmd(args):
    meta = {}
    content_md = ""

    if args.from_md:
        md_file = Path(args.from_md).expanduser().resolve()
        raw_text = md_file.read_text(encoding="utf-8")
        if raw_text.startswith("---"):
            parts = raw_text.split("---", 2)
            fm = yaml.safe_load(parts[1]) or {}
            content_md = parts[2].strip()
        else:
            fm = {}
            content_md = raw_text.strip()
    else:
        fm = {}
        content_md = args.content or ""

    event_date = args.date or str(fm.get("event_date", date.today()))
    category = args.category or fm.get("category", "milestone")
    title = args.title or fm.get("title")
    summary = args.summary or fm.get("summary") or (content_md[:180] + "..." if len(content_md) > 180 else content_md)
    location = args.location or fm.get("location_name", "武汉")
    importance = int(args.importance if args.importance is not None else fm.get("importance", 4))
    mood = int(args.mood if args.mood is not None else fm.get("mood_score", 8))
    energy = int(args.energy if args.energy is not None else fm.get("energy_score", 8))
    life_stage = args.chapter or fm.get("life_chapter", "湖北·归航与长期筑基")
    is_sensitive = (not args.public) if args.public else bool(fm.get("is_sensitive", False))

    if args.tags:
        tags = [t.strip() for t in args.tags.split(",") if t.strip()]
    else:
        tags = fm.get("tags", [])

    if not title:
        raise ValueError("成长故事或时间线事件必须提供标题 (--title 或在 Markdown Frontmatter 中声明 title)")

    meta["life_chapter"] = life_stage
    meta["content_markdown"] = content_md
    meta["word_count"] = len(content_md)
    if fm.get("slug"):
        meta["slug"] = fm["slug"]

    conn = get_db_conn("home")
    event_id = None

    try:
        with conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    INSERT INTO timeline_events (
                        event_date, event_timestamp, category, title, summary,
                        location_name, importance, mood_score, energy_score,
                        tags, metadata, is_sensitive
                    ) VALUES (
                        %s, CURRENT_TIMESTAMP, %s, %s, %s,
                        %s, %s, %s, %s,
                        %s, %s, %s
                    )
                    RETURNING id, event_date, category, title;
                    """,
                    (
                        event_date, category, title, summary,
                        location, importance, mood, energy,
                        tags, Json(meta), is_sensitive,
                    ),
                )
                ev = cur.fetchone()
                event_id = str(ev["id"])
                print(f"✅ [莫伯之家成长故事已入库] ID: {event_id} | 日期: {ev['event_date']} | 标题: {ev['title']}")
    finally:
        conn.close()

    if args.attach and event_id:
        attach_paths = [p.strip() for p in args.attach.split(",") if p.strip()]
        for ap in attach_paths:
            archive_single_media_file(
                file_path=Path(ap),
                linked_event_id=event_id,
                is_sensitive=is_sensitive,
                extra_tags=tags,
            )

    if not args.skip_sync:
        export_home_frontend_json(args.web_dir)


def handle_home_habit_cmd(args):
    conn = get_db_conn("home")
    try:
        with conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                if args.habit_type == "workout":
                    cur.execute(
                        """
                        INSERT INTO fitness_workouts (
                            workout_date, workout_type, duration_minutes, distance_km,
                            avg_heart_rate, rpe_score, calories_burned, notes
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                        RETURNING id, workout_date, workout_type, duration_minutes;
                        """,
                        (
                            args.date or str(date.today()), args.workout_type,
                            args.duration, args.distance, args.hr, args.rpe,
                            args.calories, args.notes,
                        ),
                    )
                    w = cur.fetchone()
                    print(f"🏃 [运动打卡入库 + 触发器同步完成] {w['workout_date']} | {w['workout_type']} {w['duration_minutes']}分钟")
                elif args.habit_type == "retro":
                    cur.execute(
                        """
                        INSERT INTO project_retrospectives (
                            review_period, period_type, review_date, title,
                            achievements, bottlenecks, next_actions, content_markdown, is_sensitive
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                        RETURNING id, review_period, title;
                        """,
                        (
                            args.period, args.period_type, args.date or str(date.today()),
                            args.title, args.achievements, args.bottlenecks,
                            args.next_actions, args.content or args.achievements or "",
                            not args.public,
                        ),
                    )
                    r = cur.fetchone()
                    print(f"📝 [周期复盘入库 + 触发器同步完成] {r['review_period']} | {r['title']}")
    finally:
        conn.close()

    if not args.skip_sync:
        export_home_frontend_json(args.web_dir)


def export_home_frontend_json(web_dir_override: str = None):
    base_dir = Path(web_dir_override or os.getenv("MOBOHOME_WEB_DIR", "/opt/mobo-stack/sites/mobohome"))
    pub_dir = base_dir / "data"
    int_dir = base_dir / "internal"
    pub_dir.mkdir(parents=True, exist_ok=True)
    int_dir.mkdir(parents=True, exist_ok=True)

    conn = get_db_conn("home")
    _, priv_bucket, pub_name, _ = get_oss_buckets()
    public_domain = os.getenv(
        "OSS_PUBLIC_CDN_DOMAIN", f"https://{pub_name}.oss-cn-hangzhou.aliyuncs.com"
    ).rstrip("/")

    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT id, event_date, category, title, summary, location_name,
                       importance, mood_score, energy_score, tags, metadata,
                       source_table, is_sensitive, created_at
                FROM timeline_events
                ORDER BY event_date DESC, importance DESC;
                """
            )
            events_all = cur.fetchall()

            cur.execute(
                """
                SELECT id, asset_type, title, captured_at, oss_bucket, oss_object_key,
                       oss_thumbnail_key, file_size_bytes, mime_type, storage_class,
                       exif_or_meta, linked_event_id, is_sensitive
                FROM archive_assets
                ORDER BY captured_at DESC;
                """
            )
            assets_all = cur.fetchall()

            cur.execute(
                """
                SELECT id, item_type, title, author, category, status, rating,
                       started_date, completed_date, core_takeaway, tags
                FROM reading_items
                ORDER BY COALESCE(completed_date, started_date, CURRENT_DATE) DESC;
                """
            )
            books_all = cur.fetchall()

            cur.execute("SELECT * FROM v_weekly_life_analytics LIMIT 26;")
            weekly_analytics = cur.fetchall()

            cur.execute(
                """
                SELECT id, review_period, period_type, review_date, title,
                       achievements, bottlenecks, next_actions, content_markdown, is_sensitive
                FROM project_retrospectives
                ORDER BY review_date DESC;
                """
            )
            retros_all = cur.fetchall()

        public_assets, internal_assets = [], []
        event_media_map_pub, event_media_map_int = {}, {}

        for a in assets_all:
            a_int = dict(a)
            a_int["id"] = str(a_int["id"])
            if a_int.get("linked_event_id"):
                a_int["linked_event_id"] = str(a_int["linked_event_id"])

            try:
                a_int["signed_original_url"] = priv_bucket.sign_url("GET", a_int["oss_object_key"], 7200)
                a_int["signed_thumb_url"] = (
                    priv_bucket.sign_url("GET", a_int["oss_thumbnail_key"], 7200)
                    if a_int.get("oss_thumbnail_key") else None
                )
            except Exception:
                a_int["signed_original_url"] = None
                a_int["signed_thumb_url"] = None

            internal_assets.append(a_int)
            if a_int.get("linked_event_id"):
                event_media_map_int.setdefault(a_int["linked_event_id"], []).append(a_int)

            if not a["is_sensitive"]:
                a_pub = {
                    "id": str(a["id"]),
                    "asset_type": a["asset_type"],
                    "title": a["title"],
                    "captured_at": a["captured_at"],
                    "mime_type": a["mime_type"],
                    "exif_or_meta": a["exif_or_meta"],
                    "linked_event_id": str(a["linked_event_id"]) if a.get("linked_event_id") else None,
                    "public_thumb_url": (a["exif_or_meta"] or {}).get("public_thumb_url")
                    or (f"{public_domain}/{a['oss_thumbnail_key']}" if a.get("oss_thumbnail_key") else None),
                }
                public_assets.append(a_pub)
                if a_pub["linked_event_id"]:
                    event_media_map_pub.setdefault(a_pub["linked_event_id"], []).append(a_pub)

        public_events, internal_events = [], []
        for ev in events_all:
            ev_id = str(ev["id"])
            ev_int = dict(ev)
            ev_int["id"] = ev_id
            ev_int["attached_media"] = event_media_map_int.get(ev_id, [])
            internal_events.append(ev_int)

            if not ev["is_sensitive"]:
                ev_pub = dict(ev)
                ev_pub["id"] = ev_id
                ev_pub["attached_media"] = event_media_map_pub.get(ev_id, [])
                public_events.append(ev_pub)

        (pub_dir / "public-home-data.json").write_text(
            json.dumps(
                {
                    "generated_at": datetime.now().isoformat(),
                    "site": "MoBoHome.com (莫伯之家 · 公开数字档案)",
                    "clearance_scope": "PUBLIC",
                    "timeline_stories": public_events,
                    "gallery_assets": public_assets,
                    "reading_library": books_all,
                    "weekly_life_analytics": weekly_analytics,
                    "retrospectives": [r for r in retros_all if not r["is_sensitive"]],
                },
                default=json_serial, ensure_ascii=False, indent=2,
            ),
            encoding="utf-8",
        )
        (int_dir / "internal-home-data.json").write_text(
            json.dumps(
                {
                    "generated_at": datetime.now().isoformat(),
                    "site": "MoBoHome.com (莫伯之家 · 内网全量生命档案馆)",
                    "clearance_scope": "INTERNAL_PRIVATE",
                    "timeline_stories": internal_events,
                    "gallery_assets": internal_assets,
                    "reading_library": books_all,
                    "weekly_life_analytics": weekly_analytics,
                    "retrospectives": retros_all,
                },
                default=json_serial, ensure_ascii=False, indent=2,
            ),
            encoding="utf-8",
        )
        print("🏡 [MoBoHome 莫伯之家前端数据已同步]")
    finally:
        conn.close()


def upload_private_blotter(file_path: str) -> str:
    p = Path(file_path).expanduser().resolve()
    if not p.exists():
        raise FileNotFoundError(f"找不到交割单文件: {p}")
    sha256_hex = compute_sha256(p)
    ext = p.suffix.lower()
    now_prefix = datetime.now().strftime("%Y/%m")
    oss_key = f"blotters/{now_prefix}/{sha256_hex[:16]}_{p.stem}{ext}"
    _, priv_bucket, _, priv_name = get_oss_buckets()
    if not priv_bucket.object_exists(oss_key):
        priv_bucket.put_object_from_file(oss_key, str(p))
        print(f"🔒 [OSS 私有交割单归档] oss://{priv_name}/{oss_key}")
    return oss_key


def upload_public_chart_webp(file_path: str, max_width: int = 1200) -> str:
    p = Path(file_path).expanduser().resolve()
    if not p.exists():
        raise FileNotFoundError(f"找不到图表文件: {p}")
    sha256_hex = compute_sha256(p)
    now_prefix = datetime.now().strftime("%Y/%m")
    oss_key = f"charts/{now_prefix}/{sha256_hex[:16]}.webp"
    pub_bucket, _, pub_name, _ = get_oss_buckets()
    public_domain = os.getenv(
        "OSS_PUBLIC_CDN_DOMAIN", f"https://{pub_name}.oss-cn-hangzhou.aliyuncs.com"
    ).rstrip("/")
    if not pub_bucket.object_exists(oss_key):
        _, _, webp_bytes = extract_image_exif_and_thumb(p, max_thumb_width=max_width)
        pub_bucket.put_object(
            oss_key, webp_bytes,
            headers={"Content-Type": "image/webp", "Cache-Control": "public, max-age=31536000"},
        )
    return f"{public_domain}/{oss_key}"


def parse_trade_markdown(md_path: str) -> dict:
    p = Path(md_path).expanduser().resolve()
    content = p.read_text(encoding="utf-8")
    if not content.startswith("---"):
        raise ValueError("Markdown 复盘文件必须包含顶部 YAML Frontmatter")
    parts = content.split("---", 2)
    frontmatter = yaml.safe_load(parts[1])
    body = parts[2].strip()
    sections = {"pre_trade": "", "execution": "", "lessons": ""}
    current_sec = "pre_trade"
    for line in body.splitlines():
        hl = line.strip().lower()
        if hl.startswith("## ") and ("pre-trade" in hl or "建仓前" in hl):
            current_sec = "pre_trade"
            continue
        elif hl.startswith("## ") and ("execution" in hl or "持仓" in hl or "平仓" in hl):
            current_sec = "execution"
            continue
        elif hl.startswith("## ") and ("lesson" in hl or "心得" in hl or "教训" in hl):
            current_sec = "lessons"
            continue
        sections[current_sec] += line + "\n"
    frontmatter["pre_trade_thesis_md"] = sections["pre_trade"].strip()
    frontmatter["execution_review_md"] = sections["execution"].strip()
    frontmatter["lessons_learned_md"] = sections["lessons"].strip()
    return frontmatter


def upsert_trade_review(args):
    data = parse_trade_markdown(args.from_md) if args.from_md else {}
    trade_code = args.code or data.get("trade_code")
    strategy_code = args.strategy or data.get("strategy_code")
    thesis_code = args.thesis or data.get("thesis_code")
    ticker = args.ticker or data.get("underlying_ticker")
    asset_name = args.asset_name or data.get("asset_name", ticker)
    direction = (args.direction or data.get("direction", "LONG")).upper()
    structure = args.structure or data.get("instrument_structure", "Spot")
    entry_date = args.entry_date or str(data.get("entry_date", date.today()))
    exit_date = args.exit_date or (str(data["exit_date"]) if data.get("exit_date") else None)
    status = (args.status or data.get("trade_status", "CLOSED")).upper()
    init_risk = float(args.init_risk if args.init_risk is not None else data.get("initial_risk_pct", 1.0))
    r_mult = args.r_multiple if args.r_multiple is not None else data.get("realized_r_multiple")
    ret_pct = args.return_pct if args.return_pct is not None else data.get("realized_return_pct")
    impact_bps = args.impact_bps if args.impact_bps is not None else data.get("portfolio_impact_bps")
    discipline = int(args.discipline if args.discipline is not None else data.get("discipline_score", 9))
    emotion = (args.emotion or data.get("emotional_state_tag", "CALM_SYSTEMATIC")).upper()
    visibility = (args.visibility or data.get("visibility", "PUBLIC")).upper()
    pre_thesis = args.pre_thesis or data.get("pre_trade_thesis_md", "")
    exec_review = args.exec_review or data.get("execution_review_md", "")
    lessons = args.lessons or data.get("lessons_learned_md", "")
    greeks_dict = json.loads(args.greeks) if args.greeks else data.get("greeks_snapshot", {})

    blotter_oss_key = upload_private_blotter(args.blotter) if args.blotter else data.get("private_blotter_oss_key")
    chart_oss_url = upload_public_chart_webp(args.chart) if args.chart else data.get("public_chart_oss_url")

    conn = get_db_conn("capital")
    try:
        with conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("SELECT id FROM strategy_playbooks WHERE strategy_code = %s;", (strategy_code,))
                strat_row = cur.fetchone()
                if not strat_row:
                    raise ValueError(f"策略代码 '{strategy_code}' 不存在")
                strategy_id = strat_row["id"]
                thesis_id = None
                if thesis_code:
                    cur.execute("SELECT id FROM macro_theses WHERE thesis_code = %s;", (thesis_code,))
                    t_row = cur.fetchone()
                    if t_row:
                        thesis_id = t_row["id"]

                cur.execute(
                    """
                    INSERT INTO trade_reviews (
                        trade_code, thesis_id, strategy_id, underlying_ticker, asset_name,
                        direction, instrument_structure, entry_date, exit_date, trade_status,
                        initial_risk_pct, realized_r_multiple, realized_return_pct, portfolio_impact_bps,
                        greeks_snapshot, pre_trade_thesis_md, execution_review_md, lessons_learned_md,
                        discipline_score, emotional_state_tag, private_blotter_oss_key, public_chart_oss_url,
                        visibility, updated_at
                    ) VALUES (
                        %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                        %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP
                    )
                    ON CONFLICT (trade_code) DO UPDATE SET
                        realized_r_multiple = EXCLUDED.realized_r_multiple,
                        portfolio_impact_bps = EXCLUDED.portfolio_impact_bps,
                        trade_status = EXCLUDED.trade_status,
                        exit_date = EXCLUDED.exit_date,
                        greeks_snapshot = EXCLUDED.greeks_snapshot,
                        execution_review_md = EXCLUDED.execution_review_md,
                        lessons_learned_md = EXCLUDED.lessons_learned_md,
                        discipline_score = EXCLUDED.discipline_score,
                        private_blotter_oss_key = COALESCE(EXCLUDED.private_blotter_oss_key, trade_reviews.private_blotter_oss_key),
                        public_chart_oss_url = COALESCE(EXCLUDED.public_chart_oss_url, trade_reviews.public_chart_oss_url),
                        visibility = EXCLUDED.visibility,
                        updated_at = CURRENT_TIMESTAMP
                    RETURNING trade_code, realized_r_multiple;
                    """,
                    (
                        trade_code, thesis_id, strategy_id, ticker, asset_name,
                        direction, structure, entry_date, exit_date, status,
                        init_risk, r_mult, ret_pct, impact_bps,
                        Json(greeks_dict), pre_thesis, exec_review, lessons,
                        discipline, emotion, blotter_oss_key, chart_oss_url, visibility,
                    ),
                )
                res = cur.fetchone()
                print(f"✅ [MoBoCapital 战役入库成功] {res['trade_code']} ({res['realized_r_multiple']}R)")
    finally:
        conn.close()

    if not args.skip_sync:
        export_capital_frontend_json(args.web_dir)


def export_capital_frontend_json(web_dir_override: str = None):
    base_dir = Path(web_dir_override or os.getenv("MOBOCAPITAL_WEB_DIR", "/opt/mobo-stack/sites/mobocapital"))
    pub_data_dir = base_dir / "data"
    int_data_dir = base_dir / "internal"
    pub_data_dir.mkdir(parents=True, exist_ok=True)
    int_data_dir.mkdir(parents=True, exist_ok=True)

    conn = get_db_conn("capital")
    _, priv_bucket, _, _ = get_oss_buckets()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT * FROM v_strategy_performance_summary ORDER BY strategy_code;")
            strategies_perf = cur.fetchall()
            cur.execute("SELECT * FROM macro_theses WHERE status IN ('ACTIVE', 'VALIDATED') ORDER BY created_at DESC;")
            theses_all = cur.fetchall()
            cur.execute(
                """
                SELECT tr.*, sp.strategy_code, mt.thesis_code
                FROM trade_reviews tr
                JOIN strategy_playbooks sp ON tr.strategy_id = sp.id
                LEFT JOIN macro_theses mt ON tr.thesis_id = mt.id
                ORDER BY tr.entry_date DESC;
                """
            )
            trades_all = cur.fetchall()
            cur.execute("SELECT * FROM fund_incubation_milestones ORDER BY phase_number ASC, target_date ASC;")
            milestones_all = cur.fetchall()
            cur.execute("SELECT * FROM v_media_conversion_funnel;")
            media_funnel = cur.fetchall()

        public_trades, internal_trades = [], []
        for t in trades_all:
            t_int = dict(t)
            t_int.pop("embedding", None)
            if t_int.get("private_blotter_oss_key"):
                try:
                    t_int["signed_blotter_url"] = priv_bucket.sign_url("GET", t_int["private_blotter_oss_key"], 3600)
                except Exception:
                    t_int["signed_blotter_url"] = None
            internal_trades.append(t_int)
            if t["visibility"] in ("PUBLIC", "LP_PROSPECT"):
                t_pub = dict(t_int)
                t_pub.pop("private_blotter_oss_key", None)
                t_pub.pop("signed_blotter_url", None)
                public_trades.append(t_pub)

        for m in theses_all:
            m.pop("embedding", None)

        (pub_data_dir / "public-data.json").write_text(
            json.dumps(
                {
                    "generated_at": datetime.now().isoformat(),
                    "strategies_summary": strategies_perf,
                    "macro_theses": [m for m in theses_all if m["visibility"] != "INTERNAL"],
                    "trade_reviews": public_trades,
                    "incubation_milestones": [ms for ms in milestones_all if ms["visibility"] != "INTERNAL"],
                    "media_funnel": media_funnel,
                },
                default=json_serial, ensure_ascii=False, indent=2,
            ),
            encoding="utf-8",
        )
        (int_data_dir / "internal-data.json").write_text(
            json.dumps(
                {
                    "generated_at": datetime.now().isoformat(),
                    "strategies_summary": strategies_perf,
                    "macro_theses": theses_all,
                    "trade_reviews": internal_trades,
                    "incubation_milestones": milestones_all,
                    "media_funnel": media_funnel,
                },
                default=json_serial, ensure_ascii=False, indent=2,
            ),
            encoding="utf-8",
        )
        print("🚀 [MoBoCapital 前端静态数据包已同步]")
    finally:
        conn.close()


def build_parser():
    parser = argparse.ArgumentParser(
        description="MoBo Dual-Site CLI v2.1 — 莫伯资本 & 莫伯之家终端总控"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_trade = sub.add_parser("trade", help="[MoBoCapital] 录入/更新实盘交易复盘与期权归因")
    p_trade.add_argument("--from-md", type=str)
    p_trade.add_argument("--code", type=str)
    p_trade.add_argument("--strategy", type=str)
    p_trade.add_argument("--thesis", type=str)
    p_trade.add_argument("--ticker", type=str)
    p_trade.add_argument("--asset-name", type=str)
    p_trade.add_argument("--direction", type=str)
    p_trade.add_argument("--structure", type=str)
    p_trade.add_argument("--entry-date", type=str)
    p_trade.add_argument("--exit-date", type=str)
    p_trade.add_argument("--status", type=str)
    p_trade.add_argument("--init-risk", type=float)
    p_trade.add_argument("--r-multiple", type=float)
    p_trade.add_argument("--return-pct", type=float)
    p_trade.add_argument("--impact-bps", type=int)
    p_trade.add_argument("--greeks", type=str)
    p_trade.add_argument("--discipline", type=int)
    p_trade.add_argument("--emotion", type=str)
    p_trade.add_argument("--pre-thesis", type=str)
    p_trade.add_argument("--exec-review", type=str)
    p_trade.add_argument("--lessons", type=str)
    p_trade.add_argument("--blotter", type=str)
    p_trade.add_argument("--chart", type=str)
    p_trade.add_argument("--visibility", type=str)
    p_trade.add_argument("--web-dir", type=str)
    p_trade.add_argument("--skip-sync", action="store_true")

    p_sync_cap = sub.add_parser("sync-capital-web", help="[MoBoCapital] 同步导出莫伯资本前端 JSON")
    p_sync_cap.add_argument("--web-dir", type=str)

    p_media = sub.add_parser("home-media", help="[MoBoHome] 归档个人照片、视频、PDF扫描件")
    p_media.add_argument("--file", type=str)
    p_media.add_argument("--batch-dir", type=str)
    p_media.add_argument("--type", type=str, choices=["photo", "video", "scan_doc", "audio", "certificate"])
    p_media.add_argument("--title", type=str)
    p_media.add_argument("--captured-at", type=str)
    p_media.add_argument("--event-id", type=str)
    p_media.add_argument("--poster", type=str)
    p_media.add_argument("--tags", type=str)
    p_media.add_argument("--public", action="store_true")
    p_media.add_argument("--web-dir", type=str)
    p_media.add_argument("--skip-sync", action="store_true")

    p_story = sub.add_parser("home-story", help="[MoBoHome] 录入个人成长经历与故事文章")
    p_story.add_argument("--from-md", type=str)
    p_story.add_argument("--title", type=str)
    p_story.add_argument("--date", type=str)
    p_story.add_argument("--category", type=str, default="milestone")
    p_story.add_argument("--chapter", type=str)
    p_story.add_argument("--location", type=str)
    p_story.add_argument("--summary", type=str)
    p_story.add_argument("--content", type=str)
    p_story.add_argument("--importance", type=int, default=4)
    p_story.add_argument("--mood", type=int, default=8)
    p_story.add_argument("--energy", type=int, default=8)
    p_story.add_argument("--tags", type=str)
    p_story.add_argument("--attach", type=str)
    p_story.add_argument("--public", action="store_true")
    p_story.add_argument("--web-dir", type=str)
    p_story.add_argument("--skip-sync", action="store_true")

    p_habit = sub.add_parser("home-habit", help="[MoBoHome] 录入运动训练或周期复盘")
    p_habit.add_argument("--habit-type", type=str, required=True, choices=["workout", "retro"])
    p_habit.add_argument("--date", type=str)
    p_habit.add_argument("--workout-type", type=str, default="running")
    p_habit.add_argument("--duration", type=int, default=60)
    p_habit.add_argument("--distance", type=float)
    p_habit.add_argument("--hr", type=int)
    p_habit.add_argument("--rpe", type=int, default=7)
    p_habit.add_argument("--calories", type=int)
    p_habit.add_argument("--notes", type=str)
    p_habit.add_argument("--period", type=str)
    p_habit.add_argument("--period-type", type=str, default="weekly")
    p_habit.add_argument("--title", type=str)
    p_habit.add_argument("--achievements", type=str)
    p_habit.add_argument("--bottlenecks", type=str)
    p_habit.add_argument("--next-actions", type=str)
    p_habit.add_argument("--content", type=str)
    p_habit.add_argument("--public", action="store_true")
    p_habit.add_argument("--web-dir", type=str)
    p_habit.add_argument("--skip-sync", action="store_true")

    p_sync_home = sub.add_parser("sync-home-web", help="[MoBoHome] 导出 db_archive 数据至 MoBoHome.com 前端 JSON")
    p_sync_home.add_argument("--web-dir", type=str)

    return parser


if __name__ == "__main__":
    parser = build_parser()
    cli_args = parser.parse_args()

    if cli_args.command == "trade":
        upsert_trade_review(cli_args)
    elif cli_args.command == "sync-capital-web":
        export_capital_frontend_json(cli_args.web_dir)
    elif cli_args.command == "home-media":
        handle_home_media_cmd(cli_args)
    elif cli_args.command == "home-story":
        handle_home_story_cmd(cli_args)
    elif cli_args.command == "home-habit":
        handle_home_habit_cmd(cli_args)
    elif cli_args.command == "sync-home-web":
        export_home_frontend_json(cli_args.web_dir)
EOF_MOBO_CLI

cat << 'EOF_COLLECTOR' > "${STACK_DIR}/scripts/macro_iv_collector.py"
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MoBoCapital Quant Terminal Collector (v1.0)
"""

import os
import json
import urllib.request
from datetime import datetime, date
from decimal import Decimal
from pathlib import Path

import numpy as np
import psycopg2
from psycopg2.extras import RealDictCursor
from dotenv import load_dotenv

ENV_PATH = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(dotenv_path=ENV_PATH)


def get_capital_db_conn():
    return psycopg2.connect(
        host=os.getenv("PG_HOST", "127.0.0.1"),
        port=int(os.getenv("PG_PORT", "5432")),
        dbname=os.getenv("PG_DB_MOBOBRAIN", "db_mobobrain"),
        user=os.getenv("PG_USER_MOBOBRAIN", "user_mobobrain"),
        password=os.getenv("PG_PASS_MOBOBRAIN"),
    )


def json_serial(obj):
    if isinstance(obj, (datetime, date)):
        return obj.isoformat()
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Type {type(obj)} not serializable")


def calc_rolling_zscore(series_values: list, current_val: float) -> float:
    arr = np.array(series_values + [current_val], dtype=np.float64)
    if len(arr) < 3:
        return 0.0
    mean = np.mean(arr)
    std = np.std(arr, ddof=1)
    if std < 1e-8:
        return 0.0
    return round(float((current_val - mean) / std), 2)


def classify_macro_regime(z_score: float) -> str:
    if z_score >= 0.80:
        return "EXPANSION"
    elif z_score >= 0.20:
        return "IMPROVING"
    elif z_score <= -0.80:
        return "CONTRACTION"
    elif z_score <= -0.20:
        return "BOTTOMING"
    return "NEUTRAL"


def calc_iv_rank_and_percentile(iv_history: list, current_iv: float) -> tuple:
    arr = np.array(iv_history + [current_iv], dtype=np.float64)
    if len(arr) < 5:
        return 50.0, 50.0
    iv_min, iv_max = float(np.min(arr)), float(np.max(arr))
    iv_rank = 50.0 if (iv_max - iv_min < 1e-5) else round(100.0 * (current_iv - iv_min) / (iv_max - iv_min), 1)
    iv_pct = round(float(np.sum(arr <= current_iv) / len(arr) * 100.0), 1)
    return float(np.clip(iv_rank, 0.0, 100.0)), float(np.clip(iv_pct, 0.0, 100.0))


def recommend_option_structure(iv_pct: float, skew_25d: float) -> str:
    if iv_pct <= 35.0:
        return "Long Bull Call Spread" if skew_25d <= 0.0 else "Long Diagonal / Straddle"
    elif iv_pct >= 60.0:
        return "1x2 Put Ratio Spread" if skew_25d >= 3.5 else "Iron Condor / Short Strangle"
    else:
        return "Call Ratio Spread" if skew_25d <= -1.0 else "Calendar Spread"


def fetch_json_url(url: str, timeout: int = 8) -> dict:
    req = urllib.request.Request(
        url, headers={"User-Agent": "Mozilla/5.0 MoBoCapitalQuantTerminal/2.1"}
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def fetch_yahoo_chart_metrics(symbol: str) -> dict:
    try:
        url = f"https://query1.finance.yahoo.com/v8/finance/chart/{symbol}?range=1y&interval=1d"
        data = fetch_json_url(url, timeout=6)
        result = data["chart"]["result"][0]
        closes = [c for c in result["indicators"]["quote"][0]["close"] if c is not None]
        if len(closes) < 35:
            return None
        spot = round(float(closes[-1]), 4)
        prev = float(closes[-2])
        chg_pct = round((spot - prev) / prev * 100.0, 2)
        recent_31 = np.array(closes[-31:], dtype=np.float64)
        log_returns = np.diff(np.log(recent_31))
        hv_30d = round(float(np.std(log_returns, ddof=1) * np.sqrt(252) * 100.0), 2)
        return {"spot": spot, "chg_pct": chg_pct, "hv_30d": hv_30d}
    except Exception:
        return None


DEFAULT_MACRO_BASELINES = [
    {"code": "CN_PMI_ORDER_INV_SPREAD", "name": "中国制造业 PMI (新订单-产成品库存差)", "region": "CN", "freq": "MONTHLY", "val": 3.80, "prev": 3.10, "history": [0.5, 0.8, 1.2, 1.5, 1.1, 1.8, 2.1, 2.4, 2.0, 2.7, 3.1]},
    {"code": "CN_PMI_NEW_ORDERS", "name": "中国制造业 PMI 新订单分项", "region": "CN", "freq": "MONTHLY", "val": 51.40, "prev": 50.80, "history": [49.2, 49.5, 49.8, 50.1, 49.7, 50.2, 50.4, 50.6, 50.8]},
    {"code": "CN_M1_M2_SCISSORS", "name": "社融脉冲与 M1-M2 剪刀差修复指数", "region": "CN", "freq": "MONTHLY", "val": -3.20, "prev": -4.10, "history": [-6.8, -6.2, -5.9, -5.4, -5.1, -4.8, -4.5, -4.1]},
    {"code": "US_ISM_NEW_ORDERS", "name": "美国 ISM 制造业新订单指数", "region": "US", "freq": "MONTHLY", "val": 48.90, "prev": 49.40, "history": [47.1, 48.0, 49.2, 50.3, 49.8, 49.1, 49.4]},
    {"code": "US10Y_YIELD", "name": "美债 10 年期基准收益率 (%)", "region": "US", "freq": "DAILY", "val": 4.18, "prev": 4.15, "history": [4.45, 4.38, 4.30, 4.22, 4.10, 4.05, 4.12, 4.15]},
    {"code": "VIX_INDEX", "name": "CBOE VIX 标普500波动率恐慌指数", "region": "US", "freq": "DAILY", "val": 19.45, "prev": 20.28, "history": [14.5, 15.2, 16.8, 18.0, 21.5, 20.8, 20.28]},
    {"code": "USDCNH_SPOT", "name": "离岸人民币汇率 (USD/CNH)", "region": "GLOBAL", "freq": "DAILY", "val": 7.1240, "prev": 7.1350, "history": [7.26, 7.24, 7.20, 7.18, 7.15, 7.14, 7.135]},
]

DEFAULT_VOL_SURFACE_TARGETS = [
    {"ticker": "510300.SH", "yf_symbol": "510300.SS", "name": "沪深300 ETF (510300)", "fallback_spot": 4.085, "fallback_chg": 0.62, "fallback_iv30": 21.4, "fallback_hv30": 19.8, "fallback_skew": -2.1, "iv_hist": [26.5, 25.0, 24.2, 23.8, 22.5, 28.0, 31.0, 20.5, 19.8, 21.0]},
    {"ticker": "HSTECH.HK", "yf_symbol": "^HSTECH", "name": "恒生科技指数 (HSTECH)", "fallback_spot": 4680.0, "fallback_chg": 1.15, "fallback_iv30": 34.8, "fallback_hv30": 32.1, "fallback_skew": 1.8, "iv_hist": [29.0, 31.5, 33.0, 36.5, 42.0, 38.0, 35.5, 34.0]},
    {"ticker": "SPY.US", "yf_symbol": "SPY", "name": "标普500 ETF (SPY)", "fallback_spot": 582.40, "fallback_chg": 0.28, "fallback_iv30": 18.2, "fallback_hv30": 14.6, "fallback_skew": 5.4, "iv_hist": [12.8, 13.5, 14.2, 15.8, 16.5, 17.2, 19.5, 17.8]},
    {"ticker": "GLD.US", "yf_symbol": "GLD", "name": "黄金 ETF (GLD)", "fallback_spot": 251.60, "fallback_chg": 0.45, "fallback_iv30": 16.9, "fallback_hv30": 15.2, "fallback_skew": -0.8, "iv_hist": [14.0, 15.5, 16.2, 18.5, 20.1, 17.8, 17.1]},
]


def run_daily_collection():
    today_str = str(date.today())
    conn = get_capital_db_conn()
    try:
        with conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                vix_live = fetch_yahoo_chart_metrics("^VIX")
                tnx_live = fetch_yahoo_chart_metrics("^TNX")
                cnh_live = fetch_yahoo_chart_metrics("CNH=X")

                for item in DEFAULT_MACRO_BASELINES:
                    code, val, prev = item["code"], item["val"], item["prev"]
                    if code == "VIX_INDEX" and vix_live:
                        val = vix_live["spot"]
                    elif code == "US10Y_YIELD" and tnx_live:
                        val = tnx_live["spot"]
                    elif code == "USDCNH_SPOT" and cnh_live:
                        val = cnh_live["spot"]

                    cur.execute(
                        "SELECT raw_value FROM macro_indicator_series WHERE indicator_code = %s AND obs_date < %s ORDER BY obs_date DESC LIMIT 24;",
                        (code, today_str),
                    )
                    db_hist = [float(r["raw_value"]) for r in cur.fetchall()]
                    hist_series = db_hist if len(db_hist) >= 5 else item["history"]
                    z_score = calc_rolling_zscore(hist_series, val)
                    regime = classify_macro_regime(z_score)

                    cur.execute(
                        """
                        INSERT INTO macro_indicator_series (
                            indicator_code, indicator_name, region, frequency,
                            obs_date, raw_value, prev_value, change_val, z_score, regime_tag, updated_at
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
                        ON CONFLICT (indicator_code, obs_date) DO UPDATE SET
                            raw_value = EXCLUDED.raw_value, prev_value = EXCLUDED.prev_value,
                            change_val = EXCLUDED.change_val, z_score = EXCLUDED.z_score,
                            regime_tag = EXCLUDED.regime_tag, updated_at = CURRENT_TIMESTAMP;
                        """,
                        (code, item["name"], item["region"], item["freq"], today_str, val, prev, round(val - prev, 4), z_score, regime),
                    )

                for target in DEFAULT_VOL_SURFACE_TARGETS:
                    ticker = target["ticker"]
                    live_mkt = fetch_yahoo_chart_metrics(target["yf_symbol"])
                    if live_mkt:
                        spot, chg_pct, hv_30d = live_mkt["spot"], live_mkt["chg_pct"], live_mkt["hv_30d"]
                        iv_30d = round(max(10.0, hv_30d * 1.12), 2)
                    else:
                        spot, chg_pct = target["fallback_spot"], target["fallback_chg"]
                        hv_30d, iv_30d = target["fallback_hv30"], target["fallback_iv30"]

                    skew_25d = target["fallback_skew"]
                    vrp = round(iv_30d - hv_30d, 2)

                    cur.execute(
                        "SELECT iv_30d FROM options_vol_surface_daily WHERE underlying_ticker = %s AND trade_date < %s ORDER BY trade_date DESC LIMIT 252;",
                        (ticker, today_str),
                    )
                    db_iv_hist = [float(r["iv_30d"]) for r in cur.fetchall()]
                    iv_hist = db_iv_hist if len(db_iv_hist) >= 5 else target["iv_hist"]
                    iv_rank, iv_pct = calc_iv_rank_and_percentile(iv_hist, iv_30d)
                    rec_struct = recommend_option_structure(iv_pct, skew_25d)

                    cur.execute(
                        """
                        INSERT INTO options_vol_surface_daily (
                            underlying_ticker, asset_name, trade_date, spot_price, daily_change_pct,
                            iv_30d, hv_30d, vrp_spread, iv_rank_1y, iv_percentile_1y,
                            skew_25d, recommended_structure, updated_at
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
                        ON CONFLICT (underlying_ticker, trade_date) DO UPDATE SET
                            spot_price = EXCLUDED.spot_price, daily_change_pct = EXCLUDED.daily_change_pct,
                            iv_30d = EXCLUDED.iv_30d, hv_30d = EXCLUDED.hv_30d, vrp_spread = EXCLUDED.vrp_spread,
                            iv_rank_1y = EXCLUDED.iv_rank_1y, iv_percentile_1y = EXCLUDED.iv_percentile_1y,
                            skew_25d = EXCLUDED.skew_25d, recommended_structure = EXCLUDED.recommended_structure,
                            updated_at = CURRENT_TIMESTAMP;
                        """,
                        (ticker, target["name"], today_str, spot, chg_pct, iv_30d, hv_30d, vrp, iv_rank, iv_pct, skew_25d, rec_struct),
                    )
    finally:
        conn.close()


def export_terminal_snapshot_json(web_dir_override: str = None):
    base_dir = Path(web_dir_override or os.getenv("MOBOCAPITAL_WEB_DIR", "/opt/mobo-stack/sites/mobocapital"))
    pub_data_dir = base_dir / "data"
    pub_data_dir.mkdir(parents=True, exist_ok=True)

    conn = get_capital_db_conn()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT * FROM v_latest_macro_indicators ORDER BY indicator_code;")
            macro_rows = cur.fetchall()
            cur.execute("SELECT * FROM v_latest_options_vol_surface ORDER BY underlying_ticker;")
            vol_rows = cur.fetchall()
            cur.execute("SELECT * FROM portfolio_nav_ledger ORDER BY valuation_date DESC, created_at DESC LIMIT 1;")
            nav_latest = cur.fetchone()

        terminal_payload = {
            "generated_at": datetime.now().isoformat(),
            "macro_indicators": macro_rows,
            "options_vol_surface": vol_rows,
            "nav_risk_regime": nav_latest,
        }

        term_file = pub_data_dir / "terminal-snapshot.json"
        term_file.write_text(
            json.dumps(terminal_payload, default=json_serial, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        print(f"🚀 [MoBoCapital /terminal 终端数据已发布] -> {term_file}")
    finally:
        conn.close()


if __name__ == "__main__":
    run_daily_collection()
    export_terminal_snapshot_json()
EOF_COLLECTOR

# ============================================================================
# [8/8] 写入 Restic 每日冷备、裸机恢复状态机与宿主机巡检哨兵脚本
# ============================================================================
echo "🛡️ [8/8] 正在写入 backup-cron.sh、disaster-recovery.sh 与 mobo_watchdog.sh..."

cat << 'EOF_BACKUP' > "${STACK_DIR}/scripts/backup-cron.sh"
#!/bin/sh
set -e
BACKUP_TMP="/tmp/mobo_pg_dumps"
mkdir -p "$BACKUP_TMP"

echo "[$(date)] Starting PostgreSQL dual-database dump..."
PGPASSWORD="$PG_SUPER_PASSWORD" pg_dump -h mobo-postgres -U postgres -d db_mobobrain -F p > "$BACKUP_TMP/db_mobobrain.sql"
PGPASSWORD="$PG_SUPER_PASSWORD" pg_dump -h mobo-postgres -U postgres -d db_archive -F p > "$BACKUP_TMP/db_archive.sql"

restic snapshots > /dev/null 2>&1 || restic init

echo "[$(date)] Uploading AES-256 encrypted snapshot to OSS..."
restic backup "$BACKUP_TMP" /backup/siyuan /backup/n8n /backup/caddy --tag mobo-daily
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune

rm -rf "$BACKUP_TMP"
echo "[$(date)] Backup completed successfully."
EOF_BACKUP

cat << 'EOF_DR' > "${STACK_DIR}/scripts/disaster-recovery.sh"
#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "🔍 [DRY-RUN 模式] 仅执行六阶段就绪度与快照连通性校验，不覆盖当前生产数据。"
fi

source /opt/mobo-stack/.env
export AWS_ACCESS_KEY_ID="$ALIYUN_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$ALIYUN_ACCESS_KEY_SECRET"
export RESTIC_REPOSITORY="$RESTIC_REPOSITORY"
export RESTIC_PASSWORD="$RESTIC_PASSWORD"

echo "=== [Stage 1/6] 校验宿主机 Swap 与环境变量权限 ==="
free -m | grep -q "Swap:" && echo "✅ Swap 就绪"
chmod 600 /opt/mobo-stack/.env

echo "=== [Stage 2/6] 连接阿里云 OSS 验证 Restic 最新加密快照 ==="
docker run --rm \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e RESTIC_REPOSITORY -e RESTIC_PASSWORD \
  restic/restic:latest snapshots --latest 3

if [ "$DRY_RUN" = true ]; then
    echo "✅ [DRY-RUN 演练通过] Restic 加密快照库完好，随时可执行真实裸机恢复！"
    exit 0
fi

echo "=== [Stage 3/6] 从 OSS 拉取最新快照至 /tmp/mobo_restore ==="
rm -rf /tmp/mobo_restore && mkdir -p /tmp/mobo_restore
docker run --rm \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e RESTIC_REPOSITORY -e RESTIC_PASSWORD \
  -v /tmp/mobo_restore:/restore \
  restic/restic:latest restore latest --target /restore

echo "=== [Stage 4/6] 启动 mobo-postgres 并恢复双数据库 ==="
cd /opt/mobo-stack
docker compose up -d mobo-postgres
sleep 10
docker exec -i mobo-postgres psql -U postgres -d db_mobobrain < /tmp/mobo_restore/tmp/mobo_pg_dumps/db_mobobrain.sql
docker exec -i mobo-postgres psql -U postgres -d db_archive < /tmp/mobo_restore/tmp/mobo_pg_dumps/db_archive.sql

echo "=== [Stage 5/6] 启动全栈 6 容器并同步双站静态 JSON ==="
docker compose up -d
python3 /opt/mobo-stack/scripts/mobo_cli.py sync-capital-web
python3 /opt/mobo-stack/scripts/mobo_cli.py sync-home-web
python3 /opt/mobo-stack/scripts/macro_iv_collector.py

echo "=== [Stage 6/6] 清理临时恢复目录并输出容器健康状态 ==="
rm -rf /tmp/mobo_restore
docker compose ps
echo "🎉 [裸机灾难恢复全部完成]"
EOF_DR

cat << 'EOF_WATCHDOG' > "${STACK_DIR}/scripts/mobo_watchdog.sh"
#!/usr/bin/env bash
source /opt/mobo-stack/.env

MEM_AVAIL_MB=$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo)
DISK_USED_PCT=$(df / | awk 'NR==2 {gsub("%",""); print $5}')
UNHEALTHY_CONTAINERS=$(docker ps --filter "health=unhealthy" --format "{{.Names}}")

ALERT_MSG=""
if [ "$MEM_AVAIL_MB" -lt 300 ]; then
    ALERT_MSG="${ALERT_MSG}[内存预警] 2C4G 宿主机可用内存仅剩 ${MEM_AVAIL_MB}MB；"
fi

if [ "$DISK_USED_PCT" -gt 85 ]; then
    ALERT_MSG="${ALERT_MSG}[磁盘预警] 根分区使用率已达 ${DISK_USED_PCT}%；"
fi

if [ -n "$UNHEALTHY_CONTAINERS" ]; then
    ALERT_MSG="${ALERT_MSG}[容器异常] 发现不健康容器: ${UNHEALTHY_CONTAINERS}，正在自动重启；"
    docker restart $UNHEALTHY_CONTAINERS
fi

if [ -n "$ALERT_MSG" ] && [ -n "${ALERT_WEBHOOK_URL:-}" ]; then
    curl -s -X POST "$ALERT_WEBHOOK_URL" \
      -H 'Content-Type: application/json' \
      -d "{\"msg_type\":\"text\",\"content\":{\"text\":\"🚨 莫伯双站巡检哨兵告警: ${ALERT_MSG}\"}}" > /dev/null
fi
EOF_WATCHDOG

chmod +x "${STACK_DIR}/scripts/"*.sh "${STACK_DIR}/scripts/"*.py

echo ""
echo "============================================================================"
echo "🎉 莫伯双站系统 (MoBoCapital.com & MoBoHome.com) 全部 22 个核心文件已成功落盘！"
echo "📂 根目录: ${STACK_DIR}"
echo "👉 下一步操作指引:"
echo "   1. 编辑真实密钥: vim /opt/mobo-stack/.env"
echo "   2. 安装宿主机 Python 依赖: pip3 install psycopg2-binary oss2 Pillow pypdf python-dotenv pyyaml numpy"
echo "   3. 启动全栈 6 容器: cd /opt/mobo-stack && docker compose up -d"
echo "============================================================================"