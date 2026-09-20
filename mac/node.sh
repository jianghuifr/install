#!/usr/bin/env bash
# ============================================================
#  mac/node.sh —— 安装 Node.js（Homebrew 优先，nvm 兜底）
#
#  brew 的 bottle 走清华镜像，比官网下载快很多；
#  想用 nvm 管理多版本：DEVKIT_NODE_METHOD=nvm ./install.sh node
# ============================================================
set -u
DEVKIT_ROOT="${DEVKIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=../lib/common.sh
# shellcheck source=../lib/mirrors-common.sh
. "$DEVKIT_ROOT/lib/common.sh"
. "$DEVKIT_ROOT/lib/mirrors-common.sh"
# shellcheck source=../lib/brew.sh
. "$DEVKIT_ROOT/lib/brew.sh"

NVM_VERSION="${NVM_VERSION:-v0.40.3}"
NVM_GIT="${NVM_GIT:-https://gitee.com/mirrors/nvm.git}"
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
NODE_METHOD="${DEVKIT_NODE_METHOD:-brew}"

install_via_brew() {
  brew_install node || return 1
  ok "Node 安装完成（brew）"
}

install_via_nvm() {
  step "使用 nvm 安装 Node LTS"
  if [ ! -d "$NVM_DIR/.git" ]; then
    has_cmd git || { warn "缺少 git"; return 1; }
    run git clone --depth 1 --branch "$NVM_VERSION" "$NVM_GIT" "$NVM_DIR" || { warn "克隆 nvm 失败"; return 1; }
  fi
  export NVM_DIR
  export NVM_NODEJS_ORG_MIRROR="$DEVKIT_NODE_DIST_MIRROR"
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] nvm install --lts"
    return 0
  fi
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh" || { warn "nvm 加载失败"; return 1; }
  nvm install --lts || { warn "nvm install 失败"; return 1; }
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$rc" ] || continue
    grep -q 'NVM_DIR' "$rc" 2>/dev/null && continue
    printf '\n# devkit:nvm\nexport NVM_DIR="$HOME/.nvm"\n[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"\n' >> "$rc"
    ok "已写入 nvm 加载片段到 $rc"
  done
  return 0
}

main() {
  print_header "安装 Node.js"
  if has_cmd node && has_cmd npm && [ "${DEVKIT_FORCE:-0}" != "1" ]; then
    ok "已安装 Node $(node -v) / npm $(npm -v)，跳过"
  else
    if [ "$NODE_METHOD" = "nvm" ]; then
      install_via_nvm || install_via_brew || die "Node 安装失败"
    else
      install_via_brew || install_via_nvm || die "Node 安装失败"
    fi
    load_node_env || true
  fi

  if load_node_env; then
    configure_npm
    verify_cmd node || true
    [ "$DRY_RUN" != "1" ] && info "npm 版本：$(npm -v)"
  else
    warn "当前会话仍未找到 node，请重开终端后执行 node -v"
  fi
  printf '\n'
  ok "Node 处理完毕。"
}

main "$@"
