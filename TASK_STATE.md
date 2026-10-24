# TASK_STATE.md — 莫伯双站系统（MoBoCapital & MoBoHome）多智能体交接账本

- **账本版本**：v2.1.2（Local-First Edition）
- **最后更新**：2026-10-24
- **当前模式**：**本地优先（ADR-0010）** —— 双主域未注册、ICP 未启动，**不进入公网部署**；全部工作在本地完成，云端动作挂起
- **状态口径**：`DONE` 已完成并验证｜`CODE_READY` 交付物已就位、待环境验证｜`READY` 方案就绪待执行｜`BLOCKED` 被外部条件阻塞｜`暂缓` 本阶段主动挂起
- **文档**：总册 v2.1 / ADR / docs/03 / CLAUDE / v5 / 整合总览已自金库「项目文档」恢复入库；执行记录见 [`docs/07-原始资料/执行记录-2026-10-24/`](docs/07-原始资料/执行记录-2026-10-24/)；GitHub Pages 已开（`main` `/`）

## 0. 本地阶段任务（L0–L6）

  任务   内容   验收   状态  
 --- --- --- --- 
  L0   本地环境与编排基线   **WSL2 内 Docker 29.1.3 + Compose 2.40.3**；六容器 healthy；命名卷 + 镜像加速就绪   **完成**  
  L1   数据库内核落地验证   01–09 SQL 首次初始化；`tests/sql/smoke.sql` **9 组全绿**（含 capital 10 表+4 视图、NAV 触发器、跨库拒绝）   **完成**  
  L2   应用与门户本地跑通   **CLI 闭环已通**；资本 JSON+editorial；之家公域：叙事 5 + 图库 5（PUBLIC）+ 书单 8（tag=public_portal），无沙盒泄漏；看板 database   **完成**  
  L3   n8n 本地联调   三工作流已导入且未激活；#3 发布链 disabled。无 LLM 时用 `tools/local/stage1_pending_stub.sql` 写入 `PENDING_REVIEW`（现库 2 条待审 / 2 条已发布）；真 LLM 阶段一仍待 Key   **部分完成**  
  L4   本地备份与恢复演练   本地仓库 `/backup/restic-local` 快照 `43547103`；演练库与生产库核心表计数一致；RTO 7 秒；演练库已删除   **完成**（2026-10-24）  
  L5   质量门   单测 52 项通过；4 个工作流 JSON 可解析；git 跟踪的 16 个 shell `bash -n` 通过；`smoke.sql` 9 组通过；六容器约 553MiB，均未超各自限额   **部分通过**（工作区因文档搬家与工作流禁用而非干净）  
  L6   公网就绪包   清单已入库 [`docs/07-原始资料/执行记录-2026-10-24/公网就绪包清单-2026-10-24.md`](docs/07-原始资料/执行记录-2026-10-24/公网就绪包清单-2026-10-24.md)；域名与 ICP 仍阻塞；工程仓已 Pages 发布前端   **部分完成**  
  DOC  文档真源恢复   总册/ADR/docs03/CLAUDE/v5/整合总览自金库恢复；07 执行记录同步；docx 归档说明   **完成**（2026-10-24）  


### D0（2026-10-21）已达成

  项   结果  
 --- --- 
  运行时   WSL2 内 Docker Engine（免 Windows 管理员权限），见 [ADR-0011](docs/01-项目治理/决策记录/ADR-0011-WSL2作为本地开发运行时.md)  
  六容器   caddy / postgres / siyuan / n8n / dashboard / restic **全部 healthy**  
  网关入口   公开站 200；`lab`/`kb`/`n8n`/`admin` 未认证 401、认证 200；`/internal/*` 未认证 401  
  数据库   冒烟 9 组全绿；双库四 Schema（intel / capital / n8n / archive）  
  内存   合计约 **636 MiB**（限额合计 1.84GB），远低于 1.55GB 常驻红线  
  当日修复的 8 个真问题   见 [开发部署任务执行时间线](docs/01-项目治理/开发部署任务执行时间线.md) §2 D0 表  
  入口   `http://localhost/`（莫伯资本）、`http://mobohome.localhost/`（莫伯之家）、`http://lab.localhost/`、`http://kb.localhost/`、`http://n8n.localhost/`、`http://admin.localhost/`；BasicAuth `mobo / mobo-local`  

> 详细步骤见 [`docs/05-运维与灾备/本地开发与部署.md`](docs/05-运维与灾备/本地开发与部署.md)；
> 逐条验收见 [`docs/05-运维与灾备/本地阶段自检清单.md`](docs/05-运维与灾备/本地阶段自检清单.md)；
> **执行时间线**见 [`docs/01-项目治理/开发部署任务执行时间线.md`](docs/01-项目治理/开发部署任务执行时间线.md)。

## 1. 16 步原子任务矩阵（T01–T16）

  任务   阶段   任务与交付物   负责   状态   验收命令 / 判定标准  
 --- --- --- --- --- --- 
  T01   一 云底座   阿里云 2C4G ECS、同地域双 OSS 桶、30 元余额熔断   莫伯   **暂缓**   域名/云资源到位后恢复  
  T02   一 云底座   双 OSS 桶与 4 条生命周期规则   莫伯   **暂缓**   控制台 4 条规则 Enabled  
  T03   一 云底座   RAM 子账号、预算/流量/余额告警   莫伯   **暂缓**   告警生效；AK/SK 只存密码管理器  
  T04   一 云底座   双主域注册、实名与个人 ICP   莫伯   **BLOCKED**   域名未注册；恢复条件见 ADR-0010  
  T05   二 宿主机   4GB Swap、`vm.swappiness=10`、目录树   运维   暂缓（本地等价物 L0）   `free -m` 显示 Swap≈4095MB  
  T06   二 宿主机   生产 `.env`(600) 与卷权限   运维   CODE_READY   `stat -c "%a" .env` = 600  
  T07   二 宿主机   `oss_guard_setup.py` 冷沉降与防盗链   工具链   CODE_READY（本地 DRY_RUN）   输出 `[OK] Lifecycle & Referer Guard Applied`  
  T08   二 双库内核   注入 01–09，验证双库隔离与 `capital` 域   架构   **L1 待验证**   `user_mobobrain` 连 `db_archive` 被拒；`capital.*` 就位  
  T09   三 前端与看板   落盘 CLI/看板/门户/工作流/提示词   前端   CODE_READY   脚本可执行；门户可打开  
  T10   三 前端与看板   全栈启动 + `smoke.sql` + 内存实测   架构   **L1/L5 待验证**   六容器 healthy；总内存 < 1.55GB  
  T11   四 网关与发布   双域 DNS + Caddy HTTPS   架构   **暂缓**（本地用 `localhost` 验路由）   未授权 `/internal/*` 返回 401  
  T12   四 网关与发布   导入 n8n 工作流并绑定凭证   工具链   **L3 待验证**（发布阶段禁用）   合成结果入库 `PENDING_REVIEW`  
  T13   四 网关与发布   首次 Restic 备份   运维   **L4 待验证**（本地仓库）   `restic snapshots` 可见快照  
  T14   五 封版   监控告警 + 巡检哨兵 + 证书提醒   运维   CODE_READY（本地可跑哨兵）   断网/磁盘 80%/NAV 黄红区 5 分钟内告警  
  T15   五 封版   恢复演练（`restore-drill.sh` + `--dry-run`）   运维   **L4 待验证**   核心表记录数一致；实测 RTO 记录在案  
  T16   五 封版   验收清单、成本对账、交接 runbook   运维   READY   验收全绿；首年支出 ≤ 2,400  

## 2. 最新增量交付物（2026-10-21 批次）

  类别   交付物   路径  
 --- --- --- 
  规划   双站 v2.1 总册、生产级落地附录、架构宪章、16 步账本、本地优先 ADR   `docs/00-总册/`、`docs/01-项目治理/决策记录/ADR-0010*`、根目录 `CLAUDE.md` / `TASK_STATE.md`  
  本地   本地开发与部署指南（L0–L6 全流程与排障）   `docs/05-运维与灾备/本地开发与部署.md`  
  数据库   `capital` 投研域三脚本（05–07）、索引授权（08）、`updated_at`（09）   `deploy/postgres/initdb/`  
  编排   六容器硬限流、三网络、`sites/` 挂载、n8n 静态目录   `docker-compose.yml`  
  网关   双主域 + `/internal` + `/lab` 跳转 + 安全头 + JSON 日志   `deploy/caddy/Caddyfile`  
  应用   `exporters.py` 脱敏、`capital.py` 投研读写、`site_sync.py` 导出、4 个新 CLI 命令   `services/mobo-cli/mobo_cli/`  
  前端   莫伯资本门户、莫伯之家门户   `sites/mobocapital/`、`sites/mobohome/`  
  自动化   1+3 合成提示词、微信草稿箱模板、X 串推 Code 节点、工作流 #1/#2/#3   `workflows/`  
  UI   莫伯系统控制台（admin 域）：KPI / 入口矩阵 / 运行时 / 投研风控 / 流水线 / 档案 / 任务 / 运维 / 预算 / 红线   `services/console/`  
  运维   巡检哨兵、bootstrap 落盘脚本、docx 生成器   `deploy/scripts/`、`tools/wsl/`（状态收集 + 质量门）、`tools/doc-builder/`  

## 3. 智能体唤醒指令速查

```bash
# ① 数据库注入与容器编排（T08、T10 的本地等价物）
cd /opt/mobo-stack && docker compose --env-file .env.local up -d postgres && \
docker compose --env-file .env.local exec -T postgres psql -U postgres -d db_archive \
  -f /docker-entrypoint-initdb.d/02-archive-schema.sql

# ② CLI 联调与脱敏审计（T11、T12）
cd /opt/mobo-stack && python3 -m mobo_cli export-site --site all && \
grep -c private_blotter_oss_key sites/mobocapital/data/public-data.json   # 期望 0

# ③ 前端与数据源绑定（T09、T10）
# 编辑 sites/mobocapital/index.html 与 sites/mobohome/index.html 的数据拉取逻辑
```

## 3.1 内容原料整理（本地，不阻塞 L0–L6）

| 任务 | 内容 | 状态 |
|---|---|---|
| C0 | 盘点 + 站点叙事同步 | **完成**（见 `docs/07-原始资料/`） |
| C1 | 《原件保全与双站同步方案 v5》拍板（原件不转换 / 02–07 同步 / 01 本地 / 私有原件落盘） | **READY** · v5 方案与仪表板已完成，待莫伯确认 |
| C2 | V0 密钥迁出 + V1 冻结清单与 SHA-256 | **完成**（本地隔离形态）· 7 处 P0 + 精化命中 15 件隔离未复制；`MANIFEST.csv` 44,817 行含 SHA-256 |
| C3 | V2 金库复制（不转换）+ V3 两个归档只读保留 | **完成** · `MoBo-Content-Vault-v5` 27,035 文件 / 9,532,495,945 B / **0 错误**；MBrain 1,391、Goals 24,136 行登记；逐一存在性核对 0 缺失 |
| C4 | V4 同步清单（Goals 02–07，不含 01）+ V5 展示层衍生 | **完成** · `SYNC-FILES.txt` 13,492 行（0 影视库/0 MBrain/0 视频/0 音频/0 Git）；80-Site JSON 占位 + 13,492 OSS key 计划；**WebP 缩略图/封面 2,542 张已生成**（= 2,719 规划 key 按 SHA 去重，35.9 MB，0 超限/0 失败/0 不可解码，便携 sharp+pdfjs 方案） |
| C5 | V6 上传 + V7 冒烟/回滚/HITL 验收 | 未开始 · 前置：服务器/域名/ICP/HTTPS/OSS；7 处 P0 凭据待莫伯轮换 |

> **V5 执行实测数字（2026-10-23 11:51）**：全量 44,817 文件 / 35.172 GiB；六分片对账精确闭合。总账 `E:\01-文档资料\报告与规划\MoBo-Content-Vault-v5\00-INDEX\`（`COUNTS.json` / `VERIFY.json` 全 0 错误可见性核对通过）。**增补（12:44）：⚙4 缩略图完成——2,542 张 WebP / 37,625,230 B（0.035 GiB）落 `80-Site-Release/shared/`，27,035 副本 0 缺失 0 冲突，密钥 0 命中**。执行报告：[`莫伯双站V5执行报告-2026-10-23.md`](docs/07-原始资料/莫伯双站V5执行报告-2026-10-23.md) · 仪表板：[`莫伯双站V5执行仪表板-2026-10-23.html`](docs/07-原始资料/莫伯双站V5执行仪表板-2026-10-23.html) · 新会话交接上下文：[`莫伯双站V5-新会话交接-2026-10-23.md`](docs/07-原始资料/莫伯双站V5-新会话交接-2026-10-23.md)

方案正文：[`v3 盘点/金库`](docs/07-原始资料/莫伯双站内容资产双维分析与整合方案-v3.md) · [`v5 原件保全/同步`](docs/07-原始资料/莫伯双站原件保全与双站同步方案-v5.md) · 仪表板：[`莫伯双站内容资产双维盘点仪表板.html`](docs/07-原始资料/莫伯双站内容资产双维盘点仪表板.html)

## 4. 阻塞项

  阻塞   影响   解除条件  
 --- --- --- 
  双主域未注册   T04 / T11   注册并实名，完成主体一致性核对  
  ICP 未启动   T11   域名到手后提交个人备案  
  阿里云账号与预算   T01–T03   账号可下单（本地阶段不阻塞）  
  LLM / Embedding 凭证   T07 采集评分、T12 合成   提供 Base URL、Key、模型（本地可用桩）  
  微信开放平台与 X API 凭证   T12 阶段二   后期再接；当前只产出 JSON 草稿  
  本机 Docker / Python   所有"待验证"项   在本地按 `docs/05-运维与灾备/本地开发与部署.md` 执行 L0–L5  
