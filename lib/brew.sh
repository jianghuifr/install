#!/usr/bin/env bash
# ============================================================
#  lib/brew.sh —— macOS 上 Homebrew 相关的公共逻辑
#  （Homebrew 本体、bottles、API 全部指向清华镜像）
# ============================================================

# 导出 Homebrew 国内镜像环境变量（必须在任何 brew 命令之前）
brew_use_mirror() {
  local m="$DEVKIT_BREW_MIRROR"
  export HOMEBREW_BREW_GIT_REMOTE="$m/git/homebrew/brew.git"
  export HOMEBREW_CORE_GIT_REMOTE="$m/git/homebrew/homebrew-core.git"
  export HOMEBREW_API_DOMAIN="$m/homebrew-bottles/api"
  export HOMEBREW_BOTTLE_DOMAIN="$m/homebrew-bottles"
  export HOMEBREW_NO_ANALYTICS=1
  export HOMEBREW_NO_ENV_HINTS=1
  # cask 大文件（Docker/OrbStack 等）仍走官方 CDN，这里不用管
  info "Homebrew 镜像：${m}（bottles/API/git 全部走国内）"
}

brew_prefix_for_arch() {
  case "$(uname -m)" in
    arm64) echo "/opt/homebrew" ;;
    *)     echo "/usr/local" ;;
  esac
}

brew_shellenv_path() {
  printf '%s/bin/brew' "$(brew_prefix_for_arch)"
}

# 把 brew shellenv 写入 zprofile / bash_profile（幂等）
brew_persist_shellenv() {
  local brew_bin; brew_bin="$(brew_shellenv_path)"
  local line="eval \"\$($brew_bin shellenv)\""
  local rc
  for rc in "$HOME/.zprofile" "$HOME/.bash_profile"; do
    if [ "$rc" = "$HOME/.zprofile" ] && [ ! -f "$rc" ] && [ "${SHELL##*/}" = "bash" ]; then
      continue
    fi
    touch "$rc" 2>/dev/null || continue
    grep -q "devkit:brew" "$rc" 2>/dev/null && continue
    if [ "$DRY_RUN" = "1" ]; then
      info "[演练] 向 $rc 写入 brew shellenv"
    else
      printf '\n# devkit:brew\n%s\n' "$line" >> "$rc"
      ok "已把 brew 环境写入 $rc"
    fi
  done
}

# 把镜像环境变量写入 shell rc，保证以后手动 brew install 也走国内源
brew_persist_mirror() {
  local m="$DEVKIT_BREW_MIRROR"
  local rc
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$rc" ] || [ "$rc" = "$HOME/.zshrc" ] || continue
    grep -q "devkit:brew-mirror" "$rc" 2>/dev/null && continue
    if [ "$DRY_RUN" = "1" ]; then
      info "[演练] 向 $rc 写入 Homebrew 镜像变量"
      continue
    fi
    cat >> "$rc" <<EOF

# devkit:brew-mirror
export HOMEBREW_BREW_GIT_REMOTE="$m/git/homebrew/brew.git"
export HOMEBREW_CORE_GIT_REMOTE="$m/git/homebrew/homebrew-core.git"
export HOMEBREW_API_DOMAIN="$m/homebrew-bottles/api"
export HOMEBREW_BOTTLE_DOMAIN="$m/homebrew-bottles"
export HOMEBREW_NO_ANALYTICS=1
EOF
    ok "已写入 Homebrew 镜像变量到 $rc"
  done
}

# 安装 Homebrew（不走 raw.githubusercontent，直接从清华 git 克隆）
install_homebrew() {
  local prefix; prefix="$(brew_prefix_for_arch)"
  step "未检测到 Homebrew，准备安装到 ${prefix}（源：清华镜像）"
  if ! confirm "是否安装 Homebrew？"; then
    warn "跳过 Homebrew 安装"
    return 1
  fi
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] git clone --depth=1 $DEVKIT_BREW_MIRROR/git/homebrew/brew.git $prefix"
    return 0
  fi
  has_cmd git || die "需要先有 git：安装了 Xcode Command Line Tools 才有（xcode-select --install）"
  sudo_run mkdir -p "$prefix"
  sudo_run chown -R "$(whoami)" "$prefix"
  git clone --depth=1 "$DEVKIT_BREW_MIRROR/git/homebrew/brew.git" "$prefix" || {
    warn "克隆 brew 失败，请检查网络或改为手动安装：https://mirrors.tuna.tsinghua.edu.cn/help/homebrew/"
    return 1
  }
  eval "$("$prefix/bin/brew" shellenv)" || true
  ok "Homebrew 安装完成：$(brew --version | head -1)"
  brew_persist_shellenv
  brew_persist_mirror
}

# 确保 brew 可用（必要时安装）
ensure_brew() {
  brew_use_mirror
  if has_cmd brew; then return 0; fi
  local p; p="$(brew_shellenv_path)"
  if [ -x "$p" ]; then eval "$("$p" shellenv)"; return 0; fi
  install_homebrew || return 1
  has_cmd brew || { warn "brew 安装后仍不可用"; return 1; }
}

# 安装 formula（已安装则跳过）
brew_install() {
  local pkg="$1"
  ensure_brew || return 1
  if brew list --formula "$pkg" >/dev/null 2>&1 && [ "${DEVKIT_FORCE:-0}" != "1" ]; then
    ok "brew formula $pkg 已安装，跳过"
    return 0
  fi
  step "brew install $pkg"
  run brew install "$pkg" || { warn "brew install $pkg 失败"; return 1; }
  return 0
}

brew_install_cask() {
  local pkg="$1"
  ensure_brew || return 1
  if brew list --cask "$pkg" >/dev/null 2>&1 && [ "${DEVKIT_FORCE:-0}" != "1" ]; then
    ok "brew cask $pkg 已安装，跳过"
    return 0
  fi
  step "brew install --cask ${pkg}（大文件，国内可能较慢）"
  run brew install --cask "$pkg" || { warn "brew install --cask $pkg 失败"; return 1; }
  return 0
}

# 需要 sudo 才能装 cask 时先要密码（brew 会自己弹提示，这里只做说明）
brew_note_sudo() {
  hint "提示：个别 cask 会要求输入管理员密码，请在终端里照提示输入。"
}
