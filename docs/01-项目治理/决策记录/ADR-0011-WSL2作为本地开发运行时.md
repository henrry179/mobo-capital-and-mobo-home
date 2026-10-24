# ADR-0011：WSL2 作为本地开发运行时

- **状态**：已接受
- **日期**：2026-10-21
- **决策人**：莫伯
- **相关**：ADR-0010（本地优先）、红线一（内存硬限流）、`tools/wsl/`

> **Canonical**：本议题「为何如此」以本文为真源；总册 / docs/03 / 整合总览仅保留结论指针，勿复制背景/替代方案/后果长文。

## 背景

ADR-0010 决定"本地优先，不上公网"。要在本地跑完整六容器全栈（PostgreSQL 16 + pgvector、思源、n8n、Streamlit、Caddy、Restic），需要容器运行时。本机实测：

- Windows 会话**非管理员** → Docker Desktop 的安装/服务注册需要提权；
- 没有 Docker Desktop，也没有任何 docker 可执行文件；
- Python 仅为 Microsoft Store 占位符（`python --version` 失败），无法本地跑 CLI 单测与迁移脚本；
- 但 **WSL2 + Ubuntu 26.04 已就绪**：systemd 为 PID 1、`wsl -u root` 免密、宿主 16 核 / 31.7GB / C 盘余 97.5GB、虚拟化已开启。

## 决策

**本地开发运行时 = WSL2 内的 Docker Engine（docker.io + docker-compose-v2），不装 Docker Desktop。**

配套约定：

1. **安装**：`tools/wsl/install-docker-in-wsl.sh`（幂等，Ubuntu 官方源 + `daemon.json` 配 `registry-mirrors`）。
2. **网络**：Windows 侧 `~/.wslconfig` 设 `networkingMode=mirrored` + `dnsTunneling` + `autoProxy`，WSL 与宿主共享 localhost。
3. **存储**：容器数据一律用**命名卷**（WSL ext4），不绑定 `/mnt/e`（drvfs 不支持 chmod，Postgres 初始化会失败）。
4. **编排**：新增 `docker-compose.wsl.yml` 覆盖（命名卷、纯 HTTP 网关、国内 pip/apk 源、环回端口暴露）；基础 `docker-compose.yml` 保持生产语义不变。
5. **构建源**：Dockerfile 增 `PIP_INDEX_URL` / `APK_MIRROR` / `APT_MIRROR` build arg，默认仍是官方源，本地覆盖用国内源。
6. **启动**：`tools/wsl/wsl-up.sh` 一键（生成 bcrypt → compose 校验 → postgres → 冒烟 → 全栈 → 内存统计）。

## 理由

| 理由 | 说明 |
|---|---|
| 免提权 | `wsl -u root` 直接可用，不触碰 Windows 安装与 UAC |
| 与生产同构 | 同一个 compose 基础文件、同一套 01~09 SQL、同一组镜像；本地验证过的就是生产要跑的 |
| 可复现 | 脚本入 Git，任何机器按 README 两条命令即可复现 |
| 性能可接受 | 命名卷落 ext4；源码目录在 /mnt/e 只做只读挂载（构建上下文），慢一点不影响正确性 |
| 不锁死 | 生产切回只需去掉覆盖文件，不留 WSL 专属耦合 |

## 代价与缓解

| 代价 | 缓解 |
|---|---|
| WSL 与 Windows 需镜像网络才能互通端口 | `.wslconfig` 固化步骤；README 写明 |
| 源码在 /mnt/e，文件 IO 偏慢 | 数据走命名卷；必要时把仓库 clone 进 WSL ext4 再用软链 |
| 国内镜像源有可用性波动 | `daemon.json` 配 3 个镜像容错；`tools/wsl/README.md` 记录实测可用源 |
| 代理变量会污染命令行测试 | 统一 `--noproxy '*'`；README 明确标注"带 `Proxy-Connection` 的 502 不是网关故障" |

## 备选方案

- **Docker Desktop**：需管理员权限与重启，且与 WSL2 引擎功能重叠；被否。
- **Podman Desktop**：同样需要提权，且与 compose 兼容性需额外验证；被否。
- **仅用零依赖预览模式**（`tools/local-preview/`）：能看页面但无法验证数据库/看板/工作流；降级为**模式 A**保留，不作为主路径。

## 落地结果（2026-10-21 实测）

| 指标 | 结果 |
|---|---|
| Docker / Compose | 29.1.3 / 2.40.3（WSL 内，systemd 托管） |
| 六容器 | 全部 healthy |
| 数据库冒烟 | `tests/sql/smoke.sql` **9 组全绿**（含 capital 域 10 表+4 视图、NAV 触发器、跨库拒绝） |
| 网关入口 | 公开站 200；受保护入口未认证 401、认证 200；`/internal/*` 未认证 401 |
| 内存 | 合计约 **636 MiB**（限额合计 1842 MiB），远低于 1.55GB 常驻红线 |
| 当日修复的 8 个真实问题 | 见 `docs/01-项目治理/开发部署任务执行时间线.md` §2 D0 表 |
