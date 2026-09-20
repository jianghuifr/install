#!/usr/bin/env bash
# ============================================================
#  mac/mirrors.sh —— macOS 国内镜像配置
#
#  覆盖：Homebrew(本体/bottles/API) / pip / npm / yarn / pnpm / cargo / go / maven
#  也可只配某一项：./mac/mirrors.sh pip
# ============================================================
set -u
DEVKIT_ROOT="${DEVKIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=../lib/common.sh
. "$DEVKIT_ROOT/lib/common.sh"
# shellcheck source=../lib/brew.sh
. "$DEVKIT_ROOT/lib/brew.sh"
# shellcheck source=../lib/mirrors-common.sh
. "$DEVKIT_ROOT/lib/mirrors-common.sh"

main() {
  local section="${1:-all}"
  if [ "$section" != "all" ]; then
    case "$section" in
      brew)  ensure_brew && brew_persist_mirror ;;
      pip)   configure_pip ;;
      npm)   configure_npm ;;
      cargo) configure_cargo ;;
      go)    configure_go ;;
      maven) configure_maven ;;
      *)     die "未知的镜像项：${section}（可选 brew/pip/npm/cargo/go/maven）" ;;
    esac
    return 0
  fi

  print_header "配置国内镜像源（macOS）"
  if ensure_brew; then
    step "Homebrew 镜像变量写入 shell 配置"
    brew_persist_mirror
    ok "以后手动 brew install 也会走 $DEVKIT_BREW_MIRROR"
  else
    warn "Homebrew 不可用，跳过 brew 镜像（pip/npm/cargo 等用户级配置仍会生效）"
  fi

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
