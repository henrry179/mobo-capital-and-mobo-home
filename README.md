# 莫伯双站系统（MoBoCapital.com & MoBoHome.com）

> 莫伯资本：全球宏观投研智库 · 对冲基金孵化蓝图 ·《MoBo's Memo》财经自媒体"1+3"矩阵
> 莫伯之家：个人主权数字档案馆 · Wolfram 式生命体征看板
> 项目源库 / 架构基线 / 部署交付物 / 运维手册 / 合规清单

   

## 1. 系统是什么

一台阿里云 2 核 4GB 主机，Docker Compose 六容器，承载两个逻辑独立、数据可恢复、可长期维护的网站：

| 站点 | 定位 | 数据底座 | 访问策略 |
|   |   |   |   |
| **网站 A：莫伯资本** | 投研智库、策略手册、实盘复盘与 NAV 风控、基金孵化蓝图、四端自媒体 | `db_mobobrain`（`intel` + `capital` Schema） | 主站公开；`/internal/*` 与后台强认证 |
| **网站 B：莫伯之家** | 人生叙事、影像画廊、藏书馆、阅读/运动/复盘与体征看板 | `db_archive`（`archive` Schema） | 公开栏目 + `/internal/*` 强认证 |

统一基础设施：Caddy 2 双主域网关、PostgreSQL 16（pgvector）单实例双库四 Schema、阿里云 OSS 双 Bucket 冷热分层、Restic 每日加密备份。

   

## 2. 当前状态

  **模式**：**本地优先（Local First）** —— 双主域未注册、ICP 未启动，**暂不进入公网部署**
  **阶段**：**本地全栈已跑通（L0/L1 完成）** —— WSL2 内 Docker 六容器全部 healthy，数据库冒烟 9 组全绿
  **已完成**：总册 v2.1 + 架构宪章 + 16 步账本 + **开发部署执行时间线**、治理/需求/架构/数据字典/运维/合规文档、数据库 `01~09` SQL、六容器 Compose（内存硬限流）、双域 Caddyfile、CLI（投研录入 + 公私域脱敏导出）、Streamlit 看板、双站静态门户、n8n 工作流与提示词资产、备份/灾备/演练/巡检脚本、WSL2 本地运行时脚本、测试与沙盒
  **内存实测**：六容器合计约 **636 MiB**（限额 1.84GB），低于 1.55GB 常驻红线
  **待验证**：CLI/看板单测、n8n 三工作流阶段一联调、本地 Restic 恢复演练（L2–L4）
  **未完成**：云端采购与备案、n8n 阶段二发布（微信/X，当前只产 JSON 草稿）、公网验收
  **生产可用性**：**尚未达到**。所有密钥均为占位符；切换公网前必须按 `docs/05 运维与灾备/部署手册.md` 完成替换与验收

> **下一步入口**：[开发部署执行时间线](docs/01-项目治理/开发部署任务执行时间线.md)（D0→D5 本地 / T0+6 公网）｜[本地开发与部署](docs/05-运维与灾备/本地开发与部署.md)｜[本地自检清单](docs/05-运维与灾备/本地阶段自检清单.md)｜[WSL2 运行时](tools/wsl/README.md)

   

## 3. 目录导航

```text
.
├─ README.md                     # 本文件
├─ CLAUDE.md                     # 架构宪章（五条红线，多智能体共享）
├─ TASK_STATE.md                 # 16 步动态交接账本（T01–T16）
├─ docker compose.yml            # 六容器编排 + 内存硬限流 + 三网络
├─ .env.example                  # 环境变量模板（v2.1 口径，不含真实密钥）
├─ docs/
│  ├─ 00 总册/                   # v2.1 总册、归档 v1.1、术语表、修订记录
│  ├─ 01 项目治理/               # 章程、范围、WBS、风险、ADR-0001~0009
│  ├─ 02 需求与验收/             # 需求、NFR、验收标准、测试计划
│  ├─ 03 架构设计/               # 总体、网络与安全、数据、部署、标准目录树
│  ├─ 04 数据库设计/             # A/B/莫伯资本数据字典、触发器与视图、迁移与备份
│  ├─ 05 运维与灾备/             # 部署、日常运维、监控、排障、演练、安全基线
│  ├─ 06 合规与成本/             # ICP、隐私、证券与自媒体合规、成本台账、密钥清单
│  └─ 07 原始资料/               # 原始 docx、外部档案、归档代码与差异清单
├─ deploy/
│  ├─ caddy/Caddyfile            # 双主域 + /internal + /lab + 安全头 + 日志
│  ├─ postgres/initdb/           # 01~09 初始化 SQL（双库四 Schema）
│  ├─ backup/                    # 备份镜像、每日备份、灾备恢复、演练
│  ├─ scripts/                   # OSS Guard、主机加固、巡检哨兵、Smoke Test、bootstrap
│  └─ volumes/                   # 运行时数据卷（Git 忽略）
├─ services/
│  ├─ archive dashboard/         # Streamlit 生命体征 Z Score / Lead Lag 实验室
│  ├─ mobo cli/                  # 双栖 CLI（投研读写 + 公私域脱敏导出 + 采集器）
│  └─ console/                   # 静态操作台
├─ sites/                        # 静态前端工作区（挂载至 Caddy）
│  ├─ mobocapital/               # 莫伯资本门户（五大栏目 + 三级权限）
│  └─ mobohome/                  # 莫伯之家门户（人生篇章 / 画廊 / 藏书馆）
├─ workflows/                    # n8n 工作流模板、prompts/、nodes/
├─ migrations/ seeds/ tests/     # 迁移 runner、沙盒数据、冒烟与单测
└─ tools/doc builder/            # Markdown → 机构级 docx 生成器
```

   

## 4. 架构一览

```mermaid
flowchart TB
    U[用户 / 浏览器]   >|HTTPS| C[Caddy 2 双主域网关]

    C   >|mobocapital.com| CAP[莫伯资本门户<br/>静态 + 预生成 JSON]
    C   >|mobohome.com| HOME[莫伯之家门户<br/>静态 + 预生成 JSON]
    C   >|kb + BasicAuth| SY[思源笔记]
    C   >|n8n + BasicAuth| N8N[n8n 双工作流]
    C   >|lab + BasicAuth| DASH[Streamlit 实验室]
    C   >|admin + BasicAuth| CON[静态操作台]

    N8N   >|评分 ≥7 写入母本| SY
    N8N   >|四端 JSON| CAPDB[(capital.capital_publications)]
    N8N   >|采集入库| INTL[(intel.articles_vault)]

    CLI[mobo cli]   >|读写| PG[(PostgreSQL 16<br/>db_mobobrain / db_archive)]
    CLI   >|物理脱敏后写盘| CAP
    CLI   > HOME
    CLI   >|SHA 256 去重| OSS[(阿里云 OSS<br/>公开图床 + 私有档案桶)]
    PG   > BK[restic backup]   >|AES 256| OSS
```

   

## 5. 五条架构红线

1. **2C4G 内存硬限流**：六容器 `mem_limit` 合计 1.64GB、常驻约 1.46GB；前台静态化，服务端 0 额外开销。
2. **PostgreSQL 双库物理隔离**：`user_mobobrain` 只读写 `db_mobobrain`，`user_archive` 只读写 `db_archive`；禁 FDW、禁超级用户跑业务。
3. **OSS 内网免流与冷热分层**：容器内强制 ` internal` Endpoint；原件按前缀自动转冷，前端只加载 `thumbnails/`。
4. **公私域物理脱敏与三级权限**：`PUBLIC`/`LP_PROSPECT`/`INTERNAL`；公域包写盘前删除私有字段并剔除内部记录；`/internal/*` 强制 BasicAuth。
5. **境内/境外双轨合规**：境内版本脱敏点位与收益承诺并强制免责声明；所有发布经人工终审（HITL）。

详见 [`CLAUDE.md`](CLAUDE.md) 与 ADR-0007~0009。

   

## 6. 快速开始（本地开发）

> 当前处于**本地优先**模式：不买服务器、不申请域名也能把整套系统跑起来。
> 完整步骤见 [`docs/05 运维与灾备/本地开发与部署.md`](docs/05-运维与灾备/本地开发与部署.md)；公网部署见 [`部署手册.md`](docs/05-运维与灾备/部署手册.md)。

### 模式 A · 零依赖预览（只需 Node.js，当前即可用）

```bash
node tools/local preview/start.js
```

| 入口 | 地址 |
|   |   |
| 架构与入口总览（拓扑 + 实时状态 + 差异对照） | http://127.0.0.1:8082/ |
| 莫伯资本 MoBoCapital | http://127.0.0.1:8080/ |
| 莫伯之家 MoBoHome | http://127.0.0.1:8081/ |
| 内网驾驶舱（BasicAuth：mobo / mobo local） | http://127.0.0.1:8080/internal/internal data.json |

> 与生产**同一套前端文件、同一套路由/鉴权/缓存/脱敏口径**；差别只在数据来自样例脚本还是真实数据库。

### 模式 B · Docker 全栈（目标形态）

**Windows + WSL2 （本机当前形态）**：

```bash
# 一次性：WSL 内装 Docker Engine（免 Windows 管理员权限）
wsl  u root  e bash  lc "bash /mnt/d/.../tools/wsl/install docker in wsl.sh"

# 日常：起全栈 + 冒烟 + 内存统计
cd /mnt/e/01 文档资料/报告与规划/莫伯双站系统
bash tools/wsl/wsl up.sh
```

| 入口 | 地址 | 认证 |
|   |   |   |
| 莫伯资本 | `http://localhost/` | 公开 |
| 莫伯之家 | `http://mobohome.localhost/` | 公开 |
| 生命体征实验室 | `http://lab.localhost/` | BasicAuth |
| 思源笔记 / n8n / 操作台 | `http://kb.localhost/` `http://n8n.localhost/` `http://admin.localhost/` | BasicAuth |

**通用 Docker（含 Docker Desktop / Linux）**：

```bash
cp .env.example .env.local      # 覆盖本地口令与 localhost 域名
docker compose  f docker compose.yml  f docker compose.local.yml   env file .env.local up  d   build
docker compose  f docker compose.yml  f docker compose.local.yml   env file .env.local exec  T postgres \
  psql  U postgres  d db_archive  f /tmp/smoke.sql   # 9 组冒烟
docker stats   no stream        # 常驻应 < 1.55GB
```

没有 OSS 时看板会自动切到"52 周合成沙盒"；灌沙盒数据：

```bash
dc cp seeds/52 week sandbox.sql postgres:/tmp/seed.sql
dc exec  T postgres psql  U postgres  d db_archive  f /tmp/seed.sql
```

### CLI 速查

```bash
cd services/mobo cli && pip install  e ".[dev]"

mobo cli doctor                     # 配置自检
mobo cli upload a.jpg   category PHOTO
mobo cli workout   type RUNNING   minutes 51   distance km 10
mobo cli capital thesis   code THESIS LOCAL 01   title "..."   conviction 8
mobo cli capital trade   trade code T 001   ticker 300ETF   entry date 2026 10 18   risk pct 1.25
mobo cli capital trade   trade code T 001   close   exit date 2026 10 25   r multiple 1.8   impact bps 180
mobo cli capital nav                 # NAV 与回撤熔断状态
mobo cli export site   site all      # 导出公私域数据包（写盘前自动脱敏审计）
```

   

## 7. 安全提醒

  仓库内**不得**提交 `.env`、AK/SK、Restic 密码、n8n 加密密钥、Bcrypt 哈希真实值。
  `mobo stack.env` 这类生产环境变量文件已在整理时**剔除并仅保留变量名清单**（见 `docs/07 原始资料/归档 代码/mobo stack.env.vars.txt`）。
  网站 B 存个人隐私数据、网站 A 存实盘复盘：公网部署前必须完成 HTTPS、BasicAuth、`/internal` 鉴权、SSH 加固、防火墙、脱敏审计与备份演练。
  阿里云 RAM 子账号不要使用 `AliyunOSSFullAccess`。
  境内内容发布必须过 [`证券与自媒体合规`](docs/06-合规与成本/证券与自媒体合规.md) 检查清单。

   

## 8. 文档入口

| 主题 | 文档 |
|   |   |
| 总纲 | [总册 v2.1](docs/00-总册/莫伯双站系统全栈架构与部署总册-v2.1.md) ｜ [生产级落地附录](docs/00-总册/生产级落地附录-v2.1.md) |
| 治理 | [章程](docs/01-项目治理/项目章程.md) ｜ [范围与边界](docs/01-项目治理/范围与边界.md) ｜ [WBS](docs/01-项目治理/里程碑与WBS.md) ｜ [风险](docs/01-项目治理/风险登记册.md) |
| 架构 | [总体](docs/03-架构设计/总体架构.md) ｜ [网络与安全](docs/03-架构设计/网络与安全架构.md) ｜ [数据](docs/03-架构设计/数据架构.md) ｜ [部署](docs/03-架构设计/部署架构.md) |
| 数据 | [总览](docs/04-数据库设计/README.md) ｜ [莫伯资本字典](docs/04-数据库设计/莫伯资本数据字典.md) ｜ [触发器与视图](docs/04-数据库设计/触发器与视图.md) ｜ [迁移与备份](docs/04-数据库设计/迁移与备份策略.md) |
| 运维 | [部署手册](docs/05-运维与灾备/部署手册.md) ｜ [本地开发与部署](docs/05-运维与灾备/本地开发与部署.md) ｜ [本地自检清单](docs/05-运维与灾备/本地阶段自检清单.md) ｜ [日常运维](docs/05-运维与灾备/日常运维.md) ｜ [监控告警](docs/05-运维与灾备/监控告警.md) ｜ [排障](docs/05-运维与灾备/故障排查.md) ｜ [演练](docs/05-运维与灾备/备份与恢复演练.md) ｜ [安全基线](docs/05-运维与灾备/安全基线.md) |
| 合规 | [ICP](docs/06-合规与成本/ICP与域名材料清单.md) ｜ [隐私与分类](docs/06-合规与成本/隐私与数据分类.md) ｜ [证券与自媒体](docs/06-合规与成本/证券与自媒体合规.md) ｜ [成本](docs/06-合规与成本/成本台账.md) ｜ [密钥](docs/06-合规与成本/密钥与凭据清单.md) |
| 原始资料 | [索引与差异清单](docs/07-原始资料/README.md) |

   

## 9. 版本

  v1.0：`莫伯双站系统全栈架构与部署总册.docx`（2026 10 15，MoBoBrain + 个人档案）—— 已归档
  v1.1：工程化基线（单主域、intel/archive 双 Schema）—— 已归档于 `docs/00 总册/归档/`
  **v2.1：双主域 + 投研/自媒体/量化终端（当前基线）**
  维护方式：文档与代码同仓，架构级变更先写 ADR，数据库变更走 `migrations/`。
