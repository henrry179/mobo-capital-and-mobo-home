# 双站规划/规格文档主索引

> 生成：2026-10-24 · 计划「双站规划文档盘点与整合总览」Phase 1–2  
> 范围：`莫伯双站系统` + `MoBo-Content-Vault-v5`（规划/规格类）  
> 汇集方式：**仅路径索引，不复制原文**  
> 分层：`CANON` 规范源 · `DERIVED` 派生/工具说明 · `ARCHIVE` 历史/归档 · `MIRROR` Vault 镜像（不精读） · `DEFER` 降级引用  
> 站点标签：`Capital` / `Home` / `Console` / `Shared`

相关总览：[`../双站规划文档整合总览.md`](../双站规划文档整合总览.md)

---

## A. 规范源 — 工程根与宪章

| 路径 | 类型 | 站点 | 分层 | 备注 |
|---|---|---|---|---|
| `莫伯双站系统/CLAUDE.md` | 架构宪章 | Shared | CANON | 五条红线；智能体共享记忆 |
| `莫伯双站系统/TASK_STATE.md` | 任务账本 | Shared | CANON | L0–L6 + T01–T16 + 内容 C0–C5 |
| `莫伯双站系统/README.md` | 项目总览 | Shared | CANON | 目录导航与当前本地优先状态 |

---

## B. 规范源 — docs/00 总册

| 路径 | 类型 | 站点 | 分层 | 备注 |
|---|---|---|---|---|
| `docs/00-总册/莫伯双站系统全栈架构与部署总册-v2.1.md` | 总册 | Shared | CANON | **主规格**；双站+管道+部署 |
| `docs/00-总册/生产级落地附录-v2.1.md` | 附录 | Shared | CANON | 生产落地细节 |
| `docs/00-总册/术语表.md` | 术语 | Shared | CANON | |
| `docs/00-总册/文档修订记录.md` | 修订 | Shared | CANON | |
| `docs/00-总册/归档/莫伯双站系统全栈架构与部署总册-v1.1.md` | 总册归档 | Shared | ARCHIVE | 对照用；勿当基线 |

---

## C. 规范源 — docs/01 项目治理与 ADR

| 路径 | 类型 | 站点 | 分层 | 备注 |
|---|---|---|---|---|
| `docs/01-项目治理/项目章程.md` | 章程 | Shared | CANON | |
| `docs/01-项目治理/范围与边界.md` | 范围 | Shared | CANON | 入口拓扑、MVP/不做 |
| `docs/01-项目治理/里程碑与WBS.md` | WBS | Shared | CANON | |
| `docs/01-项目治理/开发部署任务执行时间线.md` | 时间线 | Shared | CANON | D0 实测与排障 |
| `docs/01-项目治理/风险登记册.md` | 风险 | Shared | CANON | |
| `docs/01-项目治理/决策记录/README.md` | ADR 索引 | Shared | CANON | |
| `docs/01-项目治理/决策记录/ADR-0001-单机双库与Schema隔离.md` | ADR | Shared | CANON | 单实例双库 |
| `docs/01-项目治理/决策记录/ADR-0002-域名拓扑与公开静态站.md` | ADR | Shared/Capital | CANON | **部分过时**：仍写单主域+Astro；被 0007 修正 |
| `docs/01-项目治理/决策记录/ADR-0003-n8n子域与数据Schema.md` | ADR | Shared | CANON | |
| `docs/01-项目治理/决策记录/ADR-0004-备份与灾备.md` | ADR | Shared | CANON | |
| `docs/01-项目治理/决策记录/ADR-0005-中文检索与向量维度.md` | ADR | Shared | CANON | 维度待最终确认 |
| `docs/01-项目治理/决策记录/ADR-0006-安全与鉴权基线.md` | ADR | Shared | CANON | |
| `docs/01-项目治理/决策记录/ADR-0007-双主域拓扑与静态门户三级可见性.md` | ADR | Capital/Home | CANON | 双主域+三级可见性 |
| `docs/01-项目治理/决策记录/ADR-0008-db_mobobrain增设capital-schema.md` | ADR | Capital | CANON | |
| `docs/01-项目治理/决策记录/ADR-0009-公私域物理脱敏与HITL发布闸门.md` | ADR | Capital/Home | CANON | |
| `docs/01-项目治理/决策记录/ADR-0010-本地优先开发暂不进入公网部署.md` | ADR | Shared | CANON | 当前执行模式 |
| `docs/01-项目治理/决策记录/ADR-0011-WSL2作为本地开发运行时.md` | ADR | Shared | CANON | 本地 Docker 运行时 |

---

## D. 规范源 — docs/02 需求与验收

| 路径 | 类型 | 站点 | 分层 | 备注 |
|---|---|---|---|---|
| `docs/02-需求与验收/需求规格说明书.md` | 需求 | Shared | CANON | FR-A/B/O；A 站部分表述仍偏 v1「专栏」 |
| `docs/02-需求与验收/非功能需求.md` | NFR | Shared | CANON | |
| `docs/02-需求与验收/测试计划.md` | 测试 | Shared | CANON | |
| `docs/02-需求与验收/验收标准与DoD.md` | DoD | Shared | CANON | |

---

## E. 规范源 — docs/03–04 架构与数据库

| 路径 | 类型 | 站点 | 分层 | 备注 |
|---|---|---|---|---|
| `docs/03-架构设计/总体架构.md` | 架构 | Shared | CANON | |
| `docs/03-架构设计/数据架构.md` | 架构 | Shared | CANON | |
| `docs/03-架构设计/网络与安全架构.md` | 架构 | Shared | CANON | |
| `docs/03-架构设计/部署架构.md` | 架构 | Shared | CANON | |
| `docs/04-数据库设计/README.md` | 索引 | Shared | CANON | |
| `docs/04-数据库设计/网站A数据字典.md` | 数据字典 | Capital | CANON | intel 域 |
| `docs/04-数据库设计/网站B数据字典.md` | 数据字典 | Home | CANON | archive 域 |
| `docs/04-数据库设计/莫伯资本数据字典.md` | 数据字典 | Capital | CANON | capital 域 |
| `docs/04-数据库设计/触发器与视图.md` | 数据 | Shared | CANON | |
| `docs/04-数据库设计/迁移与备份策略.md` | 数据 | Shared | CANON | |

---

## F. 规范源 — docs/05–06 运维与合规

| 路径 | 类型 | 站点 | 分层 | 备注 |
|---|---|---|---|---|
| `docs/05-运维与灾备/本地开发与部署.md` | 运维 | Shared | CANON | L0–L6 主入口 |
| `docs/05-运维与灾备/本地阶段自检清单.md` | 验收 | Shared | CANON | |
| `docs/05-运维与灾备/部署手册.md` | 运维 | Shared | CANON | 公网阶段 |
| `docs/05-运维与灾备/日常运维.md` | 运维 | Shared | CANON | |
| `docs/05-运维与灾备/监控告警.md` | 运维 | Shared | CANON | |
| `docs/05-运维与灾备/故障排查.md` | 运维 | Shared | CANON | |
| `docs/05-运维与灾备/备份与恢复演练.md` | 灾备 | Shared | CANON | |
| `docs/05-运维与灾备/安全基线.md` | 安全 | Shared | CANON | |
| `docs/05-运维与灾备/证据/README.md` | 证据 | Shared | DERIVED | |
| `docs/06-合规与成本/证券与自媒体合规.md` | 合规 | Capital | CANON | |
| `docs/06-合规与成本/隐私与数据分类.md` | 合规 | Shared | CANON | |
| `docs/06-合规与成本/ICP与域名材料清单.md` | 合规 | Shared | CANON | BLOCKED 相关 |
| `docs/06-合规与成本/密钥与凭据清单.md` | 合规 | Shared | CANON | 无真实值 |
| `docs/06-合规与成本/成本台账.md` | 成本 | Shared | CANON | ≤2400 红线 |

---

## G. 内容治理方案链 — docs/07（派生规格，非部署基线）

| 路径 | 类型 | 站点 | 分层 | 备注 |
|---|---|---|---|---|
| `docs/07-原始资料/README.md` | 目录说明 | Shared | CANON* | *本目录内的「权威导航」 |
| `docs/07-原始资料/内容原料仓完整整理方案-v1.md` | 方案 | Shared | ARCHIVE | 框架版；被 v3 取代 |
| `docs/07-原始资料/内容原料仓深度整合与整理方案-v2.md` | 方案 | Shared | ARCHIVE | P0 凭据清单仍有效 |
| `docs/07-原始资料/《莫伯双站-内容原料深度整合与整理方案-v2》.docx` | 方案 | Shared | ARCHIVE | v2 docx |
| `docs/07-原始资料/莫伯双站内容资产双维分析与整合方案-v3.md` | 方案 | Shared | CANON* | 盘点/金库基线 |
| `docs/07-原始资料/莫伯双站上线同步包与内容整理方案-v4.md` | 方案 | Shared | ARCHIVE | 转换策略已废止 |
| `docs/07-原始资料/莫伯双站原件保全与双站同步方案-v5.md` | 方案 | Shared | CANON* | **内容同步当前基线** |
| `docs/07-原始资料/内容资产盘点与归库映射-2026-10-21.md` | 盘点 | Shared | ARCHIVE | 数字以 v3/v5 为准 |
| `docs/07-原始资料/站点内容同步记录-2026-10-21.md` | 同步记录 | Capital/Home | DERIVED | **唯一明确记录前端吸收来源** |
| `docs/07-原始资料/莫伯双站V5执行报告-2026-10-23.md` | 执行报告 | Shared | DERIVED | 实测数字 |
| `docs/07-原始资料/莫伯双站V5-新会话交接-2026-10-23.md` | 交接 | Shared | DERIVED | |
| `docs/07-原始资料/原始方案/莫伯双站系统全栈架构与部署总册.docx` | 原始方案 | Shared | ARCHIVE | v1.0 |
| `docs/07-原始资料/原始方案/MoBoBrain双网站建设方案.docx` | 原始方案 | Shared | ARCHIVE | |
| `docs/07-原始资料/原始方案/阿里云云端多智能体网站平台_部署与运营整合方案.docx` | 扩展路线 | Shared | ARCHIVE | 8C8G；非当前 2C4G 基线 |
| `docs/07-原始资料/外部项目档案/全球宏观财经金融OPC_Hermes_GrokBot_统一项目档案_区分用户与AI.md` | 外部档案 | Shared | DEFER | 背景参考 |
| `docs/07-原始资料/外部项目档案/全球宏观财经金融OPC_Hermes_GrokBot统一项目档案.md` | 外部档案 | Shared | ARCHIVE | 被上一份取代 |

> 另有 HTML 仪表板（非 Markdown）：`莫伯双站内容资产双维盘点仪表板.html`、`莫伯双站V5执行仪表板-2026-10-23.html` — 规划可视化，归 DERIVED。

---

## H. 控制台与工具链说明（派生）

| 路径 | 类型 | 站点 | 分层 | 备注 |
|---|---|---|---|---|
| `services/console/README.md` | UI/控制面规格 | Console | CANON* | 区块、数据流、刷新命令 |
| `services/mobo-cli/README.md` | CLI | Shared | DERIVED | 管道实现说明 |
| `workflows/README.md` | 工作流 | Capital | DERIVED | |
| `workflows/prompts/mobo-capital-synthesis-prompt.md` | 提示词规格 | Capital | DERIVED | 1+3 合成 |
| `tools/wsl/README.md` | 本地运行时 | Shared | DERIVED | |
| `tools/local-preview/README.md` | 预览 | Shared | DERIVED | |
| `tools/vault/README.md` | Vault 工具 | Shared | DERIVED | |
| `migrations/README.md` | 迁移 | Shared | DERIVED | |
| `seeds/README.md` | 种子 | Shared | DERIVED | |
| `tests/README.md` | 测试 | Shared | DERIVED | |

**前端门户**：未发现独立「UI 计划 / 线框」Markdown。门户模块规格散落在总册 §6、ADR-0007、`站点内容同步记录`，实现体为 `sites/mobocapital/index.html`、`sites/mobohome/index.html`（代码非规划文档，索引不列入正文清单）。

---

## I. Vault v5 — 索引与发布层（仓库外）

根：`E:\01-文档资料\报告与规划\MoBo-Content-Vault-v5`

| 路径 | 类型 | 站点 | 分层 | 备注 |
|---|---|---|---|---|
| `00-INDEX/README.md` | 金库总说明 | Shared | CANON* | 分区与三条决定 |
| `00-INDEX/CHANGELOG.md` | 变更 | Shared | DERIVED | |
| `00-INDEX/SECRETS-FOUND.md` | 安全 | Shared | CANON* | P0 凭据登记 |
| `00-INDEX/MANIFEST.csv` | 机读总账 | Shared | DERIVED | 44k+ 行 |
| `00-INDEX/SITE-ROUTING.csv` | 站点路由 | Capital/Home | DERIVED | |
| `00-INDEX/SYNC-FILES.txt` | 同步清单 | Shared | DERIVED | |
| `00-INDEX/LOCAL-ONLY.csv` | 本地只读 | Shared | DERIVED | |
| `00-INDEX/EXCLUDED.csv` | 排除 | Shared | DERIVED | |
| `00-INDEX/DUPLICATES.csv` | 重复 | Shared | DERIVED | |
| `00-INDEX/QUARANTINE.csv` | 隔离 | Shared | DERIVED | |
| `00-INDEX/TYPE-VIEW.csv` | 类型视图 | Shared | DERIVED | |
| `00-INDEX/OSS-KEYS.csv` | OSS Key | Shared | DERIVED | |
| `00-INDEX/COUNTS.json` / `VERIFY.json` | 校验 | Shared | DERIVED | |
| `80-Site-Release/README.md` | 展示层规格 | Capital/Home | CANON* | HITL；缩略图规格 |

**排除（本索引不枚举）**：`80-Site-Release/shared/**` 下 2500+ WebP 二进制；`10-MD/internal/**` 等对工程 docs 的 **MIRROR** 副本。

---

## J. Vault — Goals 战略层（精读子集）

根：`.../70-Archive-Immutable/MoBo-Capital-Goals/`（及工程内 `hermes-migration/henrry-push/MoBo-Capital-Goals/` 同源）

| 路径 | 类型 | 站点 | 分层 | 备注 |
|---|---|---|---|---|
| `README.md` | Goals 总览 | Shared | DERIVED | Peoples 产线说明 |
| `STRUCTURE.md` | 结构 | Shared | DERIVED | |
| `PIPELINE.md` | 产线 | Shared | DERIVED | |
| `CONTRIBUTING.md` | 贡献 | Shared | DEFER | |
| `05-.../武汉未来规划指南和导航/README.md` | 生活规划入口 | Home | DERIVED | |
| `05-.../MoBo生态全景战略总图_2026-10-07.md` | 战略总图 | Shared/Home/Capital | CANON* | 三线融合；门户叙事源 |
| `05-.../武汉中长期发展规划方案_2026-2036_三线融合完整版V2.docx` | 规划 | Home | DEFER | 摘要级；财务细节勿上公域 |
| `05-.../研究驱动型系统性交易_微信公众号矩阵运营战略全书.docx` | 媒体战略 | Capital | DEFER | |
| `05-.../博士论文v2_哲学驱动长周期金融战略框架（扩展版）.docx` | 哲学母本 | Shared | DEFER | |
| `07-MKPlayBooks/README.md` | PlayBooks 入口 | Capital | DEFER | 全文不精读 |
| `01–04、06` 各目录顶层 `README.md` | 产线入口 | Shared | DEFER | 人物库逐人 README **不列入** |

---

## K. 统计摘要

| 桶 | 约计 |
|---|---:|
| 工程 docs Markdown（00–07） | 62 |
| 工程 docs 方案 docx | 4 |
| ADR | 11 + README |
| 根宪章/账本/README | 3 |
| 控制台+工具链 README（规划相关） | ~10 |
| Vault 00-INDEX + 80 README | 15 |
| Goals 战略精读子集 | ~10 |
| **主队列精读（本轮）** | ~55 |
| 降级/镜像/二进制 | 不计入精读 |

---

## L. 冲突与过时标记（索引级）

| ID | 现象 | 以谁为准 |
|---|---|---|
| C1 | ADR-0002 单主域+Astro vs ADR-0007/总册 v2.1 双主域+静态 HTML | **0007 + 总册 v2.1** |
| C2 | 需求 FR-A「公开专栏/文章列表」vs 资本站五大栏目门户 | **总册 §6 + 现网 `sites/`**；需求待修订 |
| C3 | Vault `00-INDEX/README` 写「尚未生成 WebP」vs `80-Site-Release/README`/`TASK_STATE` 称 2542 张已生成 | **80-Site-Release + TASK_STATE / COUNTS.json** |
| C4 | 内容方案 v4 转换 vs v5 原件保全 | **v5** |
| C5 | 工程 docs 规范 vs Vault `10-MD/internal` 镜像 | **工程 docs**；镜像不精读 |
