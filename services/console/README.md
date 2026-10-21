# 莫伯系统控制台（MoBo Control Deck）

> 静态操作台：统一观测莫伯资本与莫伯之家两站的**状态、数据与运维动作**。
> 入口：`admin` 域（生产）/`admin.localhost`（本地）。**只读，不含任何密钥**。

## 1. 它解决什么问题

方案里第六个入口原本只是一张"入口列表"占位页。控制台把它升级为真正的**控制面**：

| 区块 | 内容 | 数据来源 |
|---|---|---|
| KPI 行 | 入口可达性、常驻内存、NAV/回撤、风控状态、待审发布、论点/策略、档案计数、最后刷新 | 两站脱敏 JSON + `status.json` |
| 入口矩阵 | 6 个入口的鉴权要求与实时可达性（OK / 需认证 / 不可达） | `status.json` |
| 运行时 | 容器健康与内存、磁盘、宿主机内存、Git 提交、最近备份、数据库计数 | `status.json` |
| 投研与风控 | 毛/高水位/净 NAV、回撤、风控状态与动作建议、宏观指标 Z-Score、期权波动率曲面 | `/api/capital/data/terminal-snapshot.json` |
| 内容流水线 | 论点/策略数、已发布/待审、渠道指标累计、四端发布开关、内容清单 | `/api/capital/data/public-data.json` |
| 个人档案 | 人生篇章、影像、藏书馆、训练与复盘计数 | `/api/home/data/public-home-data.json` |
| 任务与质量门 | L0–L6 进度、最近一次 Q0–Q14 门禁结果 | `status.json` / `gate.json` |
| 运维动作 | 11 条常用命令，点击即复制 | 静态 |
| 成本与预算 | 基础设施分项与 2,400 红线、AI 额度单列 | 静态 |
| 架构红线 | 五条红线 + 微信/X 阶段二禁用提示 | 静态 |

## 2. 数据流

```text
PostgreSQL ──mobo-cli export-site──▶ sites/*/data/*.json   （已物理脱敏）
                                        │
Caddy（同源只读转发 /api/capital/*、/api/home/*）
                                        │
                                  services/console/  ──▶ 控制台页面
                                        ▲
tools/wsl/collect-status.sh ─▶ services/console/data/status.json
tools/wsl/quality-gate.sh  ─▶ services/console/data/gate.json
```

- 控制台**不直接连数据库**（红线：页面不持有数据库凭据），只读已脱敏的 JSON。
- 数据面路径 `/api/capital/*`、`/api/home/*` 由 Caddy 做静态转发，不做代理计算，因此**零额外内存**（红线一）。

## 3. 可见性切换

顶栏 `PUBLIC / LP_PROSPECT / INTERNAL` 只影响**页面内对已拉取数据包的筛选展示**：

- `PUBLIC`：仅显示 `visibility=PUBLIC` 的记录；
- `LP_PROSPECT`：额外显示 `LP_PROSPECT`；
- `INTERNAL`：显示全部（**但仍只展示已脱敏的公域包**，不含私有字段）。

真正的 `INTERNAL` 全量包位于各站 `/internal/*`，由 BasicAuth 单独保护。

## 4. 刷新与更新

| 数据 | 刷新方式 |
|---|---|
| 两站数据包 | `mobo-cli export-site --site all`（写盘前自动脱敏 + 审计） |
| 运行时状态 | `bash tools/wsl/collect-status.sh` |
| 质量门结果 | `bash tools/wsl/quality-gate.sh`（自动写 `gate.json`） |
| 页面 | 每 15 秒自动刷新（顶栏可关） |

`services/console/data/*.json` 为运行时产物，已在 `.gitignore` 中，不入库。

## 5. 文件

```text
services/console/
├─ index.html            # 页面骨架
├─ assets/console.css    # 控制面样式（深海蓝 + 香槟金 + 等宽数据字体）
├─ assets/console.js     # 数据拉取与渲染
├─ data/                 # 运行时 status.json / gate.json（不入库）
└─ README.md             # 本文件
```

## 6. 维护注意

1. 页面**不得**引入任何需要后端渲染的依赖，保持静态与零构建；
2. 新增数据源时，优先在 `mobo-cli` 侧导出 JSON，而不是让页面直连数据库；
3. 任何显示真实密钥的改动都不允许合入（质量门 Q5 会拦）；
4. 若新增域名入口，记得同步 `deploy/caddy/Caddyfile(.local)` 的入口矩阵与 `collect-status.sh` 的探测列表。
