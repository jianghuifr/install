#!/usr/bin/env bash
# ============================================================
#  mac/rust.sh —— 安装 Rust 工具链（rustup + cargo）
#
#  rustup-init 从 rsproxy 镜像下载，RUSTUP_DIST_SERVER 也指向 rsproxy，
#  crates.io 依赖换成 rsproxy 稀疏索引。
#  想用 brew 装：DEVKIT_RUST_METHOD=brew ./install.sh rust
# ============================================================
set -u
DEVKIT_ROOT="${DEVKIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=../lib/common.sh
. "$DEVKIT_ROOT/lib/common.sh"
# shellcheck source=../lib/brew.sh
. "$DEVKIT_ROOT/lib/brew.sh"

CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
export CARGO_HOME RUSTUP_HOME
RUST_METHOD="${DEVKIT_RUST_METHOD:-rustup}"

triple() {
  case "$(detect_arch)" in
    arm64)  echo "aarch64-apple-darwin" ;;
    x86_64) echo "x86_64-apple-darwin" ;;
    *)      echo "" ;;
  esac
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

install_via_rustup() {
  local t; t="$(triple)"
  [ -n "$t" ] || die "不支持的架构：$(detect_arch)"

  export RUSTUP_DIST_SERVER="$DEVKIT_RUSTUP_MIRROR"
  export RUSTUP_UPDATE_ROOT="$DEVKIT_RUSTUP_MIRROR/rustup"

  step "从 $DEVKIT_RUSTUP_MIRROR 下载 rustup-init（${t}）"
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] curl -fL -o /tmp/rustup-init $DEVKIT_RUSTUP_MIRROR/rustup/dist/$t/rustup-init"
  else
    if ! curl -fL --progress-bar -o /tmp/rustup-init "$DEVKIT_RUSTUP_MIRROR/rustup/dist/$t/rustup-init"; then
      warn "rsproxy 下载失败，回退官方脚本（速度可能很慢）"
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/rustup-init.sh || die "下载 rustup 失败"
      sh /tmp/rustup-init.sh -y --profile default --default-toolchain stable --no-modify-path || die "rustup 安装失败"
      return 0
    fi
    chmod +x /tmp/rustup-init
  fi

  step "安装 stable 工具链"
  run /tmp/rustup-init -y --profile default --default-toolchain stable --no-modify-path || die "rustup-init 执行失败"

  for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.profile"; do
    append_source_once "$rc" "$CARGO_HOME/env"
  done
  if [ -f "$CARGO_HOME/env" ]; then
    # shellcheck disable=SC1091
    . "$CARGO_HOME/env" >/dev/null 2>&1 || true
  fi
}

main() {
  print_header "安装 Rust 工具链"
  if has_cmd cargo && has_cmd rustc && [ "${DEVKIT_FORCE:-0}" != "1" ]; then
    ok "已安装 $(rustc -V)，跳过"
  elif [ "$RUST_METHOD" = "brew" ]; then
    brew_install rust || die "brew install rust 失败"
  else
    install_via_rustup || { warn "rustup 方案失败，尝试 brew"; brew_install rust || die "Rust 安装失败"; }
  fi

  step "配置 crates.io 国内源"
  bash "$DEVKIT_ROOT/mac/mirrors.sh" cargo

  step "预装常用组件"
  if [ "$DRY_RUN" = "1" ]; then
    info "[演练] rustup component add rustfmt clippy"
  elif has_cmd rustup; then
    rustup component add rustfmt clippy >/dev/null 2>&1 || warn "rustfmt/clippy 安装失败"
    ok "已安装 rustfmt / clippy"
  fi

  printf '\n'
  verify_cmd rustc || true
  verify_cmd cargo || true
  ok "Rust 处理完毕。新终端执行 rustc -V 验证。"
}

main "$@"
