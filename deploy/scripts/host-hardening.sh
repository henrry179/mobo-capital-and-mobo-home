#!/usr/bin/env bash
# =============================================================================
# 主机加固（Ubuntu 22.04/24.04，root 执行）
# 内容：时区、Swap、swappiness、SSH 密钥登录、UFW、fail2ban、Docker 日志、
#       unattended-upgrades、journald 限额。
#
# 安全提示：
# - 默认只在检测到 /root/.ssh/authorized_keys 时才关闭密码登录；
#   否则会跳过，避免把自己锁在门外。
# - 如需强制关闭密码登录：FORCE_SSH_HARDENING=1 ./host-hardening.sh
# - 如 SSH 不是 22 端口，请先改 SSH_PORT。
# =============================================================================
set -Eeuo pipefail

log() { echo "[$(date '+%F %T')] $*"; }
die() { log "ERROR: $*"; exit 1; }

[ "$(id -u)" = "0" ] || die "请用 root 执行"
[ -f /etc/os-release ] || die "无法识别系统"
. /etc/os-release
case "${ID:-}" in
    ubuntu|debian) ;;
    *) log "WARN: 当前系统 ${ID:-unknown}，脚本按 Ubuntu/Debian 编写，请谨慎" ;;
esac

SSH_PORT="${SSH_PORT:-22}"
SSH_ALLOW_FROM="${SSH_ALLOW_FROM:-}"
FORCE_SSH_HARDENING="${FORCE_SSH_HARDENING:-0}"
SWAP_SIZE="${SWAP_SIZE:-4G}"
COMPOSE_DIR="${COMPOSE_DIR:-/opt/mobo-stack}"

log "1/9 安装基础包"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg ufw fail2ban unattended-upgrades chrony \
    rsync jq htop tree unzip

log "2/9 时区与 NTP"
timedatectl set-timezone Asia/Shanghai || true
systemctl enable --now chrony || true

log "3/9 Swap ${SWAP_SIZE}"
if ! swapon --show | grep -q '/swapfile'; then
    if [ ! -f /swapfile ]; then
        fallocate -l "$SWAP_SIZE" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096 status=progress
    fi
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
else
    log "Swap 已存在，跳过创建"
fi
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
cat > /etc/sysctl.d/99-mobo.conf <<'EOF'
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF
sysctl --system >/dev/null

log "4/9 SSH 加固"
mkdir -p /etc/ssh/sshd_config.d
KEY_FILE="${SSH_AUTHORIZED_KEYS:-/root/.ssh/authorized_keys}"
if [ -s "$KEY_FILE" ] || [ "$FORCE_SSH_HARDENING" = "1" ]; then
    cat > /etc/ssh/sshd_config.d/99-mobo.conf <<'EOF'
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
MaxAuthTries 5
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
    if sshd -t; then
        systemctl reload ssh || systemctl reload sshd || true
        log "SSH 已关闭密码登录（确保你已配置密钥）"
    else
        log "ERROR: sshd 配置校验失败，保留原配置"
        rm -f /etc/ssh/sshd_config.d/99-mobo.conf
    fi
else
    log "WARN: 未发现 $KEY_FILE；跳过关闭密码登录。配置密钥后重跑，或 FORCE_SSH_HARDENING=1"
fi

log "5/9 UFW"
ufw default deny incoming
ufw default allow outgoing
if [ -n "$SSH_ALLOW_FROM" ]; then
    ufw allow from "$SSH_ALLOW_FROM" to any port "$SSH_PORT" proto tcp
else
    ufw allow "$SSH_PORT"/tcp
fi
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw --force enable
ufw status verbose

log "6/9 fail2ban（SSH + Caddy 401）"
mkdir -p /etc/fail2ban/filter.d
cat > /etc/fail2ban/filter.d/caddy-401.conf <<'EOF'
[Definition]
failregex = ^.*"remote_ip":"<HOST>".*"status":401.*$
            ^.*"status":401.*"remote_ip":"<HOST>".*$
ignoreregex =
EOF
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 10
backend = auto

[sshd]
enabled = true
port = ${SSH_PORT}
logpath = %(sshd_log)s
maxretry = 5
bantime = 2h

[caddy-401]
enabled = true
port = http,https
filter = caddy-401
logpath = ${COMPOSE_DIR}/deploy/volumes/caddy_logs/access.log
maxretry = 10
findtime = 10m
bantime = 1h
EOF
systemctl enable --now fail2ban
systemctl restart fail2ban
fail2ban-client status || true

log "7/9 Docker 日志轮转"
if command -v docker >/dev/null 2>&1; then
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    systemctl restart docker || true
else
    log "Docker 未安装，跳过 daemon.json（安装后重跑本步）"
fi

log "8/9 自动安全更新"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
systemctl enable --now unattended-upgrades || true

log "9/9 journald 限额"
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-mobo.conf <<'EOF'
[Journal]
SystemMaxUse=200M
SystemKeepFree=1G
MaxRetentionSec=30day
EOF
systemctl restart systemd-journald || true

log "完成。请检查："
log "  free -m | grep -i swap"
log "  ufw status verbose"
log "  fail2ban-client status"
log "  sshd -T | grep -E 'passwordauthentication|permitrootlogin'"
log "  docker info | grep -A2 'Logging Driver'"
