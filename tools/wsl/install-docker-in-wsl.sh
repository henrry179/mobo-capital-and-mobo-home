#!/usr/bin/env bash
# =============================================================================
# 在 WSL2 (Ubuntu) 内安装 Docker Engine + Compose v2，并配置国内镜像加速
# 适用：Windows 10/11 + WSL2（systemd 已启用），无需 Windows 管理员权限
#
# 用法（在 WSL 内）：
#   bash /mnt/d/path/tools/wsl/install-docker-in-wsl.sh
# 或在 Windows PowerShell：
#   wsl -u root -e bash -lc "bash /mnt/d/.../tools/wsl/install-docker-in-wsl.sh"
#
# 幂等：可重复执行
# =============================================================================
set -Eeuo pipefail

log() { printf '\033[1;33m[install-docker]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[install-docker] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

. /etc/os-release
log "发行版：$PRETTY_NAME (codename=$VERSION_CODENAME)"

# ---------------------------------------------------------------------------
# 1. systemd 必须是 PID 1（dockerd 依赖它托管）
# ---------------------------------------------------------------------------
pgrep -x systemd >/dev/null 2>&1 || die \
  "PID 1 不是 systemd。请在 /etc/wsl.conf 加 [boot] systemd=true 后执行 wsl --shutdown"

# ---------------------------------------------------------------------------
# 2. 安装 docker.io + docker-compose-v2
#    注意：新发行版（如 Ubuntu 26.04 / codename=resolute）在 docker.com 官方仓库
#    还没有对应 dist，Ubuntu 官方源已提供 29.x + compose v2，优先用它。
# ---------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
log "apt-get update ..."
apt-get update -qq

if ! dpkg -s docker.io >/dev/null 2>&1; then
  log "安装 docker.io ..."
  apt-get install -y -qq docker.io
else
  log "docker.io 已安装：$(docker --version 2>/dev/null || echo unknown)"
fi

if ! dpkg -s docker-compose-v2 >/dev/null 2>&1; then
  log "安装 docker-compose-v2 ..."
  apt-get install -y -qq docker-compose-v2
else
  log "docker-compose-v2 已安装"
fi

# ---------------------------------------------------------------------------
# 3. 守护进程配置：registry-mirrors（国内）+ 日志轮转 + nofile
#    背景：国内网络直连 Docker Hub 会 DNS 污染/超时，走镜像加速最稳。
# ---------------------------------------------------------------------------
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'JSON'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.1panel.live",
    "https://hub.rat.dev"
  ],
  "default-ulimits": {
    "nofile": { "Name": "nofile", "Hard": 65536, "Soft": 65536 }
  },
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "max-concurrent-downloads": 6
}
JSON

log "systemctl enable --now docker"
systemctl enable docker >/dev/null 2>&1 || true
systemctl restart docker
sleep 3
systemctl is-active --quiet docker || die "docker 未 active：$(systemctl status docker --no-pager | head -20)"

# ---------------------------------------------------------------------------
# 4. 常用用户加入 docker 组
# ---------------------------------------------------------------------------
DEFAULT_USER=""
if [ -f /etc/wsl.conf ]; then
  DEFAULT_USER="$(awk '/\[user\]/{f=1;next} /^\[/{f=0} f && /^[a-z_][a-z0-9_-]*$/{print $1; exit}' /etc/wsl.conf)"
fi
if [ -z "$DEFAULT_USER" ]; then
  DEFAULT_USER="$(awk -F: '$3>=1000 && $7 !~ /(nologin|false)$/ {print $1; exit}' /etc/passwd)"
fi
if [ -n "$DEFAULT_USER" ] && id -u "$DEFAULT_USER" >/dev/null 2>&1; then
  getent group docker >/dev/null 2>&1 || groupadd docker
  usermod -aG docker "$DEFAULT_USER"
  log "已把 $DEFAULT_USER 加入 docker 组（重新登录 WSL 会话后生效）"
fi

# ---------------------------------------------------------------------------
# 5. 验证
# ---------------------------------------------------------------------------
log "版本："
docker --version
docker compose version
log "状态：$(systemctl is-active docker)  存储：$(docker info --format '{{.Driver}}' 2>/dev/null)"

log "连通性测试（hello-world）..."
if docker run --rm hello-world >/dev/null 2>&1; then
  log "OK：容器可正常运行"
else
  log "警告：hello-world 拉取失败，检查 registry-mirrors 是否可达"
fi

cat <<'DONE'

────────────────────────────────────────────────────────────
 Docker Engine (WSL2) 就绪

 下一步（WSL 内）：
   cd /mnt/e/01-文档资料/报告与规划/莫伯双站系统
   bash tools/wsl/wsl-up.sh

 提示：
  · Windows 侧与 WSL 侧通过 localhost 互通（需 .wslconfig 里 networkingMode=mirrored）
  · 数据目录用命名卷（落在 WSL ext4），不要绑定 /mnt/e（drvfs 不支持 chmod，会导致 Postgres 初始化失败）
  · 若本机 http_proxy 指向 127.0.0.1:7897，curl 测试请加 --noproxy '*'
────────────────────────────────────────────────────────────
DONE
