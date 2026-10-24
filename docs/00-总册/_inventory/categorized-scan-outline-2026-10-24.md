# 分类扫描大纲（读前计划）

- 全量文档清单：`_tmp_full_doc_inventory.txt` → **1117** 份
- 其中项目侧（已剔 vendor/第三方克隆噪声）：**736**
- 其中 vendor/工具链噪声：**381**（本轮不逐字通读）
- 双站工程核心（docs/deploy/services/sites/… + 根宪章）：**169**
- 扫描排除树（未入全量清单）：`.git` / `node_modules` / `deploy/volumes` / `hermes-migration` / `.cursor`

## 按种类汇总（项目侧）

| 种类 | 项目侧计数 | 双站核心计数 | 样例路径（最多 5） | 本轮读优先级 |
|---|---:|---:|---|---|
| 总体方案 | 7 | 7 | `docs/00-总册/双站规划文档整合总览.md`<br>`docs/00-总册/归档/莫伯双站系统全栈架构与部署总册-v1.1.md`<br>`docs/00-总册/生产级落地附录-v2.1.md`<br>`docs/00-总册/莫伯双站系统全栈架构与部署总册-v2.1.md`<br>`docs/07-原始资料/原始方案/MoBoBrain双网站建设方案.docx` | P0 |
| 双站项目 | 30 | 25 | `deploy/postgres/initdb/05-mobocapital-schema.sql`<br>`deploy/postgres/initdb/06-mobocapital-nav-and-triggers.sql`<br>`deploy/postgres/initdb/07-mobocapital-terminal-schema.sql`<br>`docs/01-项目治理/决策记录/ADR-0007-双主域拓扑与静态门户三级可见性.md`<br>`docs/07-原始资料/《莫伯双站-内容原料深度整合与整理方案-v2》.docx` | P0 |
| 架构 | 31 | 31 | `CLAUDE.md`<br>`deploy/caddy/Caddyfile`<br>`deploy/postgres/initdb/01-init-dual-db.sql`<br>`deploy/postgres/initdb/02-archive-schema.sql`<br>`deploy/postgres/initdb/03-archive-triggers.sql` | P0 |
| 规划 | 6 | 4 | `docs/01-项目治理/开发部署任务执行时间线.md`<br>`docs/01-项目治理/范围与边界.md`<br>`docs/01-项目治理/里程碑与WBS.md`<br>`docs/01-项目治理/项目章程.md` | P1 |
| 方案 | 74 | 0 | `01-工作与项目/AutopilotTradeBoMo/01_原始文档/AIGC原稿/OpenClaw完整部署方案-简历更新版-0321.docx`<br>`01-工作与项目/ITPM-PlayBooks/potm-2.0/guides/DOCUMENTATION_STRUCTURE.md`<br>`01-工作与项目/ITPM-PlayBooks/potm-2.0/guides/completed_todos.md`<br>`01-工作与项目/ITPM-PlayBooks/potm-2.0/guides/historical_context_records.md`<br>`01-工作与项目/ITPM-PlayBooks/potm-2.0/guides/integration_report.md` | P1 |
| 任务 | 9 | 6 | `TASK_STATE.md`<br>`docs/02-需求与验收/测试计划.md`<br>`docs/02-需求与验收/需求规格说明书.md`<br>`docs/02-需求与验收/非功能需求.md`<br>`docs/02-需求与验收/验收标准与DoD.md` | P1 |
| 项目 | 421 | 33 | `README.md`<br>`docs/01-项目治理/决策记录/ADR-0010-本地优先开发暂不进入公网部署.md`<br>`docs/01-项目治理/决策记录/ADR-0011-WSL2作为本地开发运行时.md`<br>`docs/01-项目治理/决策记录/README.md`<br>`docs/01-项目治理/风险登记册.md` | P2 |
| 字段定义 | 13 | 13 | `docs/00-总册/术语表.md`<br>`docs/04-数据库设计/网站A数据字典.md`<br>`docs/04-数据库设计/网站B数据字典.md`<br>`docs/04-数据库设计/莫伯资本数据字典.md`<br>`docs/04-数据库设计/触发器与视图.md` | P0 |
| 未归类文档 | 145 | 50 | `deploy/backup/Dockerfile`<br>`deploy/scripts/requirements.txt`<br>`docs/00-总册/_inventory/planning-docs-index.md`<br>`docs/00-总册/文档修订记录.md`<br>`docs/00-总册/文档整合与清理建议.md` | P3-跳过或抽检 |

## 双站核心 · 各类完整路径清单（供通读）

### 总体方案（7）
- `docs/00-总册/双站规划文档整合总览.md`
- `docs/00-总册/归档/莫伯双站系统全栈架构与部署总册-v1.1.md`
- `docs/00-总册/生产级落地附录-v2.1.md`
- `docs/00-总册/莫伯双站系统全栈架构与部署总册-v2.1.md`
- `docs/07-原始资料/原始方案/MoBoBrain双网站建设方案.docx`
- `docs/07-原始资料/原始方案/莫伯双站系统全栈架构与部署总册.docx`
- `docs/07-原始资料/原始方案/阿里云云端多智能体网站平台_部署与运营整合方案.docx`

### 双站项目（25）
- `deploy/postgres/initdb/05-mobocapital-schema.sql`
- `deploy/postgres/initdb/06-mobocapital-nav-and-triggers.sql`
- `deploy/postgres/initdb/07-mobocapital-terminal-schema.sql`
- `docs/01-项目治理/决策记录/ADR-0007-双主域拓扑与静态门户三级可见性.md`
- `docs/07-原始资料/《莫伯双站-内容原料深度整合与整理方案-v2》.docx`
- `docs/07-原始资料/内容原料仓完整整理方案-v1.md`
- `docs/07-原始资料/内容原料仓深度整合与整理方案-v2.md`
- `docs/07-原始资料/内容资产盘点与归库映射-2026-10-21.md`
- `docs/07-原始资料/归档-代码/04-应用代码/mobohome-index-早期版.html`
- `docs/07-原始资料/归档-代码/mobo-stack.env.vars.txt`
- `docs/07-原始资料/莫伯双站V5-新会话交接-2026-10-23.md`
- `docs/07-原始资料/莫伯双站V5执行仪表板-2026-10-23.html`
- `docs/07-原始资料/莫伯双站V5执行报告-2026-10-23.md`
- `docs/07-原始资料/莫伯双站上线同步包与内容整理方案-v4.md`
- `docs/07-原始资料/莫伯双站内容资产双维分析与整合方案-v3.md`
- `docs/07-原始资料/莫伯双站内容资产双维盘点仪表板.html`
- `docs/07-原始资料/莫伯双站原件保全与双站同步方案-v5.md`
- `sites/mobocapital/data/public-data.json`
- `sites/mobocapital/data/terminal-snapshot.json`
- `sites/mobocapital/index.html`
- `sites/mobocapital/internal/internal-data.json`
- `sites/mobohome/data/public-home-data.json`
- `sites/mobohome/index.html`
- `sites/mobohome/internal/internal-home-data.json`
- `workflows/workflow-03-mobocapital-1plus3.template.json`

### 架构（31）
- `CLAUDE.md`
- `deploy/caddy/Caddyfile`
- `deploy/postgres/initdb/01-init-dual-db.sql`
- `deploy/postgres/initdb/02-archive-schema.sql`
- `deploy/postgres/initdb/03-archive-triggers.sql`
- `deploy/postgres/initdb/04-mobobrain-schema.sql`
- `deploy/postgres/initdb/08-indexes-grants.sql`
- `deploy/postgres/initdb/09-updated-at-triggers.sql`
- `docker-compose.local.yml`
- `docker-compose.wsl.yml`
- `docker-compose.yml`
- `docs/01-项目治理/决策记录/ADR-0001-单机双库与Schema隔离.md`
- `docs/01-项目治理/决策记录/ADR-0002-域名拓扑与公开静态站.md`
- `docs/01-项目治理/决策记录/ADR-0003-n8n子域与数据Schema.md`
- `docs/01-项目治理/决策记录/ADR-0004-备份与灾备.md`
- `docs/01-项目治理/决策记录/ADR-0005-中文检索与向量维度.md`
- `docs/01-项目治理/决策记录/ADR-0006-安全与鉴权基线.md`
- `docs/01-项目治理/决策记录/ADR-0008-db_mobobrain增设capital-schema.md`
- `docs/01-项目治理/决策记录/ADR-0009-公私域物理脱敏与HITL发布闸门.md`
- `docs/03-架构设计/宿主机标准目录树-v2.1.txt`
- `docs/03-架构设计/总体架构.md`
- `docs/03-架构设计/数据架构.md`
- `docs/03-架构设计/标准生产目录树-v2.1.txt`
- `docs/03-架构设计/网络与安全架构.md`
- `docs/03-架构设计/部署架构.md`
- `docs/07-原始资料/归档-代码/02-sql-精简版/02-archive-schema.sql`
- `docs/07-原始资料/归档-代码/03-部署配置草稿/5.1-Caddyfile-精简版.txt`
- `docs/07-原始资料/归档-代码/03-部署配置草稿/Caddyfile-v2.1.txt`
- `docs/07-原始资料/归档-代码/03-部署配置草稿/P0-Caddyfile-草稿.txt`
- `docs/07-原始资料/归档-代码/03-部署配置草稿/docker-compose-v2.1.yaml`
- `migrations/202610200001__schema_migrations.sql`

### 规划（4）
- `docs/01-项目治理/开发部署任务执行时间线.md`
- `docs/01-项目治理/范围与边界.md`
- `docs/01-项目治理/里程碑与WBS.md`
- `docs/01-项目治理/项目章程.md`

### 任务（6）
- `TASK_STATE.md`
- `docs/02-需求与验收/测试计划.md`
- `docs/02-需求与验收/需求规格说明书.md`
- `docs/02-需求与验收/非功能需求.md`
- `docs/02-需求与验收/验收标准与DoD.md`
- `docs/06-合规与成本/成本与部署仪表板.html`

### 项目（33）
- `README.md`
- `docs/01-项目治理/决策记录/ADR-0010-本地优先开发暂不进入公网部署.md`
- `docs/01-项目治理/决策记录/ADR-0011-WSL2作为本地开发运行时.md`
- `docs/01-项目治理/决策记录/README.md`
- `docs/01-项目治理/风险登记册.md`
- `docs/04-数据库设计/README.md`
- `docs/04-数据库设计/迁移与备份策略.md`
- `docs/05-运维与灾备/备份与恢复演练.md`
- `docs/05-运维与灾备/安全基线.md`
- `docs/05-运维与灾备/故障排查.md`
- `docs/05-运维与灾备/日常运维.md`
- `docs/05-运维与灾备/本地开发与部署.md`
- `docs/05-运维与灾备/本地阶段自检清单.md`
- `docs/05-运维与灾备/监控告警.md`
- `docs/05-运维与灾备/证据/README.md`
- `docs/05-运维与灾备/部署手册.md`
- `docs/06-合规与成本/ICP与域名材料清单.md`
- `docs/06-合规与成本/密钥与凭据清单.md`
- `docs/06-合规与成本/成本台账.md`
- `docs/06-合规与成本/证券与自媒体合规.md`
- `docs/06-合规与成本/隐私与数据分类.md`
- `docs/07-原始资料/README.md`
- `docs/07-原始资料/外部项目档案/全球宏观财经金融OPC_Hermes_GrokBot_统一项目档案_区分用户与AI.md`
- `docs/07-原始资料/外部项目档案/全球宏观财经金融OPC_Hermes_GrokBot统一项目档案.md`
- `migrations/README.md`
- `seeds/README.md`
- `services/console/README.md`
- `services/mobo-cli/README.md`
- `tests/README.md`
- `tools/local-preview/README.md`
- `tools/vault/README.md`
- `tools/wsl/README.md`
- `workflows/README.md`

### 字段定义（13）
- `docs/00-总册/术语表.md`
- `docs/04-数据库设计/网站A数据字典.md`
- `docs/04-数据库设计/网站B数据字典.md`
- `docs/04-数据库设计/莫伯资本数据字典.md`
- `docs/04-数据库设计/触发器与视图.md`
- `docs/07-原始资料/资产盘点数据-2026-10-22/duplicate-summary.json`
- `docs/07-原始资料/资产盘点数据-2026-10-22/launch-packages.csv`
- `docs/07-原始资料/资产盘点数据-2026-10-22/launch-packages.json`
- `docs/07-原始资料/资产盘点数据-2026-10-22/summary.json`
- `docs/07-原始资料/资产盘点数据-2026-10-22/sync-v5-category.csv`
- `docs/07-原始资料/资产盘点数据-2026-10-22/sync-v5-local.csv`
- `docs/07-原始资料/资产盘点数据-2026-10-22/sync-v5-p2.csv`
- `docs/07-原始资料/资产盘点数据-2026-10-22/sync-v5.json`

### 未归类文档（50）
- `deploy/backup/Dockerfile`
- `deploy/scripts/requirements.txt`
- `docs/00-总册/_inventory/planning-docs-index.md`
- `docs/00-总册/文档修订记录.md`
- `docs/00-总册/文档整合与清理建议.md`
- `docs/07-原始资料/归档-代码/02-sql-精简版/01-init-dual-db.sql`
- `docs/07-原始资料/归档-代码/02-sql-精简版/03-archive-triggers.sql`
- `docs/07-原始资料/归档-代码/03-部署配置草稿/5.2-六容器编排-v2.1.yaml`
- `docs/07-原始资料/归档-代码/04-应用代码/requirements-dashboard-固定版本.txt`
- `docs/07-原始资料/归档-代码/04-应用代码/site-占位首页.html`
- `docs/07-原始资料/站点内容同步记录-2026-10-21.md`
- `docs/07-原始资料/资产盘点数据-2026-10-22/cross-matrix.csv`
- `docs/07-原始资料/资产盘点数据-2026-10-22/dashboard-data.json`
- `docs/07-原始资料/资产盘点数据-2026-10-22/dashboard_template.html`
- `docs/07-原始资料/资产盘点数据-2026-10-22/duplicate-by-folder.json`
- `docs/07-原始资料/资产盘点数据-2026-10-22/duplicates.csv`
- `docs/07-原始资料/资产盘点数据-2026-10-22/ext-detail.csv`
- `docs/07-原始资料/资产盘点数据-2026-10-22/filetype-size.csv`
- `docs/07-原始资料/资产盘点数据-2026-10-22/folder-size-level1.csv`
- `docs/07-原始资料/资产盘点数据-2026-10-22/folder-size-level2.csv`
- `docs/07-原始资料/资产盘点数据-2026-10-22/folder-size-level3.csv`
- `docs/07-原始资料/资产盘点数据-2026-10-22/folder-size-level4.csv`
- `docs/07-原始资料/资产盘点数据-2026-10-22/launch-category.csv`
- `docs/07-原始资料/资产盘点数据-2026-10-22/launch-package-category.csv`
- `docs/07-原始资料/资产盘点数据-2026-10-22/launch-package-folder.csv`
- `docs/07-原始资料/资产盘点数据-2026-10-22/top-files.csv`
- `migrations/202610210001__grant_n8n_create_on_database.sql`
- `seeds/52-week-sandbox.sql`
- `services/archive-dashboard/.streamlit/config.toml`
- `services/archive-dashboard/Dockerfile`
- `services/archive-dashboard/requirements-dev.txt`
- `services/archive-dashboard/requirements.txt`
- `services/console/data/credentials.local.json`
- `services/console/data/gate.json`
- `services/console/data/status.json`
- `services/console/index.html`
- `services/mobo-cli/mobo_cli.egg-info/SOURCES.txt`
- `services/mobo-cli/mobo_cli.egg-info/dependency_links.txt`
- `services/mobo-cli/mobo_cli.egg-info/entry_points.txt`
- `services/mobo-cli/mobo_cli.egg-info/requires.txt`
- `services/mobo-cli/mobo_cli.egg-info/top_level.txt`
- `services/mobo-cli/pyproject.toml`
- `tests/sql/dashboard-real-data.sql`
- `tests/sql/smoke.sql`
- `tools/local-preview/architecture.html`
- `tools/local-preview/lab-placeholder.html`
- `workflows/prompts/mobo-capital-synthesis-prompt.md`
- `workflows/wechat-draft-push.template.json`
- `workflows/workflow-01-rss-to-vault.template.json`
- `workflows/workflow-02-score-to-draft.template.json`

