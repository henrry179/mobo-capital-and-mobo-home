# n8n 工作流

> 本目录存放可导入 n8n 的工作流**模板**：`*.template.json` 中的 URL、Key、模型、凭证 ID 均为占位符，导入后必须替换。

## 1. 工作流清单

| 文件 | 作用 | 触发 | 写入 |
|---|---|---|---|
| `workflow-01-rss-to-vault.template.json` | RSS 采集 → 去重 → `intel.articles_vault` | 每 4 小时 | `articles_vault`（`NEW`） |
| `workflow-02-score-to-draft.template.json` | 取 `NEW` → LLM 评分 → 回写状态 | 手动（稳定后改定时） | `articles_vault`（`SCORED`/`NEEDS_MANUAL`） |

后续工作流（待实现，命名 `workflow-03-*.json` 起）：

- `03`：高分文章 → 生成多平台 `content_drafts`（WECHAT/XUEQIU/X），只写 `DRAFT`。
- `04`：`SCORED` 文章 → 思源笔记（`intel.articles_vault.siyuan_doc_id` 回填）。
- `05`：每周复盘 / 数据对账 / 成本统计。

## 2. 导入前准备

1. n8n 已能通过 `https://n8n.<主域>/` 登录（BasicAuth + owner 账号）。
2. 创建 PostgreSQL 凭证：
   - Host `postgres`，Port `5432`，Database `db_mobobrain`
   - User `user_mobobrain`（业务）或 `user_n8n`（n8n 自身 Schema）
   - SSL 关闭（容器内网）
3. 在 `intel.sources` 登记 RSS 源（`feed_url` 唯一）。
4. 创建 LLM 凭证（Header Auth 或 OpenAI-compatible 节点），或先把 Key 放环境变量再引用。
5. 打开模板，替换：
   - `REPLACE_WITH_CREDENTIAL_ID` / `REPLACE_WITH_LLM_KEY`
   - `https://example.com/feed.xml`
   - `https://api.example.com/v1/chat/completions`、`your-chat-model`

## 3. 导入与启用

1. n8n → Workflows → Import from File，选择模板 JSON。
2. 保存后先保持 **Inactive**，点 “Execute Workflow” 手动跑一次。
3. 检查 `intel.ingestion_runs` 与 `intel.llm_usage`（工作流应写入运行记录）。
4. 确认无重复/无脏数据后，再开启 Schedule。
5. 每改一次工作流，导出更新本目录 JSON（不含凭证）。

## 4. 运行记录约定

工作流成功/失败都应写 `intel.ingestion_runs`：

```sql
INSERT INTO intel.ingestion_runs
    (workflow_name, trigger_type, status, items_fetched, items_new, stats)
VALUES
    ('01-rss-to-vault', 'SCHEDULE', 'SUCCESS', 20, 8, '{"note":"n8n 节点统计"}');
```

LLM 调用写 `intel.llm_usage`，用于成本对账。

## 5. 注意事项

- **不要把真实 Key/密码写进工作流 JSON**；凭证走 n8n Credentials。
- 平台发布永远由人审核；工作流只能写 `DRAFT`。
- `queryReplacement` 对含逗号的长文本可能出错；生产建议改用 Postgres Insert 模式或中间表。
- 工作流 JSON 导出时如包含凭证引用，只保留凭证 ID/名称，不保留密钥。
- 修改模板后跑 `node -e "JSON.parse(require('fs').readFileSync('文件','utf8'))"` 做 JSON 校验。
