# ADR-0009：公私域物理脱敏与 HITL 发布闸门

- **状态**：已接受
- **日期**：2026-10-21
- **相关**：ADR-0007（三级可见性）、CLAUDE.md 红线四/红线五

## 背景

v2.1 引入了两个天然高风险的数据通道：

1. **静态数据包通道**：CLI 把数据库内容导出为 JSON，Caddy 直接对外分发。这条通道一旦写错字段，实盘交割单引用、私密影像签名链接就会出现在公网。
2. **内容发布通道**：n8n 工作流 #2 一次 LLM 调用生成四端内容（官网 / 微信公众号 / 雪球 / X），其中境内平台对"荐股、目标价、收益承诺"有明确合规红线。

同时，境内个人投研内容天然带有"证券投资建议"的边界风险，需要可执行的制度而非口头约定。

## 决策

### 一、物理脱敏（数据通道）

1. 脱敏发生在**写盘之前**（`services/mobo-cli/mobo_cli/exporters.py`），不依赖前端隐藏或路径保密。
2. 公域包必须物理删除：`private_blotter_oss_key`、`signed_blotter_url`、`private_attachment_oss_key`、`oss_object_key`、`oss_thumbnail_key`、`signed_url`、任何 `access_key*`/`password`/`secret` 字段。
3. 公域包必须物理剔除：`visibility = 'INTERNAL'` 的记录（莫伯资本）、`is_sensitive = TRUE` 与 `privacy ∈ {PRIVATE, VAULT}` 的记录（莫伯之家）。
4. 写盘前执行 `audit_payload()` 自检，命中违规直接抛错，不产生文件。
5. 全量数据与 OSS 临时签名链接只允许写入 `internal/` 目录，由 Caddy `/internal/*` 的 `basic_auth` 保护；该目录**不得**出现在 `data/` 下。
6. 脱敏规则必须有单元测试（`services/mobo-cli/tests/test_exporters.py`）并在发布前跑通。

### 二、HITL 发布闸门（内容通道）

1. 工作流 #2 阶段一写库状态固定为 `PENDING_REVIEW`，**禁止**直接写 `PUBLISHED`。
2. 状态机：`DRAFT → PENDING_REVIEW → APPROVED → PUBLISHED`（失败为 `FAILED`），每次跃迁写 `intel.ingestion_runs` 审计。
3. 微信/雪球版本由提示词强制脱敏具体买卖点位、强制追加免责声明；X（境外）版本保留结构化论证但同样经人工确认。
4. 微信"直推"仅指推送到**公众号草稿箱**（`cgi-bin/draft/add`），最终群发仍由本人在公众号后台确认。

## 理由

- 把控制点放在唯一可审计的位置：写盘前、发布前。
- 单元测试 + 自检让脱敏规则可回归，避免"改一次提示词就漏一个字段"。
- HITL 让"内容生产自动化"停留在"草稿自动化"，符合个人自媒体与境内合规的现实边界。

## 代价与缓解

| 代价 | 缓解 |
|---|---|
| 每条内容需人工点一次 | 批量审阅模式；只审 PENDING_REVIEW 队列 |
| 脱敏字段清单需随表结构维护 | 清单集中在 `exporters.PRIVATE_FIELDS`；新增表时由单元测试与审计自检拦截 |
| 静态数据包有延迟 | 缓存 60 秒 + Cron 定时导出 |

## 备选方案

- **仅靠前端隐藏敏感字段**：被否。JSON 本身即暴露面，curl 即可读取。
- **工作流直接发布不做人工确认**：被否。境内平台合规风险不可接受，且与红线五冲突。
