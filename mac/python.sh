#!/usr/bin/env bash
# ============================================================
#  mac/python.sh —— 安装 Python 3 + pip + pipx，配置 PyPI 国内源
#
#  macOS 自带 /usr/bin/python3（Xcode CLT，版本较老），
#  这里用 Homebrew 装一份新的并放到 PATH 前面。
#  指定版本：DEVKIT_PY_VERSION=3.12 ./install.sh python
# ============================================================
set -u
DEVKIT_ROOT="${DEVKIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=../lib/common.sh
. "$DEVKIT_ROOT/lib/common.sh"
# shellcheck source=../lib/brew.sh
. "$DEVKIT_ROOT/lib/brew.sh"

PY_VERSION="${DEVKIT_PY_VERSION:-}"

main() {
  print_header "安装 Python 3"

  local formula="python" opt_dir=""
  if [ -n "$PY_VERSION" ]; then
    formula="python@$PY_VERSION"
    opt_dir="$(brew_prefix_for_arch)/opt/$formula/libexec/bin"
  fi

  if [ -n "$PY_VERSION" ]; then
    brew_install "$formula" || die "$formula 安装失败"
    step "把 $formula 加入 PATH（keg-only，需要手动加）"
    append_path_once "$opt_dir" "$HOME/.zshrc"
    append_path_once "$opt_dir" "$HOME/.bashrc"
    case ":$PATH:" in *":$opt_dir:"*) ;; *) [ -d "$opt_dir" ] && PATH="$opt_dir:$PATH" && export PATH ;; esac
  else
    brew_install python || die "python 安装失败"
  fi

  brew_install pipx || warn "pipx 安装失败（可选，用于隔离安装 Python CLI 工具）"

  step "配置 PyPI 国内源"
  bash "$DEVKIT_ROOT/mac/mirrors.sh" pip

  step "升级 pip 工具链"
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] python3 -m pip install -U pip setuptools wheel"
  else
    python3 -m pip install -U pip setuptools wheel 2>&1 | tail -3 || warn "pip 升级失败，可忽略"
    has_cmd pipx && pipx ensurepath >/dev/null 2>&1 || true
  fi

  printf '\n'
  if [ "$DRY_RUN" != "1" ]; then
    info "python3 -> $(command -v python3)"
    info "$(python3 -V 2>&1)"
  fi
  verify_cmd pipx || true
  ok "Python 处理完毕。"
  hint "常用：python3 -m venv .venv && source .venv/bin/activate"
}

main "$@"
