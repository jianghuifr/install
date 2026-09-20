#!/usr/bin/env bash
# ============================================================
#  linux/node.sh —— 安装 Node.js LTS（nvm 管理）
#
#  优先方案：从 gitee 镜像克隆 nvm，再用 npmmirror 的 node 二进制安装
#  兜底方案：直接从 npmmirror 下载官方 tar.xz 解压到 ~/.local/node
#  完成后：npm registry 指向 npmmirror
# ============================================================
set -u
DEVKIT_ROOT="${DEVKIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=../lib/common.sh
# shellcheck source=../lib/mirrors-common.sh
. "$DEVKIT_ROOT/lib/common.sh"
. "$DEVKIT_ROOT/lib/mirrors-common.sh"

NVM_VERSION="${NVM_VERSION:-v0.40.3}"
NVM_GIT="${NVM_GIT:-https://gitee.com/mirrors/nvm.git}"   # GitHub 慢时用 gitee 镜像
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
NODE_CHANNEL="${NODE_CHANNEL:-lts}"                        # lts / current / 22 等

node_ok() { has_cmd node && has_cmd npm; }

install_via_nvm() {
  step "方案一：nvm（${NVM_GIT}）"
  if [ ! -d "$NVM_DIR/.git" ]; then
    if ! has_cmd git; then
      warn "没有 git，无法克隆 nvm，转方案二"
      return 1
    fi
    run git clone --depth 1 --branch "$NVM_VERSION" "$NVM_GIT" "$NVM_DIR" || {
      warn "克隆 nvm 失败（${NVM_GIT}），转方案二"; return 1; }
  fi
  export NVM_DIR
  if [ "$DRY_RUN" != "1" ]; then
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh" || { warn "nvm 加载失败，转方案二"; return 1; }
  fi

  # 关键：node 二进制走 npmmirror，否则 nodejs.org 在国内极慢
  export NVM_NODEJS_ORG_MIRROR="$DEVKIT_NODE_DIST_MIRROR"
  export NVM_IOJS_ORG_MIRROR="$DEVKIT_NODE_DIST_MIRROR"
  step "nvm 安装 Node（${NODE_CHANNEL}，源：${DEVKIT_NODE_DIST_MIRROR}）"
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] nvm install --$NODE_CHANNEL"
  else
    nvm install "--$NODE_CHANNEL" || { warn "nvm install 失败，转方案二"; return 1; }
    nvm alias default "$(nvm version | sed 's/^v//' | head -1)" >/dev/null 2>&1 || true
  fi

  # 写入 shell 配置，让新终端自动加载 nvm
  for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    [ -f "$rc" ] || continue
    if ! grep -q 'NVM_DIR' "$rc" 2>/dev/null; then
      if [ "$DRY_RUN" = "1" ]; then
        info "[演练] 向 $rc 写入 nvm 加载片段"
      else
        cat >> "$rc" <<'EOF'

# devkit:nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
EOF
        ok "已写入 nvm 加载片段到 $rc"
      fi
    fi
  done
  return 0
}

install_via_tarball() {
  step "方案二：直接从 npmmirror 下载 Node 官方二进制"
  local arch; arch="$(detect_arch)"
  local narch
  case "$arch" in
    x86_64|amd64) narch="x64" ;;
    aarch64|arm64) narch="arm64" ;;
    armv7l|armv8l) narch="armv7l" ;;
    *) warn "不认识的架构 $arch"; return 1 ;;
  esac

  local channel="latest-v22.x"
  case "$NODE_CHANNEL" in
    lts|"") channel="latest-v22.x" ;;
    current) channel="latest" ;;
    *) channel="latest-v${NODE_CHANNEL}.x" ;;
  esac

  local base="$DEVKIT_NODE_DIST_MIRROR/$channel"
  local dest="$HOME/.local/node"
  local file=""

  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] 从 $base 列目录，取 node-*-linux-$narch.tar.xz，解压到 $dest"
    return 0
  fi

  file="$(curl -fsSL --max-time 20 "$base/" 2>/dev/null \
          | grep -o "node-v[0-9.]*-linux-$narch\.tar\.xz" | head -1)"
  if [ -z "$file" ]; then
    warn "无法从 $base 解析文件名，尝试盲取目录（若失败请手动下载 Node）"
    return 1
  fi
  info "下载 $file"
  mkdir -p "$dest"
  if ! curl -fL --progress-bar -o "/tmp/$file" "$base/$file"; then
    warn "下载失败：$base/$file"; return 1
  fi
  tar -xJf "/tmp/$file" -C "$dest" --strip-components=1 || { warn "解压失败（可能需要 xz：sudo apt install xz-utils）"; return 1; }
  rm -f "/tmp/$file"

  append_path_once "$dest/bin" "$HOME/.bashrc"
  append_path_once "$dest/bin" "$HOME/.zshrc"
  case ":$PATH:" in *":$dest/bin:"*) ;; *) PATH="$dest/bin:$PATH"; export PATH ;; esac
  ok "Node 已解压到 $dest"
  return 0
}

main() {
  print_header "安装 Node.js"
  if node_ok && [ "${DEVKIT_FORCE:-0}" != "1" ]; then
    ok "已安装 Node $(node -v) / npm $(npm -v)，跳过（强制重装请加 DEVKIT_FORCE=1）"
  else
    install_via_nvm || install_via_tarball || die "Node.js 安装失败：请检查网络，或手动安装后重跑"
    load_node_env || true
  fi

  if load_node_env; then
    configure_npm
    verify_cmd node || true
    verify_cmd npm || true
    if [ "$DRY_RUN" != "1" ]; then
      info "npm 版本：$(npm -v)"
    fi
  else
    warn "当前会话仍未找到 node，请重开终端后执行：node -v"
  fi
  printf '\n'
  ok "Node 处理完毕。新终端里执行 node -v 验证。"
}

main "$@"
