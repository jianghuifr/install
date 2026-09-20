#!/usr/bin/env bash
# ============================================================
#  linux/python.sh —— 安装 Python 3 + pip / venv，并配置 PyPI 国内源
#
#  Ubuntu/Debian 自带的 python3 通常够用，这里补齐 pip / venv / dev 头文件，
#  并处理 PEP 668（externally-managed）带来的 “pip 装不上包” 问题。
# ============================================================
set -u
DEVKIT_ROOT="${DEVKIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=../lib/common.sh
. "$DEVKIT_ROOT/lib/common.sh"

main() {
  print_header "安装 Python 3"
  require_apt

  local pyver=""
  has_cmd python3 && pyver="$(python3 -V 2>&1)"
  if [ -n "$pyver" ] && [ "${DEVKIT_FORCE:-0}" != "1" ]; then
    ok "已安装 $pyver"
  else
    apt_update
  fi

  step "安装 python3 / pip / venv / dev"
  apt_install python3 python3-pip python3-venv python3-dev

  # 先配源，再升级 pip（否则从 pypi.org 拉会超时）
  step "配置 PyPI 国内源"
  bash "$DEVKIT_ROOT/linux/mirrors.sh" pip

  step "升级 pip 工具链"
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] python3 -m pip install -U pip setuptools wheel"
  else
    python3 -m pip install -U pip setuptools wheel 2>&1 | tail -3 || \
      warn "pip 自升级失败（常见于系统 pip + PEP 668 限制），不影响后续使用"
  fi

  # PEP 668：Ubuntu 23.04+ / Debian 12+ 默认禁止 pip 装到系统环境
  if [ "$DRY_RUN" != "1" ] && ls /usr/lib/python3*/EXTERNALLY-MANAGED >/dev/null 2>&1; then
    warn "检测到 PEP 668（externally-managed-environment）限制：pip install 装到系统 Python 会被拒绝。"
    hint "推荐做法：用 venv（python3 -m venv .venv && source .venv/bin/activate）"
    hint "或安装 CLI 工具用 pipx（sudo apt install pipx && pipx ensurepath）"
    if confirm "是否放开限制，允许 pip 直接安装到系统 Python（追加 break-system-packages）？"; then
      if [ "$DRY_RUN" = "1" ]; then
        info "[演练] 追加 break-system-packages = true"
      else
        mkdir -p "$HOME/.config/pip"
        printf '\n# 由 devkit 追加\nbreak-system-packages = true\n' >> "$HOME/.config/pip/pip.conf"
        ok "已允许系统级 pip 安装（风险自负：可能与发行版包冲突）"
      fi
    fi
  fi

  # pipx：装命令行工具的推荐方式
  if ! has_cmd pipx; then
    step "安装 pipx（隔离安装 Python CLI 工具）"
    sudo_run env DEBIAN_FRONTEND=noninteractive apt-get install -y pipx >/dev/null 2>&1 \
      || warn "pipx 安装失败（源里可能没有），可改用 venv"
    if has_cmd pipx; then
      run pipx ensurepath >/dev/null 2>&1 || true
      ok "pipx 已安装"
    fi
  fi

  printf '\n'
  verify_cmd python3 || true
  verify_cmd pip3 || true
  ok "Python 处理完毕。"
  hint "常用：python3 -m venv .venv && source .venv/bin/activate"
}

main "$@"
