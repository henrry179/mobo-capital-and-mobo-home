# WSL2 本地开发运行时

> 用途：在 **Windows + WSL2** 的开发机上，用 WSL 内的 Docker Engine 跑本项目的完整六容器全栈
> （PostgreSQL 16 + pgvector、思源、n8n、Streamlit 看板、Caddy、Restic 备份）。
> 决策依据：[ADR-0011](../../docs/01-项目治理/决策记录/ADR-0011-WSL2作为本地开发运行时.md)

## 0. 为什么是 WSL2 而不是 Docker Desktop

| 维度 | 结论 |
|---|---|
| 权限 | 本机 Windows 会话**非管理员**；Docker Desktop 安装需要提权。WSL 内 `wsl -u root` 免密可用 |
| 资源 | WSL 已装 Ubuntu 26.04 + systemd 开启；宿主 16 核 / 31.7GB / C 盘剩 97.5GB，远超需求 |
| 网络 | `.wslconfig` 设 `networkingMode=mirrored` 后，WSL 与宿主共享 localhost，端口双向直连 |
| 性能 | 容器数据放**命名卷**（WSL ext4），不落 `/mnt/e`（drvfs 不支持 chmod，会让 Postgres 初始化失败） |

## 1. 一次性安装

```bash
# 在 WSL 内（PowerShell：wsl -u root -e bash -lc "bash /mnt/d/.../tools/wsl/install-docker-in-wsl.sh"）
bash tools/wsl/install-docker-in-wsl.sh
```

脚本做四件事：

1. 安装 `docker.io`（29.x）+ `docker-compose-v2`（2.4x）
   ——**不用 docker.com 官方源**：新发行版（codename `resolute`）在该源还没有 dist，Ubuntu 官方源已提供
2. 写 `/etc/docker/daemon.json`：`registry-mirrors`（daocloud / 1panel / rat.dev）+ 日志轮转 + nofile
3. `systemctl enable --now docker`，把常用用户加入 `docker` 组
4. 用 `hello-world` 验证拉取

### Windows 侧 `.wslconfig`（用户级，无需管理员）

```ini
[wsl2]
memory=24GB
processors=12
swap=8GB
swapFile=E:\\WSL\\swap.vhdx
networkingMode=mirrored
dnsTunneling=true
autoProxy=true
firewall=true
localhostForwarding=true
```

改完执行 `wsl --shutdown` 生效（会停掉 WSL 里的容器，重启后 systemd 自动拉起 docker）。

> 旧版 WSL 用 `[experimental] networkingMode=mirrored`；新版请写在 `[wsl2]` 下，否则会打印"未知选项"告警。

## 2. 启动本地全栈

```bash
cd /mnt/e/01-文档资料/报告与规划/莫伯双站系统
bash tools/wsl/wsl-up.sh
```

脚本：生成 bcrypt → 校验 compose → 起 postgres（首次跑 01~09）→ 冒烟 9 组 → 起全栈 → 内存统计。

手动等价命令：

```bash
C="docker compose -f docker-compose.yml -f docker-compose.wsl.yml --env-file .env.local"
$C up -d --build
$C ps
docker stats --no-stream
```

## 3. 入口

| 入口 | 地址 | 认证 |
|---|---|---|
| 莫伯资本 | `http://localhost/` | 公开 |
| 莫伯之家 | `http://mobohome.localhost/` | 公开 |
| 生命体征实验室 | `http://lab.localhost/` | BasicAuth |
| 思源笔记 | `http://kb.localhost/` | BasicAuth + 思源访问码 |
| n8n | `http://n8n.localhost/` | BasicAuth |
| 操作台 | `http://admin.localhost/` | BasicAuth |
| 内网驾驶舱 | `http://localhost/internal/internal-data.json` | BasicAuth（未认证 401） |

BasicAuth 默认 `mobo` / `mobo-local`（本地弱口令，见 `.env.local`）。

## 4. 本地专属编排差异（`docker-compose.wsl.yml`）

| 项 | 基础编排 | WSL 覆盖 |
|---|---|---|
| 数据目录 | 绑定挂载 `./deploy/volumes/*` | **命名卷**（落 WSL ext4，快 5–20 倍且支持 chmod） |
| 网关配置 | `Caddyfile`（HTTPS/ACME） | `Caddyfile.local`（纯 HTTP，`*.localhost`） |
| pip 源 | pypi.org | 清华源（pypi.org 在受限网络不可达） |
| apk 源 | Alpine 官方 CDN | 阿里云源（官方 CDN 被拦） |
| 端口 | 仅 80/443 | 额外暴露 5432/5678/6806/8501 到环回地址，便于 Windows 侧 CLI 直连 |

## 5. 受限网络下的三个坑（已修复，勿回退）

| 坑 | 现象 | 修复 |
|---|---|---|
| Docker Hub 拉不动 | `dial tcp ...: i/o timeout` | `daemon.json` 配 `registry-mirrors` |
| PyPI 装不上 | pip 超时/重试 | Dockerfile `PIP_INDEX_URL` build arg → 清华源 |
| Alpine 装不上 | `apk: Permission denied` | Dockerfile `APK_MIRROR` build arg → 阿里云源 |

## 6. 本地代理注意事项

本机配置了 `http_proxy=http://127.0.0.1:7897`（且该代理当前 TLS CONNECT 不可用）：

- **命令行测试一律加 `--noproxy '*'`**，否则会拿到来自身份代理的 502（带 `Proxy-Connection` 响应头，极易误判为网关故障）；
- 浏览器访问 `*.localhost` 正常（浏览器直连，不走 shell 的代理变量）；
- 若浏览器也异常，在代理客户端里把 `localhost` 与 `*.localhost` 加入直连规则。

## 7. 常见问题

| 现象 | 处理 |
|---|---|
| `permission denied for database db_mobobrain` | n8n 需要库级 CREATE：`migrations/202610210001__grant_n8n_create_on_database.sql` |
| `initdb: directory ... exists but is not empty` | 卷挂载在 /mnt/e；改用命名卷 + `PGDATA` 子目录 |
| 思源容器反复重启 | 镜像 v3.8 内核需 `serve` 子命令参数（见基础编排 `command:`） |
| n8n `JavaScript heap out of memory` | `NODE_OPTIONS` 与 `mem_limit` 需匹配（现 400MB / 512MB） |
| `docker compose` 找不到 `.env.local` | 必须带 `--env-file .env.local` |
| 端口被占用 | Windows 侧占用时改映射端口 |

## 8. 与生产的差异

WSL 本地全栈与生产**同一套镜像、同一个 compose 基础文件、同一套 SQL**，差异仅在：域名/HTTPS、OSS、密钥、备份目标、监控告警。
生产切回方式：去掉 `docker-compose.wsl.yml`，用 `docker-compose.local.yml`（或生产的 `docker-compose.yml`）即可。
