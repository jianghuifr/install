#!/usr/bin/env bash
# ============================================================
#  linux/codex.sh —— 安装 OpenAI Codex CLI（@openai/codex）
#
#  纯国内网络下 npm 包本身能从 npmmirror 装下来，
#  但 *运行* 时需要能访问 OpenAI 接口（或自建/中转端点）。
#  若已有中转端点，可这样带参安装，脚本会顺手写好 ~/.codex/config.toml：
#    DEVKIT_CODEX_BASE_URL=https://your-endpoint/v1 \
#    DEVKIT_CODEX_API_KEY=sk-xxx ./install.sh codex
# ============================================================
set -u
DEVKIT_ROOT="${DEVKIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=../lib/common.sh
. "$DEVKIT_ROOT/lib/common.sh"

PKG="${CODEX_PKG:-@openai/codex}"
CMD="codex"

write_codex_config() {
  local base="${DEVKIT_CODEX_BASE_URL:-}" key="${DEVKIT_CODEX_API_KEY:-}"
  [ -n "$base" ] || return 0
  step "写入 ~/.codex/config.toml（自定义端点）"
  write_file "$HOME/.codex/config.toml" <<EOF
# 由 devkit 生成：自定义 model provider
model_provider = "custom"

[model_providers.custom]
name = "custom"
base_url = "$base"
env_key = "OPENAI_API_KEY"
wire_api = "responses"
EOF
  if [ -n "$key" ]; then
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
      [ -f "$rc" ] || continue
      grep -q "devkit:codex-key" "$rc" 2>/dev/null && continue
      if [ "$DRY_RUN" = "1" ]; then
        info "[演练] 向 $rc 写入 OPENAI_API_KEY"
      else
        printf '\n# devkit:codex-key\nexport OPENAI_API_KEY="%s"\n' "$key" >> "$rc"
      fi
    done
    ok "已把 API Key 写入 shell 配置（仅本机，注意不要提交到 git）"
  fi
}

main() {
  print_header "安装 Codex CLI"
  npm_global_install "$PKG"
  verify_cmd "$CMD" || true
  write_codex_config

  printf '\n'
  ok "Codex CLI 处理完毕。"
  hint "启动：codex      查看版本：codex --version     登录：codex login"
  hint "用 ChatGPT 账号登录需要能访问 OpenAI；国内一般要配中转端点或代理。"
  hint "配自定义端点：export OPENAI_BASE_URL=https://your-endpoint/v1 后重跑本脚本。"
}

main "$@"
