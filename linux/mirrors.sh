#!/usr/bin/env bash
# ============================================================
#  linux/mirrors.sh —— 把常见开发工具的下载源换成国内镜像
#
#  覆盖：apt(系统源) / pip / npm / yarn / pnpm / cargo / go / maven
#  所有改动前都会备份原文件（*.devkit.bak.时间戳）
#  可用环境变量覆盖镜像地址，例如：
#    DEVKIT_APT_MIRROR=https://mirrors.aliyun.com ./install.sh mirrors
#
#  也可只配某一项：
#    ./linux/mirrors.sh pip        # 只配 PyPI
#    ./linux/mirrors.sh cargo      # 只配 crates.io
# ============================================================
set -u
DEVKIT_ROOT="${DEVKIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=../lib/common.sh
. "$DEVKIT_ROOT/lib/common.sh"
# shellcheck source=../lib/mirrors-common.sh
. "$DEVKIT_ROOT/lib/mirrors-common.sh"

DISTRO="$(detect_distro)"
ARCH="$(detect_arch)"

# ---------------- apt ----------------
apt_ubuntu_like() {
  case "$DISTRO" in ubuntu|linuxmint|pop|kali|raspbian) return 0 ;; *) return 1 ;; esac
}

apt_repo_path() {
  # arm64 的 Ubuntu 在 ports 仓库
  if apt_ubuntu_like; then
    case "$ARCH" in
      aarch64|arm64|armv7l|armv8l) echo "ubuntu-ports" ;;
      *) echo "ubuntu" ;;
    esac
  else
    echo "debian"
  fi
}

configure_apt() {
  require_apt || return 0
  local path; path="$(apt_repo_path)"
  local base="$DEVKIT_APT_MIRROR/$path"
  local sec="$DEVKIT_APT_MIRROR/debian-security"

  local codename=""
  if [ -r /etc/os-release ]; then
    codename="$( . /etc/os-release; printf '%s' "${VERSION_CODENAME:-}" )"
  fi
  [ -n "$codename" ] || codename="$(lsb_release -sc 2>/dev/null || true)"
  [ -n "$codename" ] || { warn "无法确定发行版代号，跳过 apt 源替换"; return 0; }

  step "配置 apt 国内源（$DISTRO / $codename / $ARCH → ${base}）"
  if ! confirm "将替换系统 apt 源为 ${base}，原文件会备份。继续？"; then
    info "跳过 apt 源替换"
    return 0
  fi

  # --- 情况 A：Ubuntu 24.04+ / Debian 12+ 的 deb822 格式 ---
  local deb822=""
  local f
  for f in /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/debian.sources; do
    [ -f "$f" ] && deb822="$f" && break
  done

  if [ -n "$deb822" ]; then
    info "检测到 deb822 格式源文件：$deb822"
    local suites="" main_suites="" sec_suites=""
    suites="$(grep -h '^Suites:' "$deb822" 2>/dev/null | sed 's/^Suites:[[:space:]]*//' | tr '\n' ' ')"
    if [ -n "$suites" ]; then
      main_suites="$(printf '%s' "$suites" | tr ' ' '\n' | grep -v security | tr '\n' ' ' | sed 's/ *$//')"
      sec_suites="$(printf '%s' "$suites" | tr ' ' '\n' | grep security | tr '\n' ' ' | sed 's/ *$//')"
    fi
    [ -n "$main_suites" ] || main_suites="$codename ${codename}-updates ${codename}-backports"
    [ -n "$sec_suites" ]  || sec_suites="${codename}-security"

    local comps="main restricted universe multiverse"
    [ "$DISTRO" = "debian" ] && comps="main contrib non-free non-free-firmware"
    local keyring="/usr/share/keyrings/ubuntu-archive-keyring.gpg"
    [ "$DISTRO" = "debian" ] && keyring="/usr/share/keyrings/debian-archive-keyring.gpg"

    write_file_sudo "$deb822" <<EOF
# 由 devkit 于 $(date '+%Y-%m-%d %H:%M:%S') 生成，原文件已备份
Types: deb
URIs: $base/
Suites: $main_suites
Components: $comps
Signed-By: $keyring

Types: deb
URIs: $sec/
Suites: $sec_suites
Components: $comps
Signed-By: $keyring
EOF
    if [ "$DISTRO" = "debian" ] && [ -f /etc/apt/sources.list ]; then
      write_file_sudo /etc/apt/sources.list <<'EOF'
# 由 devkit 生成：Debian 12+ 已改用 /etc/apt/sources.list.d/debian.sources
EOF
    fi
    apt_update
    return 0
  fi

  # --- 情况 B：传统 one-line 格式 ---
  info "使用传统 sources.list 格式"
  if [ "$DISTRO" = "debian" ]; then
    write_file_sudo /etc/apt/sources.list <<EOF
# 由 devkit 于 $(date '+%Y-%m-%d %H:%M:%S') 生成，原文件已备份
deb $base/ $codename main contrib non-free non-free-firmware
deb $base/ ${codename}-updates main contrib non-free non-free-firmware
deb $sec/ ${codename}-security main contrib non-free non-free-firmware
EOF
  else
    write_file_sudo /etc/apt/sources.list <<EOF
# 由 devkit 于 $(date '+%Y-%m-%d %H:%M:%S') 生成，原文件已备份
deb $base/ $codename main restricted universe multiverse
deb $base/ ${codename}-updates main restricted universe multiverse
deb $base/ ${codename}-backports main restricted universe multiverse
deb $sec/ ${codename}-security main restricted universe multiverse
EOF
  fi
  apt_update
}

# 支持只跑其中一项：mirrors.sh pip / cargo / npm / go / maven / apt
main() {
  local section="${1:-all}"
  if [ "$section" != "all" ]; then
    case "$section" in
      apt)    configure_apt ;;
      pip)    configure_pip ;;
      npm)    configure_npm ;;
      cargo)  configure_cargo ;;
      go)     configure_go ;;
      maven)  configure_maven ;;
      *)      die "未知的镜像项：${section}（可选 apt/pip/npm/cargo/go/maven）" ;;
    esac
    return 0
  fi

  print_header "配置国内镜像源（Linux）"
  case "$DISTRO" in
    ubuntu|debian|linuxmint|pop|kali|raspbian) configure_apt ;;
    *) warn "发行版 $DISTRO 不在 apt 自动处理范围内，跳过系统源（pip/npm/cargo 等仍会配置）" ;;
  esac
  configure_pip
  configure_npm
  configure_cargo
  configure_go
  configure_maven
  printf '\n'
  ok "镜像源配置完成。若某个源不可用，可用环境变量替换后重跑，例如："
  hint "DEVKIT_PIP_MIRROR=https://mirrors.aliyun.com/pypi/simple ./install.sh mirrors"
}

main "$@"
