#!/usr/bin/env bash
# ============================================================
#  lib/mirrors-common.sh —— macOS / Linux 共用的镜像配置逻辑
#  覆盖：pip / npm(+yarn/pnpm) / cargo / go / maven
#  依赖 lib/common.sh 里的日志、write_file 等函数
# ============================================================

# ---------------- pip ----------------
configure_pip() {
  step "配置 pip 国内源（${DEVKIT_PIP_MIRROR}）"
  local body
  body="$(cat <<EOF
[global]
index-url = $DEVKIT_PIP_MIRROR
trusted-host = $DEVKIT_PIP_HOST
timeout = 120
EOF
)"
  # 用户级配置：Linux 用 ~/.config/pip/pip.conf，macOS 两者都写一份更稳
  local targets="$HOME/.config/pip/pip.conf"
  if [ "$(uname -s)" = "Darwin" ]; then
    targets="$targets|$HOME/Library/Application Support/pip/pip.conf"
  fi

  local old_ifs="$IFS"
  IFS='|'
  for f in $targets; do
    IFS="$old_ifs"
    if [ "$DRY_RUN" = "1" ]; then
      info "[演练] 写入 $f"
    else
      mkdir -p "$(dirname "$f")"
      if [ -f "$f" ] && ! grep -q "devkit" "$f" 2>/dev/null; then
        cp "$f" "$f.devkit.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
      fi
      printf '# 由 devkit 生成\n%s\n' "$body" > "$f"
      ok "已写入 $f"
    fi
    IFS='|'
  done
  IFS="$old_ifs"

  # 系统级（多用户/root 也能用）
  if is_root || has_cmd sudo; then
    if confirm "是否同时写入系统级 /etc/pip.conf（对所有用户生效）？"; then
      printf '# 由 devkit 生成\n%s\n' "$body" | write_file_sudo /etc/pip.conf
    fi
  fi
}

# ---------------- npm / yarn / pnpm ----------------
# npm 12 起 `npm config set` 会丢弃 disturl / electron_mirror 等非标准键，
# 所以这些二进制包镜像直接写进 ~/.npmrc（npm 仍会读取并传给 lifecycle 脚本）。
npmrc_binary_mirrors() {
  local f="$HOME/.npmrc"
  local block="# devkit:binary-mirrors:start
disturl=$DEVKIT_NODE_DIST_MIRROR
electron_mirror=https://npmmirror.com/mirrors/electron/
sass_binary_site=https://npmmirror.com/mirrors/node-sass
puppeteer_download_host=https://npmmirror.com/mirrors
# devkit:binary-mirrors:end"
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] 把二进制包镜像追加到 $f"
    return 0
  fi
  touch "$f" 2>/dev/null || { warn "无法写入 $f"; return 0; }
  # 去重：按"键名"删掉旧的同名配置（npm 重写 .npmrc 时会吃掉注释行，
  # 所以不能只依赖 devkit 标记，必须按键名清理，否则重复运行会不断堆积）
  local managed='^[[:space:]]*(disturl|electron_mirror|sass_binary_site|puppeteer_download_host)[[:space:]]*=' 
  grep -v -E "$managed|devkit:binary-mirrors" "$f" > "$f.devkit.tmp" 2>/dev/null || true
  [ -f "$f.devkit.tmp" ] && mv "$f.devkit.tmp" "$f"
  printf '%s\n' "$block" >> "$f"
  ok "已把二进制包镜像写入 ${f}（electron / node-sass / puppeteer / node 头文件）"
}

configure_npm() {
  step "配置 npm 国内源（${DEVKIT_NPM_MIRROR}）"
  if ! load_node_env; then
    warn "未安装 Node/npm，跳过 npm 配置（装完 Node 后重跑 ./install.sh mirrors 即可）"
    return 0
  fi
  if run_soft 30 npm config set registry "$DEVKIT_NPM_MIRROR"; then
    ok "npm registry = $DEVKIT_NPM_MIRROR"
  else
    warn "npm registry 未设置成功，可手动执行：npm config set registry $DEVKIT_NPM_MIRROR"
  fi
  npmrc_binary_mirrors

  if has_cmd yarn; then
    # 用 run_soft：corepack 垫片版的 yarn/pnpm 首次运行会联网拉包，可能长时间卡住
    if run_soft 20 yarn config set registry "$DEVKIT_NPM_MIRROR"; then
      ok "yarn registry 已设置"
    fi
  fi
  if has_cmd pnpm; then
    if run_soft 20 pnpm config set registry "$DEVKIT_NPM_MIRROR"; then
      ok "pnpm registry 已设置"
    else
      warn "pnpm registry 未设置成功（不影响 npm）；手动设置：pnpm config set registry $DEVKIT_NPM_MIRROR"
    fi
  fi
  if has_cmd bun; then
    info "检测到 bun：可在 ~/.bunfig.toml 里加 [install] registry = \"$DEVKIT_NPM_MIRROR\""
  fi
}

# ---------------- cargo / rustup ----------------
configure_cargo() {
  step "配置 Rust 国内源（${DEVKIT_CARGO_MIRROR}）"
  local f="$HOME/.cargo/config.toml"
  if [ -f "$f" ] && ! grep -q "devkit" "$f" 2>/dev/null; then
    warn "$f 已存在，将先备份再写入"
  fi
  write_file "$f" <<EOF
# 由 devkit 生成（crates.io 国内镜像：rsproxy）
[source.crates-io]
replace-with = 'rsproxy-sparse'

[source.rsproxy]
registry = "$DEVKIT_CARGO_MIRROR/crates.io-index"

[source.rsproxy-sparse]
registry = "sparse+$DEVKIT_CARGO_MIRROR/index/"

[registries.rsproxy]
index = "$DEVKIT_CARGO_MIRROR/crates.io-index"

[net]
git-fetch-with-cli = true
EOF
}

# ---------------- go ----------------
configure_go() {
  step "配置 Go 国内源（${DEVKIT_GO_MIRROR}）"
  if ! has_cmd go; then
    warn "未安装 Go，跳过（装完 Go 后重跑 ./install.sh mirrors）"
    return 0
  fi
  run go env -w GOPROXY="$DEVKIT_GO_MIRROR"
  run go env -w GOSUMDB="sum.golang.google.cn"
  ok "GOPROXY = $DEVKIT_GO_MIRROR"
}

# ---------------- maven ----------------
configure_maven() {
  step "配置 Maven 国内源（${DEVKIT_MAVEN_MIRROR}）"
  local f="$HOME/.m2/settings.xml"
  if [ -f "$f" ]; then
    if grep -q "aliyun" "$f" 2>/dev/null; then
      ok "$f 已配置阿里云镜像，跳过"
      return 0
    fi
    warn "$f 已存在且未含阿里云镜像，为避免破坏已有仓库/私服配置，这里不覆盖。"
    hint "如需启用，请手动在 <mirrors> 中加入："
    hint "  <mirror><id>aliyun</id><mirrorOf>central</mirrorOf><url>$DEVKIT_MAVEN_MIRROR</url></mirror>"
    return 0
  fi
  write_file "$f" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!-- 由 devkit 生成 -->
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 https://maven.apache.org/xsd/settings-1.0.0.xsd">
  <mirrors>
    <mirror>
      <id>aliyun-central</id>
      <name>aliyun public</name>
      <mirrorOf>central</mirrorOf>
      <url>$DEVKIT_MAVEN_MIRROR</url>
    </mirror>
  </mirrors>
</settings>
EOF
}
