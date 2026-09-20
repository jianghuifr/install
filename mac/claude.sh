#!/usr/bin/env bash
# ============================================================
#  linux/claude.sh —— 安装 Claude Code CLI（@anthropic-ai/claude-code）
#
#  npm 包本身可从 npmmirror 装；运行需要 Anthropic 接口访问能力。
#  有中转端点时可带参安装，脚本会写入 shell 配置：
#    DEVKIT_ANTHROPIC_BASE_URL=https://your-endpoint \
#    DEVKIT_ANTHROPIC_AUTH_TOKEN=sk-xxx ./install.sh claude
# ============================================================
set -u
DEVKIT_ROOT="${DEVKIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=../lib/common.sh
. "$DEVKIT_ROOT/lib/common.sh"

PKG="${CLAUDE_PKG:-@anthropic-ai/claude-code}"
CMD="claude"

write_claude_env() {
  local base="${DEVKIT_ANTHROPIC_BASE_URL:-}" tok="${DEVKIT_ANTHROPIC_AUTH_TOKEN:-}"
  [ -n "$base$tok" ] || return 0
  step "写入 Anthropic 端点/密钥到 shell 配置"
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
    grep -q "devkit:claude-env" "$rc" 2>/dev/null && continue
    if [ "$DRY_RUN" = "1" ]; then
      info "[演练] 向 $rc 写入 ANTHROPIC_* 变量"
      continue
    fi
    {
      printf '\n# devkit:claude-env\n'
      [ -n "$base" ] && printf 'export ANTHROPIC_BASE_URL="%s"\n' "$base"
      [ -n "$tok" ]  && printf 'export ANTHROPIC_AUTH_TOKEN="%s"\n' "$tok"
    } >> "$rc"
    ok "已写入 ${rc}（注意不要提交到 git）"
  done
}

main() {
  print_header "安装 Claude Code"
  npm_global_install "$PKG"
  verify_cmd "$CMD" || true
  write_claude_env

  printf '\n'
  ok "Claude Code 处理完毕。"
  hint "启动：claude     查看版本：claude --version"
  hint "国内直连 Anthropic 通常不通；可配中转：ANTHROPIC_BASE_URL + ANTHROPIC_AUTH_TOKEN"
}

main "$@"
