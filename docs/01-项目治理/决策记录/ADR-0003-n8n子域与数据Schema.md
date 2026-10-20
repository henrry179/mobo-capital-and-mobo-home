# ADR-0003：n8n 子域与数据 Schema

- 状态：Accepted
- 日期：2026-10-20
- 决策人：莫伯

## 背景

v1.0 使用 `handle_path /n8n/*` 反代 n8n，但没有配置子路径相关环境变量，n8n 的编辑器静态资源、Webhook、OAuth 回调容易错乱。同时 n8n 默认会把自身表建在 `db_mobobrain` 的 `public` Schema，与 `intel` 业务表混在一起。

## 决策

1. n8n 使用 `n8n.` **独立子域**，不做子路径。
2. n8n 数据库仍用 `db_mobobrain`，但使用独立 Schema `n8n`，属主 `user_n8n`。
3. Compose 设置：
   - `DB_TYPE=postgresdb`
   - `DB_POSTGRESDB_DATABASE=db_mobobrain`
   - `DB_POSTGRESDB_SCHEMA=n8n`
   - `DB_POSTGRESDB_USER=user_n8n`
   - `N8N_HOST=${DOMAIN_N8N}`
   - `N8N_PROTOCOL=https`
   - `WEBHOOK_URL=https://${DOMAIN_N8N}/`
   - `N8N_PROXY_HOPS=1`
4. Webhook 默认不公开：工作流以定时/手动触发为主；若未来需要外部 Webhook，单独加 `hooks.` 子域 + Header Auth + IP 限制。
5. 镜像版本在生产前固定到具体 tag/digest，不使用 `latest` 长期运行。

## 理由

- 子域是最稳的反代方式，避免 `N8N_PATH` 的边界问题。
- Schema 隔离让 n8n 升级/清理不影响 `intel` 表。
- 独立账号降低误操作风险。
- 固定版本避免“今天还能跑，明天升级坏了”。

## 后果

**正面**

- n8n 编辑器/Webhook/回调路径正确。
- 数据库结构清晰；备份仍可按库一次完成。

**负面**

- 需要多一个 DNS 记录和证书（Caddy 自动）。
- `n8n` Schema 需要预创建并授权；n8n 迁移需要该账号有 CREATE 权限。
- 升级需要手动改 tag 并测试。

## 验证

- `https://n8n...` 登录后静态资源无 404。
- `docker compose logs mobobrain-n8n` 无 schema/权限错误。
- `\dt n8n.*` 能看到 n8n 表；`\dt intel.*` 只有业务表。
- 工作流手动触发成功，Webhook URL 指向 `https://n8n.../webhook/...`。
