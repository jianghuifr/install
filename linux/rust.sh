#!/usr/bin/env bash
# ============================================================
#  linux/rust.sh —— 安装 Rust 工具链（rustup + cargo）
#
#  国内网络要点：
#    1. rustup-init 二进制从 rsproxy 镜像下载（不走 static.rust-lang.org）
#    2. 设置 RUSTUP_DIST_SERVER / RUSTUP_UPDATE_ROOT 指向 rsproxy
#    3. crates.io 依赖换成 rsproxy 稀疏索引
# ============================================================
set -u
DEVKIT_ROOT="${DEVKIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=../lib/common.sh
. "$DEVKIT_ROOT/lib/common.sh"

CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
export CARGO_HOME RUSTUP_HOME

triple() {
  case "$(detect_arch)" in
    x86_64|amd64)   echo "x86_64-unknown-linux-gnu" ;;
    aarch64|arm64)  echo "aarch64-unknown-linux-gnu" ;;
    armv7l|armv8l)  echo "armv7-unknown-linux-gnueabihf" ;;
    riscv64)        echo "riscv64gc-unknown-linux-gnu" ;;
    *)              echo "" ;;
  esac
}

install_rustup() {
  local t; t="$(triple)"
  [ -n "$t" ] || die "不支持的架构：$(detect_arch)"

  export RUSTUP_DIST_SERVER="$DEVKIT_RUSTUP_MIRROR"
  export RUSTUP_UPDATE_ROOT="$DEVKIT_RUSTUP_MIRROR/rustup"

  step "从 $DEVKIT_RUSTUP_MIRROR 下载 rustup-init（${t}）"
  local url="$DEVKIT_RUSTUP_MIRROR/rustup/dist/$t/rustup-init"
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] curl -fL -o /tmp/rustup-init $url"
  else
    has_cmd curl || apt_install curl
    if ! curl -fL --progress-bar -o /tmp/rustup-init "$url"; then
      warn "rsproxy 下载失败，回退官方安装脚本（速度可能很慢）"
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/rustup-init.sh || die "下载 rustup 安装脚本失败"
      RUSTUP_DIST_SERVER="$RUSTUP_DIST_SERVER" RUSTUP_UPDATE_ROOT="$RUSTUP_UPDATE_ROOT" \
        sh /tmp/rustup-init.sh -y --profile default --default-toolchain stable --no-modify-path || die "rustup 安装失败"
      return 0
    fi
    chmod +x /tmp/rustup-init
  fi

  step "安装 stable 工具链（默认 profile，含 cargo/rustc/rustup）"
  run /tmp/rustup-init -y --profile default --default-toolchain stable --no-modify-path || die "rustup-init 执行失败"

  # 让新终端能直接用
  for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    append_source_once "$rc" "$CARGO_HOME/env"
  done
  if [ -f "$CARGO_HOME/env" ]; then
    # shellcheck disable=SC1091
    . "$CARGO_HOME/env" >/dev/null 2>&1 || true
  fi
}

# 把 . "$CARGO_HOME/env" 写进 rc（幂等）
append_source_once() {
  local rc="$1" target="$2"
  [ -f "$rc" ] || return 0
  grep -q "devkit:cargo-env" "$rc" 2>/dev/null && return 0
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] 向 $rc 追加 . \"$target\""
    return 0
  fi
  printf '\n# devkit:cargo-env\n. "%s"\n' "$target" >> "$rc"
  ok "已把 cargo 环境写入 $rc"
}

main() {
  print_header "安装 Rust 工具链"
  if has_cmd cargo && has_cmd rustc && [ "${DEVKIT_FORCE:-0}" != "1" ]; then
    ok "已安装 $(rustc -V)，跳过（强制重装：DEVKIT_FORCE=1）"
  else
    install_rustup
  fi

  step "配置 crates.io 国内源（rsproxy 稀疏索引）"
  bash "$DEVKIT_ROOT/linux/mirrors.sh" cargo

  step "预装常用组件"
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] rustup component add rustfmt clippy; rustup target list --installed"
  elif has_cmd rustup; then
    rustup component add rustfmt clippy >/dev/null 2>&1 || warn "rustfmt/clippy 安装失败，可稍后手动重试"
    rustup default stable >/dev/null 2>&1 || true
    ok "已安装 rustfmt / clippy"
  fi

  printf '\n'
  verify_cmd rustc || true
  verify_cmd cargo || true
  ok "Rust 处理完毕。新终端执行 rustc -V / cargo -V 验证。"
}

main "$@"
