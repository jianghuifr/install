#!/usr/bin/env bash
# ============================================================
#  devkit 公共函数库（被 install.sh 与各子脚本 source）
#  兼容 bash 3.2（macOS 自带版本），不使用 bash4 专有语法
# ============================================================

DEVKIT_ROOT="${DEVKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"

# ---------- 镜像地址（全部可用环境变量覆盖） ----------
# pip   : 清华 PyPI
# npm   : npmmirror（阿里）
# cargo : rsproxy（字节，rustup 与 crates 都有）
# apt   : 清华（Ubuntu/Debian 系统源）
# go    : goproxy.cn（七牛）
# maven : 阿里云公共仓库
# brew  : 清华（Homebrew 本体 + bottles + API）
export DEVKIT_PIP_MIRROR="${DEVKIT_PIP_MIRROR:-https://pypi.tuna.tsinghua.edu.cn/simple}"
export DEVKIT_PIP_HOST="${DEVKIT_PIP_HOST:-pypi.tuna.tsinghua.edu.cn}"
export DEVKIT_NPM_MIRROR="${DEVKIT_NPM_MIRROR:-https://registry.npmmirror.com}"
export DEVKIT_NODE_DIST_MIRROR="${DEVKIT_NODE_DIST_MIRROR:-https://npmmirror.com/mirrors/node}"
export DEVKIT_CARGO_MIRROR="${DEVKIT_CARGO_MIRROR:-https://rsproxy.cn}"
export DEVKIT_APT_MIRROR="${DEVKIT_APT_MIRROR:-https://mirrors.tuna.tsinghua.edu.cn}"
export DEVKIT_GO_MIRROR="${DEVKIT_GO_MIRROR:-https://goproxy.cn,direct}"
export DEVKIT_MAVEN_MIRROR="${DEVKIT_MAVEN_MIRROR:-https://maven.aliyun.com/repository/public}"
export DEVKIT_BREW_MIRROR="${DEVKIT_BREW_MIRROR:-https://mirrors.tuna.tsinghua.edu.cn}"
export DEVKIT_RUSTUP_MIRROR="${DEVKIT_RUSTUP_MIRROR:-https://rsproxy.cn}"

# ---------- 颜色 ----------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""; C_BOLD=""; C_OFF=""
fi

# ---------- 日志 ----------
info() { printf '%s[信息]%s %s\n' "$C_CYAN" "$C_OFF" "$*"; }
ok()   { printf '%s[完成]%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
warn() { printf '%s[注意]%s %s\n' "$C_YELLOW" "$C_OFF" "$*"; }
err()  { printf '%s[错误]%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; }
die()  { err "$*"; exit 1; }
step() { printf '\n%s==> %s%s\n' "$C_BOLD" "$*" "$C_OFF"; }
hint() { printf '        %s\n' "$*"; }

# ---------- 基础工具 ----------
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# 所有会产生副作用的命令都过一遍 run：支持 --dry-run 演练
run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '%s[演练]%s %s\n' "$C_YELLOW" "$C_OFF" "$*"
    return 0
  fi
  "$@"
}

is_root() { [ "$(id -u 2>/dev/null)" = "0" ]; }

# 带超时执行：失败/超时都不中断主流程
# 用途：某些命令会莫名其妙挂住（例如 corepack 垫片版 pnpm 会去联网拉包），
#       一键安装脚本绝不能被一条命令卡死。macOS 没有 GNU timeout，这里自己实现。
run_soft() {
  local secs="$1"; shift
  if [ "$DRY_RUN" = "1" ]; then
    printf '%s[演练]%s %s\n' "$C_YELLOW" "$C_OFF" "$*"
    return 0
  fi
  "$@" >/dev/null 2>&1 &
  local pid=$!
  local i=0
  while [ "$i" -lt "$secs" ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid"
      return $?
    fi
    sleep 1
    i=$((i + 1))
  done
  kill -TERM "$pid" 2>/dev/null || true
  sleep 1
  kill -KILL "$pid" 2>/dev/null || true
  warn "命令超时（${secs}s）已放弃：$*"
  return 124
}

# 需要管理员权限执行
sudo_run() {
  if is_root; then
    run "$@"
  elif has_cmd sudo; then
    run sudo "$@"
  else
    die "需要 root 权限，但当前既不是 root 也没有 sudo：$*"
  fi
}

# 交互确认；ASSUME_YES=1 或非交互环境（如管道执行）默认继续
confirm() {
  local prompt="${1:-是否继续？}"
  if [ "$ASSUME_YES" = "1" ]; then return 0; fi
  if [ ! -t 0 ]; then
    warn "非交互环境，默认继续：$prompt"
    return 0
  fi
  printf '%s [Y/n] ' "$prompt"
  local ans=""
  read -r ans || ans=""
  case "$ans" in
    ""|y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# 写文件（带备份），配合 heredoc 使用：
#   write_file /path/to/x <<'EOF' ... EOF
write_file() {
  local f="$1"
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] 将写入 $f"
    cat >/dev/null
    return 0
  fi
  mkdir -p "$(dirname "$f")" 2>/dev/null || true
  if [ -f "$f" ]; then
    local bak="$f.devkit.bak.$(date +%Y%m%d%H%M%S)"
    cp "$f" "$bak" 2>/dev/null && info "已备份原文件 -> $bak"
  fi
  cat > "$f" || die "写入失败：$f"
  ok "已写入 $f"
}

# 需要管理员权限写系统文件
write_file_sudo() {
  local f="$1"
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] 将以 root 写入 $f"
    cat >/dev/null
    return 0
  fi
  if [ -f "$f" ]; then
    sudo_run cp "$f" "$f.devkit.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  fi
  local tmp; tmp="$(mktemp)"
  cat > "$tmp" || die "临时文件写入失败"
  sudo_run mkdir -p "$(dirname "$f")"
  sudo_run cp "$tmp" "$f" || { rm -f "$tmp"; die "写入失败：$f"; }
  rm -f "$tmp"
  ok "已写入 $f"
}

# ---------- 系统识别 ----------
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "mac" ;;
    Linux)  echo "linux" ;;
    *)      echo "unknown" ;;
  esac
}

detect_distro() {
  if [ -r /etc/os-release ]; then
    ( . /etc/os-release; printf '%s' "${ID:-unknown}" )
  else
    echo "unknown"
  fi
}

detect_arch() { uname -m; }

# Debian 系（含 Ubuntu / Deepin / UOS / 麒麟的 deb 版本）
is_debian_like() {
  case "$(detect_distro)" in
    ubuntu|debian|linuxmint|pop|deepin|uos|kali|raspbian) return 0 ;;
    *) return 1 ;;
  esac
}

require_apt() {
  is_debian_like || die "当前发行版 $(detect_distro) 不是 Debian/Ubuntu 系，本脚本的 apt 逻辑不适用。"
  has_cmd apt-get || die "找不到 apt-get。"
}

apt_update() {
  step "刷新 apt 索引"
  sudo_run apt-get update -y || warn "apt-get update 失败，继续尝试（可能是某个源不可用）"
}

apt_install() {
  [ "$#" -gt 0 ] || return 0
  step "apt 安装：$*"
  sudo_run env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" || die "apt 安装失败：$*"
}

# ---------- Node / npm ----------
# 确保 shell 里能用 node/npm：优先当前 PATH，其次加载 nvm
load_node_env() {
  if has_cmd node && has_cmd npm; then return 0; fi
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck disable=SC1090
    . "$NVM_DIR/nvm.sh" >/dev/null 2>&1 || true
  fi
  if ! has_cmd npm && [ -d /usr/local/bin ]; then
    case ":$PATH:" in *":/usr/local/bin:"*) ;; *) PATH="/usr/local/bin:$PATH"; export PATH ;; esac
  fi
  has_cmd npm
}

ensure_node() {
  if load_node_env; then
    info "已检测到 Node $(node -v) / npm $(npm -v)"
    return 0
  fi
  warn "未检测到 Node.js，先自动安装 Node（codex / dsh / claude code 都依赖它）"
  local osname; osname="$(detect_os)"
  local script="$DEVKIT_ROOT/$osname/node.sh"
  [ -f "$script" ] || die "找不到 ${script}，请先手动安装 Node.js"
  DEVKIT_ROOT="$DEVKIT_ROOT" DRY_RUN="$DRY_RUN" ASSUME_YES="$ASSUME_YES" bash "$script" || die "Node.js 安装失败"
  load_node_env || die "Node.js 安装后仍无法在当前会话找到 npm，请重开终端后再试"
}

# 全局安装 npm 包：走国内源；遇到权限不足自动加 sudo
npm_global_install() {
  local pkg="$1"
  ensure_node || return 1
  step "npm 全局安装 ${pkg}（源：${DEVKIT_NPM_MIRROR}）"
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] npm install -g $pkg --registry=$DEVKIT_NPM_MIRROR"
    return 0
  fi
  if npm install -g "$pkg" --registry="$DEVKIT_NPM_MIRROR"; then
    ok "$pkg 安装完成"
    return 0
  fi
  warn "普通权限安装失败，尝试用 sudo 重试"
  local prefix; prefix="$(npm config get prefix 2>/dev/null || echo /usr/local)"
  sudo_run npm install -g "$pkg" --registry="$DEVKIT_NPM_MIRROR" || die "$pkg 安装失败"
  ok "$pkg 安装完成（prefix=${prefix}）"
}

# 安装后校验命令是否可用，并打印版本
verify_cmd() {
  local cmd="$1"
  if has_cmd "$cmd"; then
    ok "$cmd 可用：$("$cmd" --version 2>&1 | head -1)"
    return 0
  fi
  local guess=""
  for guess in "$HOME/.local/bin/$cmd" "$HOME/.cargo/bin/$cmd" "/usr/local/bin/$cmd"; do
    if [ -x "$guess" ]; then
      ok "$cmd 已安装于 ${guess}（当前 PATH 未包含，重开终端或 export PATH 后可用）"
      return 0
    fi
  done
  warn "$cmd 安装后仍未在 PATH 中找到，请重开终端后再验证"
  return 1
}

# 添加 PATH 到 shell 配置（幂等）
append_path_once() {
  local dir="$1"
  local rc="$2"
  [ -f "$rc" ] || return 0
  if grep -q "devkit:path:$dir" "$rc" 2>/dev/null; then return 0; fi
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] 向 $rc 追加 PATH: $dir"
    return 0
  fi
  printf '\n# devkit:path:%s\nexport PATH="%s:$PATH"\n' "$dir" "$dir" >> "$rc"
  ok "已把 $dir 加入 PATH（${rc}）"
}

print_header() {
  printf '\n%s' "$C_BOLD"
  echo "============================================================"
  echo " devkit | $1"
  echo "============================================================"
  printf '%s' "$C_OFF"
}
