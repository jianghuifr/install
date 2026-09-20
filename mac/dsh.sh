#!/usr/bin/env bash
# ============================================================
#  linux/dsh.sh —— 安装 DeepSeek Harness CLI（@deepseek-ai/dsh）
#
#  默认装 npm 上 latest 标签；想装别的 tag/版本：
#    DSH_TAG=alpha ./install.sh dsh
#    DSH_TAG=0.1.5-rc.2 ./install.sh dsh
# ============================================================
set -u
DEVKIT_ROOT="${DEVKIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=../lib/common.sh
. "$DEVKIT_ROOT/lib/common.sh"

DSH_TAG="${DSH_TAG:-}"
CMD="dsh"

main() {
  print_header "安装 DeepSeek Harness (dsh)"
  local pkg="@deepseek-ai/dsh"
  [ -n "$DSH_TAG" ] && pkg="@deepseek-ai/dsh@$DSH_TAG"

  npm_global_install "$pkg"
  verify_cmd "$CMD" || true

  printf '\n'
  ok "dsh 处理完毕。"
  hint "启动：dsh        查看版本：dsh --version"
  hint "首次运行按提示配置模型与 API Key。"
  if [ -z "$DSH_TAG" ]; then
    hint "npm 上 dsh 的 latest/next 为 RC 版本；要装 alpha：DSH_TAG=alpha ./install.sh dsh"
  fi
}

main "$@"
