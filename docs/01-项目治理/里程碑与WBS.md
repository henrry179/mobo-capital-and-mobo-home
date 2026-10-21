# 里程碑与 WBS（v2.1.1 双站实施计划 · 本地优先）

> 状态：`DONE` 已完成并验证｜`CODE_READY` 交付物已就位、待环境验证｜`READY` 方案就绪待执行｜`BLOCKED` 被外部条件阻塞｜`暂缓` 本阶段主动挂起。
> 本表是项目**唯一任务清单**；动态交接账本见根目录 [`TASK_STATE.md`](../../TASK_STATE.md)。
> **当前模式**：本地优先（[ADR-0010](决策记录/ADR-0010-本地优先开发暂不进入公网部署.md)）—— 双主域未注册，**不进入公网部署**，云端任务挂起，本地完成 L0–L6。

## 1. 阶段总览

| 阶段 | 名称 | 预计 | 关键产出 | 退出条件 | 状态 |
|---|---|---:|---|---|---|
| E0 | 工程基线（本仓库） | 已完成 | 总册 v2.1、宪章、账本、ADR、01–09 SQL、Compose/Caddy、CLI/看板/门户、工作流资产、测试与文档 | 交付物入库且静态校验通过 | 完成 |
| **L** | **本地开发与验证** | **3–5d** | **本地全栈跑通、9 组冒烟、CLI 投研与脱敏导出、工作流阶段一、备份演练、质量门** | **L5 质量门全绿** | **进行中** |
| 一 | 云资源采购与备案 | 挂起 | ECS、双 OSS 桶、RAM 子账号、双域名 ICP | 备案进入管局审核 | 暂缓（域名未注册） |
| 二 | 宿主机加固与 OSS 防护 | 挂起 | Swap、目录树、`.env`(600)、OSS Guard | 4 条生命周期生效 | 暂缓 |
| 三 | 数据库与容器全栈 | 部分本地完成 | 01–09 SQL 注入、双库四 Schema、六容器 | Smoke Test 通过 | 本地 L1 |
| 四 | 网关、n8n 与灾备 | 部分本地完成 | 双域 HTTPS、n8n 三流、首次备份 | 401 生效、快照存在 | 本地 L3/L4；公网暂缓 |
| 五 | 上线封版与运营 | 挂起 | 监控、巡检、恢复演练、验收、交接 | 验收清单全绿 | 暂缓 |

**总计**：工程基线已就绪；**本地阶段约 3–5 个工作日**；公网上线待域名与 ICP 就绪后按 T01–T16 恢复。

## 1.1 本地阶段任务（L0–L6）

| ID | 任务 | 产出 / DoD | 依赖 | 状态 |
|---|---|---|---|---|
| L0 | 本地环境与编排基线 | Docker Desktop + `.env.local`；`docker compose config` 通过；变量缺失 0 | — | READY |
| L1 | 数据库内核落地验证 | 01–09 首次初始化；`tests/sql/smoke.sql` 9 组全绿；`capital` 域就位 | L0 | READY |
| L2 | 应用与门户本地跑通 | 看板四模块；CLI `capital-*`/`export-site` 可用；5 个静态数据包产出；脱敏审计 0 违规 | L1 | READY |
| L3 | n8n 本地联调（阶段一） | 工作流 #1/#2/#3 阶段一跑通；`capital_publications` 出现 `PENDING_REVIEW`；发布节点保持禁用 | L1/L2 | READY |
| L4 | 本地备份与恢复演练 | 本地 Restic 仓库有快照；`restore-drill.sh` 核心表计数一致；RTO 有记录 | L1 | READY |
| L5 | 质量门 | 单测 / JSON 校验 / `bash -n` / smoke / 内存实测 < 1.55GB 全绿 | L2–L4 | READY |
| L6 | 公网就绪包 | 域名、ICP、密钥、监控、验收材料备齐但**不启用** | — | READY |

> 操作步骤：[`docs/05-运维与灾备/本地开发与部署.md`](../05-运维与灾备/本地开发与部署.md)

## 2. 关键路径与并行

```text
E0 工程基线 ─▶ L0 环境 ─▶ L1 数据库 ─▶ L2 应用/门户 ─┬─▶ L3 n8n 阶段一
                                                 └─▶ L4 备份演练 ─▶ L5 质量门 ─▶ L6 就绪包
                                                                              │
（域名到位后另起一条线） T01 ECS → T02 OSS → T03 RAM → T04 域名+ICP → T08~T10 上云 → T11~T16 上线
```

- 公网线与本地线**互不阻塞**：本地阶段全部产出在切换到云端时直接复用。
- ICP 审核（5–10 工作日）不在本地关键路径上。

## 3. E0：工程基线（已完成）

| ID | 任务 | 产出 | DoD | 状态 |
|---|---|---|---|---|
| E0-01 | 双站 v2.1 总册 | `docs/00-总册/...-v2.1.md` | 12 章 + 16 步 + 验收 + 差异迁移 | DONE |
| E0-02 | 架构宪章与任务账本 | `CLAUDE.md`、`TASK_STATE.md` | 五红线 + T01–T16 状态 | DONE |
| E0-03 | 治理文档更新 | 章程/范围/WBS/风险/ADR-0007~0009 | 双站口径一致 | DONE |
| E0-04 | 数据库 01–09 | `deploy/postgres/initdb/` | 双库四 Schema + 触发器 + 索引授权 | CODE_READY |
| E0-05 | 六容器编排 | `docker-compose.yml` | 硬限流 + 三网络 + `sites/` 挂载 | CODE_READY |
| E0-06 | 双域网关 | `deploy/caddy/Caddyfile` | 双主域 + `/internal` + `/lab` + 日志 | CODE_READY |
| E0-07 | CLI 扩展 | `capital.py`/`exporters.py`/`site_sync.py` | 投研读写 + 脱敏导出 + 4 命令 | CODE_READY |
| E0-08 | 静态双站门户 | `sites/mobocapital`、`sites/mobohome` | 五大栏目 / 人生四篇章 | CODE_READY |
| E0-09 | 自动化资产 | `workflows/`（模板 + 提示词 + 节点） | 工作流 #1/#2/#3 可导入 | CODE_READY |
| E0-10 | 运维与灾备 | 备份/灾备/演练/巡检/bootstrap | 脚本 `bash -n` 通过 | CODE_READY |
| E0-11 | 文档体系 | `docs/01~07` | 字典/运维/合规/原始资料齐备 | CODE_READY |
| E0-12 | 测试与沙盒 | `tests/`、`seeds/`、CLI 单测 | 可在有 Docker/Python 的机器执行 | CODE_READY |

## 4. 一：云资源采购与备案（T01–T04）

| ID | 任务 | 产出 / DoD | 依赖 | 状态 |
|---|---|---|---|---|
| T01 | 核验优惠购买 2C4G（杭州，Ubuntu 24.04，≥3 个月或 3 年） | 公网 IP；SSH 密钥登录成功 | — | BLOCKED（账号/预算待定） |
| T02 | 同地域开通 OSS，创建公开/私有双 Bucket | 双 Bucket；私有库阻止公共访问 | T01 | 未开始 |
| T03 | 创建 RAM 子账号（最小权限）、预算/流量/余额 30 元熔断 | 告警生效；AK/SK 只存密码管理器 | T02 | 未开始 |
| T04 | 注册/确认双主域，实名并提交个人 ICP | 备案订单进入管局审核；等待期并行 T05–T10 | T01 | BLOCKED（域名待确认） |

## 5. 二：宿主机加固与 OSS 防护（T05–T07）

| ID | 任务 | 产出 / DoD | 依赖 | 状态 |
|---|---|---|---|---|
| T05 | 4GB Swap、`vm.swappiness=10`、安装 Docker/Compose | `free -m` 显示 4096MB Swap | T01 | CODE_READY |
| T06 | 目录树 + `.env`(600) + 卷权限 | `stat -c "%a" .env` = 600；Caddy/思源卷 UID 1000 | T05 | CODE_READY |
| T07 | 运行 `oss_guard_setup.py` | 4 条生命周期 Enabled；公开桶禁止空 Referer | T03 | CODE_READY |

## 6. 三：数据库与全栈启动（T08–T10）

| ID | 任务 | 产出 / DoD | 依赖 | 状态 |
|---|---|---|---|---|
| T08 | 注入 01–09 SQL，验证双库隔离与 `capital` 域 | `user_mobobrain` 连 `db_archive` 被拒；`capital.*` 就位 | T06 | CODE_READY |
| T09 | 落盘 CLI/看板/门户/工作流/提示词 | 脚本可执行；门户可打开 | T06 | CODE_READY |
| T10 | `docker compose up -d --build` + `tests/sql/smoke.sql` | 六容器 healthy；总内存 < 1.55GB；时间线与 NAV 触发器生效 | T08/T09 | CODE_READY |

## 7. 四：网关、n8n 与灾备（T11–T13）

| ID | 任务 | 产出 / DoD | 依赖 | 状态 |
|---|---|---|---|---|
| T11 | 双域 DNS + Caddy HTTPS | 双主域绿锁；`/internal/*` 未认证 401；`/lab` 跳转正常 | T04/T10 | CODE_READY |
| T12 | 导入 n8n 工作流 #1/#2，绑定 DB/LLM/思源/微信/X 凭证 | 手动投递→入库→思源母本；四端 JSON 入库 `PENDING_REVIEW` | T10/T11 | CODE_READY（凭证待提供） |
| T13 | 手动首次 Restic 备份，离线封存 `.env` 与恢复脚本 | `restic snapshots` 有快照；密码管理器完成备份 | T10 | CODE_READY |

## 8. 五：监控、演练与验收（T14–T16）

| ID | 任务 | 产出 / DoD | 依赖 | 状态 |
|---|---|---|---|---|
| T14 | 监控告警 + `mobo_watchdog.sh` 巡检 + 证书提醒 | 断网/容器退出/磁盘 80%/NAV 黄红区 5 分钟内告警 | T13 | CODE_READY |
| T15 | 恢复演练（`restore-drill.sh` + `disaster-recovery.sh --dry-run`） | 核心表记录数一致；实测 RTO 记录在案 | T13 | READY |
| T16 | 验收清单、成本对账、密钥清单、交接 runbook | 验收全绿；首年支出 ≤ 2,400；交接完成 | T14/T15 | 未开始 |

## 9. 依赖与阻塞

| 阻塞项 | 影响 | Owner | 解除条件 |
|---|---|---|---|
| 域名与 ICP | T04/T11 | 莫伯 | 双主域注册 + 备案通过 |
| 阿里云账号与预算 | T01 起 | 莫伯 | 账号可下单 |
| LLM/Embedding API | T07 采集评分、T12 合成 | 莫伯 | 提供 Base URL/Key/模型 |
| 微信开放平台 / X API | T12 阶段二 | 莫伯 | AppID/Secret、OAuth 凭证 |
| Docker / Python 环境 | 所有"待验证"项 | 莫伯 | 在有 Docker 的机器跑 `smoke.sql` + `pytest` |

## 10. 每周检查

- [ ] 本周完成任务与工时（对照 `TASK_STATE.md`）
- [ ] 阻塞项与解除计划
- [ ] 风险登记更新（新增风险即时登记）
- [ ] 成本台账更新（LLM 与 OSS 月度对账）
- [ ] 文档/ADR 更新（架构变更必须先写 ADR）
- [ ] 备份/恢复演练（到周期则必须做）
- [ ] 脱敏审计（`pytest services/mobo-cli/tests/test_exporters.py`）
