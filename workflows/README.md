# n8n 工作流与提示词资产

> 本目录存放可导入 n8n 的工作流**模板**（`*.template.json`）与配套提示词/代码节点资产。模板中的 URL、Key、模型、凭证 ID 均为占位符，导入后必须替换。

## 1. 清单

| 文件 | 作用 | 触发 | 写入 |
|---|---|---|---|
| `workflow-01-rss-to-vault.template.json` | RSS 采集 → SHA-256 去重 → `intel.articles_vault`（`NEW`） | 每 4 小时 | `intel.articles_vault` |
| `workflow-02-score-to-draft.template.json` | 取 `NEW` → LLM 评分 → 回写 `SCORED` / `NEEDS_MANUAL` | 手动 | `intel.articles_vault` |
| `workflow-03-mobocapital-1plus3.template.json` | **1+3 四端同源合成 + HITL 发布**（官网/微信/雪球/X） | Webhook 两阶段 | `capital.capital_publications` |
| `prompts/mobo-capital-synthesis-prompt.md` | 四端合成 System Prompt（境内脱敏 + 免责声明） | — | — |
| `wechat-draft-push.template.json` | 微信 `cgi-bin/draft/add` 请求体模板 | — | — |
| `nodes/x-thread-publish.code.js` | X (Twitter) 链式串推 Code 节点逻辑 | — | — |

## 2. 导入前准备

1. n8n 已能通过 `https://n8n.mobocapital.com/` 登录（BasicAuth + owner 账号）。
2. 创建 PostgreSQL 凭证：Host `postgres`、Port `5432`、Database `db_mobobrain`、User `user_mobobrain`（业务）或 `user_n8n`（n8n 自身 Schema）。
3. 在 `intel.sources` 登记 RSS 源（`feed_url` 唯一）。
4. 创建 LLM 凭证（OpenAI-compatible）；微信与 X 凭证走 n8n Credentials，**不要写进工作流 JSON**。
5. 替换占位符：`REPLACE_WITH_CREDENTIAL_ID`、`REPLACE_WITH_LLM_KEY`、`https://api.example.com/v1/...`、`your-chat-model`、`https://example.com/feed.xml`。
6. 工作流 #3 需额外：注入 `system_prompt`（可从 `prompts/` 读入并作为 Webhook 入参传入）。

## 3. 导入与启用

1. n8n → Workflows → Import from File。
2. 保存后保持 **Inactive**，先 “Execute Workflow” 手动跑一次。
3. 检查落库：工作流 #1/#2 看 `intel.ingestion_runs` 与 `intel.llm_usage`；工作流 #3 看 `capital.capital_publications`（应为 `PENDING_REVIEW`）。
4. 确认无重复/无脏数据后再开启 Schedule / Webhook。
5. 每次修改后重新导出本目录 JSON（不含凭证）。

## 4. 运行记录约定

```sql
INSERT INTO intel.ingestion_runs
    (workflow_name, trigger_type, status, items_fetched, items_new, stats)
VALUES
    ('03-mobocapital-1plus3', 'WEBHOOK', 'SUCCESS', 1, 1, '{"slug":"...","wechat":"PENDING_REVIEW"}');
```

LLM 调用写 `intel.llm_usage`，用于成本对账（月度限额见 `docs/06-合规与成本/成本台账.md`）。

## 5. 注意事项

- **HITL 闸门**：工作流 #3 阶段一只能写 `PENDING_REVIEW`；`PUBLISHED` 只能由阶段二（人工批准后）写入。
- **合规**：境内版本（微信/雪球）必须脱敏具体买卖点位并带免责声明；检查清单见 `docs/06-合规与成本/证券与自媒体合规.md`。
- **内存红线**：n8n 容器 `mem_limit=350m`，必须 `EXECUTIONS_PROCESS=main`，采集用 `SplitInBatches(Batch=1)` 串行。
- **`queryReplacement` 逗号风险**：长文本含逗号时参数可能被拆分；生产建议改用 Postgres Insert 模式或中间表。
- **校验**：修改模板后跑 `node -e "JSON.parse(require('fs').readFileSync('文件','utf8'))"`。
