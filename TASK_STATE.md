# TASK_STATE.md — 莫伯双站系统（MoBoCapital & MoBoHome）多智能体交接账本

- **账本版本**：v2.1（Dual-Site Full-Stack Edition）
- **最后更新**：2026-10-21
- **当前阶段**：双站工程基线已在仓库完成（文档 / 数据库 / 编排 / 网关 / CLI / 看板 / 门户 / 工作流资产），等待云端资源与真实环境联调
- **状态口径**：`DONE` 已完成并验证｜`CODE_READY` 代码已交付待环境验证｜`READY` 方案就绪待执行｜`BLOCKED` 被外部条件阻塞

## 1. 16 步原子任务矩阵（T01–T16）

| 任务 | 阶段 | 任务与交付物 | 负责 | 状态 | 验收命令 / 判定标准 |
|---|---|---|---|---|---|
| T01 | 一 云底座 | 阿里云 2C4G ECS（杭州）、同地域双 OSS 桶、30 元余额熔断、双域名与 ICP 提交 | 莫伯 | BLOCKED | `ping mobocapital.com` 与 `ping mobohome.com` 正常解析；备案进入管局审核 |
| T02 | 一 云底座 | 宿主机 4GB Swap、`vm.swappiness=10`、目录树初始化 | 运维 | CODE_READY | `free -m` 显示 Swap≈4095MB；`/opt/mobo-stack` 目录树就位 |
| T03 | 一 云底座 | 生产 `.env` 生成与 `chmod 600` 锁定 | 运维 | CODE_READY | `stat -c "%a" /opt/mobo-stack/.env` 输出 600 |
| T04 | 一 云底座 | `oss_guard_setup.py` 注入冷沉降与防盗链 | 工具链 | CODE_READY | 控制台 4 条生命周期 Enabled；公开桶禁止空 Referer |
| T05 | 二 双库内核 | 注入 `01-init-dual-db.sql`，验证跨库访问拒绝 | 架构 | CODE_READY | `user_mobobrain` 连 `db_archive` 返回拒绝 |
| T06 | 二 双库内核 | 注入 `02/03`（莫伯之家表与触发器） | 架构 | CODE_READY | 插入 `fitness_workouts` 自动同步到 `timeline_events` |
| T07 | 二 双库内核 | 注入 `04–07`（intel 采集域 + capital 投研域 + 终端） | 架构 | CODE_READY | 平仓一笔 `trade_reviews` 自动更新 `portfolio_nav_ledger` 与回撤熔断状态 |
| T08 | 三 前端与看板 | `archive-dashboard` 构建与内存验证 | 前端 | CODE_READY | 容器常驻 < 180MB；`/\_stcore/health` 200 |
| T09 | 三 前端与看板 | 部署 `sites/mobocapital/index.html` | 前端 | CODE_READY | 五大栏目与三级权限切换流畅；`/data/public-data.json` 可访问 |
| T10 | 三 前端与看板 | 部署 `sites/mobohome/index.html` | 前端 | CODE_READY | 人生篇章过滤、影像画廊与藏书馆渲染正常 |
| T11 | 三 前端与看板 | `mobo-cli` 投研录入 + `macro_iv_collector.py` + 宿主机 Cron | 工具链 | CODE_READY | `mobo-cli export-site` 产出公域与 internal 数据包；`terminal-snapshot.json` 刷新 |
| T12 | 三 前端与看板 | 公私域 JSON 物理脱敏审计 | 工具链 | CODE_READY | `pytest services/mobo-cli/tests/test_exporters.py` 通过；`audit_payload().ok == True` |
| T13 | 四 网关与发布 | 部署思源与 n8n，导入工作流 #1 / #2 | 工具链 | CODE_READY | Webhook 触发后 `capital_publications` 正常入库（`PENDING_REVIEW`） |
| T14 | 四 网关与发布 | Caddy 双域路由与 `/internal/*` BasicAuth | 架构 | CODE_READY | 未授权访问 `/internal/*` 返回 401；`caddy validate` 通过 |
| T15 | 四 网关与发布 | `mobo-restic-backup` 与每日 03:00 加密备份 | 运维 | CODE_READY | `restic snapshots` 可见最新双库快照；`restore-drill.sh` 对账一致 |
| T16 | 五 封版 | `disaster-recovery.sh --dry-run` 演练、内存终验、验收与交接 | 运维 | READY | 全栈总内存 < 1.55GB，六容器 healthy；验收清单全绿 |

## 2. 最新增量交付物（2026-10-21 批次）

| 类别 | 交付物 | 路径 |
|---|---|---|
| 规划 | 双站 v2.1 总册、生产级落地附录、架构宪章、16 步账本 | `docs/00-总册/`、根目录 `CLAUDE.md` / `TASK_STATE.md` |
| 数据库 | `capital` 投研域三脚本（05–07）、索引授权（08）、`updated_at`（09） | `deploy/postgres/initdb/` |
| 编排 | 六容器硬限流、三网络、`sites/` 挂载、n8n 静态目录 | `docker-compose.yml` |
| 网关 | 双主域 + `/internal` + `/lab` 跳转 + 安全头 + JSON 日志 | `deploy/caddy/Caddyfile` |
| 应用 | `exporters.py` 脱敏、`capital.py` 投研读写、`site_sync.py` 导出、4 个新 CLI 命令 | `services/mobo-cli/mobo_cli/` |
| 前端 | 莫伯资本门户、莫伯之家门户 | `sites/mobocapital/`、`sites/mobohome/` |
| 自动化 | 1+3 合成提示词、微信草稿箱模板、X 串推 Code 节点 | `workflows/` |
| 运维 | 巡检哨兵、bootstrap 落盘脚本、docx 生成器 | `deploy/scripts/`、`tools/doc-builder/` |

## 3. 智能体唤醒指令速查

```bash
# ① 数据库注入与容器编排（T05–T07、T14）
cd /opt/mobo-stack && docker compose up -d postgres && \
docker compose exec -T postgres psql -U postgres -d db_archive -f /docker-entrypoint-initdb.d/02-archive-schema.sql

# ② CLI 联调与脱敏审计（T11、T12）
cd /opt/mobo-stack && python3 -m mobo_cli export-site --site all && \
python3 -c "import json;d=json.load(open('sites/mobocapital/data/public-data.json'));print('keys',list(d))"

# ③ 前端与数据源绑定（T09、T10）
# 编辑 sites/mobocapital/index.html 与 sites/mobohome/index.html 的数据拉取逻辑
```

## 4. 阻塞项

| 阻塞 | 影响 | 解除条件 |
|---|---|---|
| 域名与 ICP | T01/T11/T14 | 备案通过 |
| 阿里云账号与预算 | T01 | 账号可下单 |
| LLM / Embedding 凭证 | T07/T11/T13 | 提供 Base URL、Key、模型 |
| 微信开放平台与 X API 凭证 | T13 阶段二 | 提供 AppID/Secret 与 OAuth |
| Docker / Python 本地环境 | 所有"待验证"项 | 在有 Docker 的机器执行 `tests/sql/smoke.sql` 与 `pytest` |
