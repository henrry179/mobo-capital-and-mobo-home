# GitHub 推送规划：本地约 8GB → 入库约 ≤3GB（2026-10-24）

> 远程：`git@github.com:henrry179/mobo-capital-and-mobo-home.git`  
> HTTPS 备份：`https://github.com/henrry179/mobo-capital-and-mobo-home.git`  
> 冻结：不改动 n8n 工作流正文、Compose、Caddy、initdb 内容（可原样入库）。

## 1. 本地体量口径（为何说「约 8GB」）

| 层 | 位置 | 约量 | 是否入本仓库 |
|---|---|---|---|
| 金库同步原件包 | `MoBo-Content-Vault-v5`（`SYNC-FILES`） | ~4.9 GiB | **否**（OSS / 后续 LFS 或独立内容仓） |
| 金库本地只读归档 | 同金库 `70-Archive` 等 | ~3.8 GiB | **否** |
| 内容原料仓 | 工程树内 `01-工作与项目/` 等 | ~19 GiB | **否**（已 gitignore） |
| 工程可推送树 | `sites` / `services` / `docs` / `deploy` / `tools`… | ≪1 GiB（实测工程去大目录后约 790M 含 `.git`） | **是** |

「约 8GB」≈ 金库同步包 + 工程侧可上站相关物料的叙事体量；**本仓推送目标是必要工程与文档，体积应远低于 3GB 上限。**

## 2. 推送范围（必须入库）

1. **三前端**：`sites/mobocapital`、`sites/mobohome`、`services/console`（及 `services/archive-dashboard` 若存在）
2. **公域演示 JSON**：`sites/*/data/*.json`（含 `editorial.json`）；`internal/*.json` 仍不入库（公私域脱敏）
3. **文档**：`docs/**`（组织/需求/架构/运维/原始资料说明与盘点元数据；不含密钥）
4. **必要部件**：`services/mobo-cli`、`tools/`（含 vault 工具）、`migrations/`、`seeds/`、`tests/`、`workflows/*.template.json`
5. **资源配置（冻结原样）**：`deploy/`（Caddy/脚本/模板）、根目录 `docker-compose*.yml`、`.env.example`
6. **同步样例包（小）**：`server-sync-data/`（约数百 KB，非金库原件）
7. **状态**：`README.md`、`TASK_STATE.md`

## 3. 明确排除（体积与安全）

| 路径/类型 | 处理 |
|---|---|
| `01-工作与项目/`、`hermes-migration/`、`ITPM原稿内容/`、`AIGC原稿/`、`ReadingBooks/`、`content-staging/` | gitignore |
| 金库 `10–70` 原件与 `80-Site-Release` 大图/缩略图 | **不复制进仓**；用文档指向金库路径 + `SYNC-FILES.txt` |
| `deploy/volumes/**` 运行时数据 | gitignore |
| `.env` / `.env.local` / `*.pem` / secrets | gitignore |
| `sites/*/internal/*.json` | gitignore（内域） |
| `services/console/data/*.json` 运行时 | gitignore |
| `_tmp_*`、日志、`__pycache__`、`.venv` | 不提交 |
| 根目录大 docx 原稿 | 已 gitignore |

**Git LFS**：本轮 **不启用**。单文件均远小于 GitHub 警告阈值；金库媒体整包用「仓外金库 + OSS」而非 LFS，避免免费额度与克隆膨胀。若日后单文件 >50MB 再按路径启用 LFS。

## 4. 执行步骤

1. 更新 `.gitignore`：允许 `sites/*/data/*.json`；保持 `internal` 与大原料仓排除  
2. `git remote set-url origin git@github.com:henrry179/mobo-capital-and-mobo-home.git`  
3. Stage 第 2 节路径；**不** `git add -f` 冻结配置的改写（本轮无改写）  
4. Commit → `git push -u origin main`  
5. 记录：推送清单、`du`/`git count-objects`、远程 `git ls-remote`、大文件策略

## 5. GitHub Pages（三站可直接打开）

- **发布源**：`main` 分支 **仓库根目录**（`/`），并提交 `.nojekyll`
- **入口**：`https://henrry179.github.io/mobo-capital-and-mobo-home/`
- **三站 URL**：
  - 资本：`.../sites/mobocapital/`
  - 之家：`.../sites/mobohome/`
  - 控制台：`.../services/console/`
- 各站 `index.html` 已在子目录根；数据用相对路径 `./data/*.json`；控制台在 `github.io` 下改走相对公域 JSON

## 6. 验收

- 远程 `main` 含三前端 + docs + 资源配置  
- 工作区体积（可推送树）≪ 3GB  
- Compose / Caddy / initdb / n8n 正文相对冻结基线无内容改动  
- Pages 三 URL 可打开；内域 JSON / 金库媒体不在公开仓  
