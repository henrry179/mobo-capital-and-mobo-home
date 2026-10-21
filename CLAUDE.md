# CLAUDE.md — 莫伯双站系统（MoBoCapital.com & MoBoHome.com）架构宪章 v2.1

> 本文件是 **Claude Code CLI / Codex CLI / Cursor** 等智能体共享的唯一架构记忆。
> 生产部署位置：`/opt/mobo-stack/CLAUDE.md`，并可 `ln -sf CLAUDE.md .cursorrules && ln -sf CLAUDE.md AGENTS.md`。
> 完整总册：[`docs/00-总册/莫伯双站系统全栈架构与部署总册-v2.1.md`](docs/00-总册/莫伯双站系统全栈架构与部署总册-v2.1.md)
> 任务账本：[`TASK_STATE.md`](TASK_STATE.md)

## 1. 系统顶层定位与双站拓扑

本系统在单台 **阿里云 2 核 4GB ECS（Ubuntu 24.04 LTS）** 上通过容器化硬限流与单实例双库隔离，承载两个主权站点：

1. **网站 A：莫伯资本（`MoBoCapital.com`）— 职业纵深、投研智库与对冲基金孵化平台**
   - 业务：全球宏观推演（ITPM）、策略手册（Playbooks）、实战期权与多空交易复盘（Greeks & R-Multiples）、基金三阶段孵化蓝图、《MoBo's Memo》"1+3" 多平台自媒体矩阵。
   - 数据底座：`db_mobobrain`（`intel` 采集域 + `capital` 投研域 + `n8n` 自动化域）。
   - 前端：`sites/mobocapital/index.html`（机构级深海蓝金单页门户），由 CLI 预生成 `data/public-data.json` 与 `internal/internal-data.json` 驱动，服务端 0 额外内存。

2. **网站 B：莫伯之家（`MoBoHome.com`）— 个人成长叙事与 Wolfram 式生命数字档案馆**
   - 业务：人生四篇章（深圳 → 北京 → 上海 → 湖北归航）、影像画廊、跨学科藏书馆、每日跑步与力量训练自律看板、周期复盘。
   - 数据底座：`db_archive`（`archive` Schema）。
   - 前端：`sites/mobohome/index.html`（温润人文风单页门户），由 CLI 预生成 `data/public-home-data.json` 与 `internal/internal-home-data.json` 驱动。

## 2. 宿主机标准目录树（`/opt/mobo-stack`）

```text
/opt/mobo-stack/
├── CLAUDE.md                        # 架构宪章（本文件）
├── TASK_STATE.md                    # 16 步动态交接账本
├── .env                             # 全部敏感变量（chmod 600，严禁入 Git）
├── docker-compose.yml               # 六容器编排 + mem_limit 硬限流
├── deploy/
│   ├── caddy/Caddyfile              # 双主域 HTTPS、/internal BasicAuth 守卫
│   ├── postgres/initdb/01~09.sql    # 双库四 Schema 初始化序列
│   ├── backup/                      # 备份镜像、每日备份、灾备恢复、演练
│   ├── scripts/                     # OSS Guard、主机加固、巡检哨兵、Smoke Test、bootstrap
│   └── volumes/                     # 运行时数据卷
├── services/
│   ├── archive-dashboard/           # Streamlit 生命体征实验室（容器 archive-dashboard）
│   ├── mobo-cli/                    # 双栖 CLI（mobo_cli 包） + 采集器 collectors/
│   └── console/                     # 静态操作台
├── sites/                           # 静态前端工作区（挂载至 mobo-caddy）
│   ├── mobocapital/{index.html,data/,internal/}
│   └── mobohome/{index.html,data/,internal/}
├── workflows/                       # n8n 工作流 JSON、prompts/、nodes/
├── migrations/ seeds/ tests/ tools/
```

## 3. 五条不可逾越的架构红线

1. **2C4G 内存硬限流**：严格维持 6 个容器，`mem_limit` 合计 1.84GB，常驻实测约 0.64GB（云端目标 ≤1.2GB）；严禁引入 Elasticsearch、Redis 集群或额外常驻 Web 后端。
   `caddy 80m` / `postgres 600m` / `siyuan 300m` / `n8n 512m` / `dashboard 200m` / `restic 150m`；宿主机 4GB Swap、`vm.swappiness=10`。
   n8n 限额取 512m 是因为其启动迁移期 V8 堆峰值约 300MB（`NODE_OPTIONS=--max-old-space-size=400`）。
2. **PostgreSQL 双库物理隔离**：`user_mobobrain` 仅读写 `db_mobobrain`（`intel` + `capital`）；`user_archive` 仅读写 `db_archive`；严禁 FDW、严禁超级用户运行业务。
3. **OSS 内网免流与冷热分层**：容器内强制 `oss-cn-hangzhou-internal.aliyuncs.com`；原件前缀 `photo/`、`video/`、`scan_doc/`、`blotters/` 自动转冷；前端列表只加载 `thumbnails/`。
4. **公私域物理脱敏与三级权限**：`PUBLIC` / `LP_PROSPECT` / `INTERNAL`；导出公域包时物理删除私有 OSS Key 字段并剔除 `INTERNAL` / `is_sensitive` 记录；`/internal/*` 强制 Caddy `basic_auth`。
5. **境内/境外双轨内容合规**：微信、雪球版本自动脱敏具体买卖点位并强制免责声明；所有发布必须经 **HITL 人工终审阀门**。

## 4. 三大智能体职责边界

- **Claude Code CLI（架构与生产运维）**：Swap/Sysctl 调优、Compose 编排、Caddyfile、PostgreSQL 01–09 注入与触发器验证、Restic 备份与灾备演练。
- **Codex CLI（自动化工具链与安全审计）**：`services/mobo-cli/`（含 `exporters.py` 脱敏、`capital.py` 投研读写）、`oss_guard_setup.py`、n8n 工作流 JSON、公私域 JSON 脱敏审计。
- **Cursor（前端与可视化）**：`sites/mobocapital/index.html`、`sites/mobohome/index.html`、`services/archive-dashboard/`。

## 5. 交接铁律

- 任何智能体开工前先读 `TASK_STATE.md`；完成后必须运行该任务的**验收命令**，把状态改为 `DONE` 并附实测日志，才能移交下一智能体。
- 数据库结构变更走 `migrations/`，不得改写已执行的 `deploy/postgres/initdb/` 文件。
- 密钥只进 `.env` 与密码管理器；任何提交前先跑 `git status` 确认 `.env` 未入库。
- 提交前必须通过：`bash -n`（脚本）、`node -e "JSON.parse(...)"`（工作流）、`pytest`（CLI 与看板单测）、`tests/sql/smoke.sql`（数据库）。
