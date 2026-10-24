#!/usr/bin/env bash
# =============================================================================
# 莫伯双站 · 本地 crontab 接线（本地优先模式）
#
# 用途：把「量化终端采集器」与「双站静态包刷新」挂到 WSL 的 cron 上，
#       让 http://localhost/ 的 /terminal 栏目每天自动更新（ADR-0007 / ADR-0010）。
#
# 设计要点：
#   - 幂等：整块内容用 BEGIN/END 标记管理，重复执行只替换不追加；
#   - 不写死行情兜底常量：网络不可用时采集器保留库内最近一期（见采集器注释）；
#   - 日志落在 tools/wsl/logs/（已 gitignore），不进仓库；
#   - 路径含中文，故命令里显式加 LANG=C.UTF-8，避免 cron 的 locale 缺默认值。
#
# 用法（WSL 内）：
#   bash tools/wsl/install-local-cron.sh            # 安装/更新
#   bash tools/wsl/install-local-cron.sh --print    # 只打印，不写 crontab
#   bash tools/wsl/install-local-cron.sh --uninstall
#
# ⚠️ 默认 venv 在 /root/venv-mobo-cli（仅 root 可读），因此需 root 执行：
#   wsl -u root -e bash -lc "bash /mnt/e/.../tools/wsl/install-local-cron.sh"
#   或用 MOBO_VENV 指定其他可读路径。
# =============================================================================
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VENV_DIR="${MOBO_VENV:-/root/venv-mobo-cli}"
PY="$VENV_DIR/bin/python"
CLI="$VENV_DIR/bin/mobo-cli"
COLLECTOR="$PROJECT_DIR/services/mobo-cli/collectors/macro_iv_collector.py"
ENV_FILE="${MOBO_ENV_FILE:-$PROJECT_DIR/.env.local}"
LOG_DIR="${MOBO_LOG_DIR:-$PROJECT_DIR/tools/wsl/logs}"

MARK_BEGIN="# >>> mobo-local-cron (managed by tools/wsl/install-local-cron.sh) >>>"
MARK_END="# <<< mobo-local-cron <<<"

ACTION="install"
case "${1:-}" in
  --uninstall) ACTION="uninstall" ;;
  --print)     ACTION="print" ;;
  "")          ACTION="install" ;;
  *) echo "未知参数：$1（支持 --print / --uninstall）"; exit 2 ;;
esac

fail() { echo "[!] $*" >&2; exit 1; }

# --- 前置检查 ---------------------------------------------------------------
[ -f "$COLLECTOR" ] || fail "找不到采集器：$COLLECTOR"
[ -f "$ENV_FILE" ]  || fail "找不到环境文件：$ENV_FILE（本地优先模式应使用 .env.local）"
[ -x "$PY" ]       || fail "找不到可执行的 Python：$PY（用 MOBO_VENV 指定）"

if [ "$(id -u)" -ne 0 ] && [ ! -r "$PY" ]; then
  fail "当前用户读不到 $PY；请用 root 执行：wsl -u root -e bash -lc \"bash $0\""
fi

mkdir -p "$LOG_DIR"

COLLECT_LOG="$LOG_DIR/macro-iv-collector.log"
EXPORT_LOG="$LOG_DIR/export-site.log"

build_block() {
  cat <<EOF
$MARK_BEGIN
# 莫伯双站 · 量化终端采集（A股/港股收盘后 16:35）
35 16 * * 1-5 cd "$PROJECT_DIR" && LANG=C.UTF-8 "$PY" "$COLLECTOR" --env-file "$ENV_FILE" >> "$COLLECT_LOG" 2>&1
# 莫伯双站 · 量化终端采集（美股收盘后，次日清晨 06:15）
15 6 * * 2-6 cd "$PROJECT_DIR" && LANG=C.UTF-8 "$PY" "$COLLECTOR" --env-file "$ENV_FILE" >> "$COLLECT_LOG" 2>&1
# 莫伯双站 · 双站静态数据包刷新（每日 03:20）
20 3 * * * cd "$PROJECT_DIR" && LANG=C.UTF-8 "$CLI" --env-file "$ENV_FILE" export-site --site all >> "$EXPORT_LOG" 2>&1
$MARK_END
EOF
}

if [ "$ACTION" = "print" ]; then
  build_block
  exit 0
fi

# --- 采集器体检（装之前先确认能连上库）--------------------------------------
echo "=== 采集器体检 ==="
if ! LANG=C.UTF-8 "$PY" "$COLLECTOR" --env-file "$ENV_FILE" --check; then
  fail "采集器体检未通过，已中止安装"
fi

# --- 写入 crontab -----------------------------------------------------------
CURRENT="$(crontab -l 2>/dev/null || true)"
STRIPPED="$(printf '%s\n' "$CURRENT" | awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
  $0==b {skip=1} !skip {print} $0==e {skip=0}
')"

if [ "$ACTION" = "uninstall" ]; then
  printf '%s\n' "$STRIPPED" | grep -v '^$' | crontab - 2>/dev/null || true
  echo "已移除 mobo-local-cron 条目。"
  crontab -l 2>/dev/null | awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    $0==b {show=1} show {print} $0==e {show=0}
  '
  exit 0
fi

{
  printf '%s\n' "$STRIPPED" | grep -v '^$' || true
  build_block
} | crontab -

echo
echo "=== 已写入 crontab ==="
crontab -l 2>/dev/null | awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
  $0==b {show=1} show {print} $0==e {show=0}
'
echo
echo "日志：$COLLECT_LOG"
echo "     $EXPORT_LOG"
echo "注意：WSL 的 cron 只在 WSL 实例运行时触发；关机/休眠期间不会补跑。"
