# 本地预览（零依赖模式）

> 目标：在**没有 Docker、没有 PostgreSQL、没有 Python** 的机器上，先把两个网站的**真实页面与真实路由**跑起来看。
> 适用：本机只有 Node.js（本仓库当前开发机即如此）。
> 与 Docker 全栈的关系：**站点代码、目录、路由、鉴权、缓存、脱敏口径完全一致**；差异只在"数据从哪来"和"后端服务是否在跑"。

---

## 1. 一键启动

```bash
node tools/local-preview/start.js
```

输出：

```text
  架构与入口总览  http://127.0.0.1:8082/
  莫伯资本        http://127.0.0.1:8080/
  莫伯之家        http://127.0.0.1:8081/
  状态 JSON       http://127.0.0.1:8082/status.json
  /internal/*     BasicAuth：mobo / mobo-local（仅本地）
```

分步执行也可以：

```bash
node tools/local-preview/generate-sample-data.js   # 只生成数据包
node tools/local-preview/serve.js                   # 只启动网关
```

自定义端口：

```bash
node tools/local-preview/serve.js --capital 9080 --home 9081 --console 9082
```

## 2. 本地预览复刻了哪些生产行为

| 生产（Caddyfile） | 本地预览实现 |
|---|---|
| 双主站独立入口 | 两个独立端口（:8080 / :8081） |
| `/data/*.json` → `public, max-age=60, must-revalidate` | 同规则 |
| `/internal/*` → `basic_auth` + `no-store` + `noindex` | 同规则（未认证 401 + `WWW-Authenticate`） |
| SPA `try_files {path} /index.html` | 同规则 |
| `security_headers` 片段（nosniff / SAMEORIGIN / Referrer-Policy / Permissions-Policy） | 同规则 |
| 目录穿越防护 | `safeJoin()` 解析后校验根目录前缀 |
| JSON 静态分发（`file_server`） | 同规则 |

## 3. 样例数据从哪来

`generate-sample-data.js` 依据**与生产同构的字段**生成 5 个包：

| 文件 | 内容 | 裁剪规则 |
|---|---|---|
| `sites/mobocapital/data/public-data.json` | 论点、策略、交易复盘、发布、渠道指标 | 剔除 `visibility='INTERNAL'`，删除私有字段 |
| `sites/mobocapital/data/terminal-snapshot.json` | 宏观指标、期权波动率曲面、组合 NAV | — |
| `sites/mobocapital/internal/internal-data.json` | 全量（含 `private_blotter_oss_key`） | 无裁剪，仅 BasicAuth 保护 |
| `sites/mobohome/data/public-home-data.json` | 人生篇章、画廊、藏书馆、训练、复盘 | 剔除 `is_sensitive`，删除私有字段 |
| `sites/mobohome/internal/internal-home-data.json` | 全量（含私密影像与 VAULT 复盘） | 无裁剪，仅 BasicAuth 保护 |

生成后会**自动做一次与 `exporters.audit_payload()` 等价的审计**：

```text
[audit] capital public: OK（0 违规）
[audit] home public: OK（0 违规）
[audit] capital internal（应含敏感字段，仅内网可见）: 含敏感字段（预期）
```

> 这些 JSON 在 `.gitignore` 中（`sites/*/data/*.json`、`sites/*/internal/*.json`），不入库；脚本随时可重新生成。

## 4. 验收入口

| 检查 | 期望 |
|---|---|
| `http://127.0.0.1:8080/` | 莫伯资本首页，五大栏目可切换，终端表有数据 |
| `http://127.0.0.1:8081/` | 莫伯之家首页，篇章/画廊/藏书馆可过滤 |
| `http://127.0.0.1:8080/internal/internal-data.json` | **401**（未认证） |
| `curl -u mobo:mobo-local http://127.0.0.1:8080/internal/internal-data.json` | **200** 且含 `private_blotter_oss_key` |
| `http://127.0.0.1:8082/` | 架构总览页（拓扑 + 实时状态 + 差异对照） |
| `http://127.0.0.1:8082/status.json` | 网关状态、数据文件清单、最近请求 |

## 5. 与 Docker 全栈的差异

| 能力 | 本地预览 | Docker 全栈 |
|---|---|---|
| 双站门户与路由 | ✅ 真实 | ✅ 真实 |
| 公私域鉴权与脱敏裁剪 | ✅ 真实 | ✅ 真实 |
| 数据来源 | 样例数据（脚本生成） | PostgreSQL → CLI 导出 + 审计 |
| PostgreSQL / pgvector / 触发器 / NAV | ❌ | ✅ |
| Streamlit 实验室 | 占位页 | ✅ 实时看板 |
| 思源 / n8n | ❌ | ✅ |
| OSS / Restic 备份 | ❌ | ✅ |
| HTTPS / 域名 | HTTP + 127.0.0.1 | 双主域 + ACME |

切换到全栈形态后，`sites/` 下的前端文件**不需要任何改动**。

## 6. 常见问题

| 现象 | 原因 / 处理 |
|---|---|
| 页面样式丢失（全是纯文本 HTML） | Tailwind 与字体走 CDN，需要联网；离线时用 `apps/官网/09-路由与部署说明.md` 之外的本地构建方案 |
| 图片不显示 | 样例数据引用 Unsplash 图床，需要联网；本地可用 `images.unsplash.com` 直连 |
| `8080` 被占用 | 换端口：`--capital 9080 --home 9081 --console 9082` |
| 数据包 404 | 未生成样例数据 → 先跑 `generate-sample-data.js` |
| 端口 8080 监听失败 | 检查防火墙/安全软件占用 |
| 想换成自己的数据 | 直接改 `generate-sample-data.js` 里的数组，或用 `mobo-cli export-site`（需全栈）产出真包覆盖同名文件 |

## 7. 目录

```text
tools/local-preview/
├─ start.js                  # 一键启动（生成数据 + 启动网关）
├─ serve.js                  # 零依赖预览网关（Node 内置模块）
├─ generate-sample-data.js   # 样例数据包生成 + 脱敏审计
├─ architecture.html         # 架构与入口总览页（:8082）
├─ lab-placeholder.html      # 实验室占位页
└─ README.md                 # 本文件
```
