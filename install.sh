#!/usr/bin/env bash
# ============================================================
#  devkit 统一入口（macOS / Linux）
#
#  用法：
#    ./install.sh                     # 交互式菜单
#    ./install.sh list                # 列出所有可安装项
#    ./install.sh all                 # 依次安装全部（先配镜像源）
#    ./install.sh node                # 只装 Node.js
#    ./install.sh node python rust    # 一次装多个
#    ./install.sh check               # 体检：打印已装版本
#
#  选项：
#    -y, --yes        全部自动确认（无人值守）
#    -n, --dry-run    演练模式：只打印将要执行的命令，不真正改动系统
#    -h, --help       帮助
# ============================================================
set -u

DEVKIT_ROOT="$(cd "$(dirname "$0")" && pwd)"
export DEVKIT_ROOT
# shellcheck source=lib/common.sh
. "$DEVKIT_ROOT/lib/common.sh"

# 子脚本目录名 = 系统名（mac / linux）
OS_NAME="$(detect_os)"

# 安装顺序有依赖：mirrors 先跑（后续 npm/pip 才会走国内源）
ALL_TOOLS="mirrors node python rust docker jdk codex dsh claude"
# 每个工具的说明（纯展示用）
tool_desc() {
  case "$1" in
    mirrors) echo "配置国内镜像源：apt / pip / npm / yarn / pnpm / cargo / maven / go / brew" ;;
    node)    echo "Node.js LTS（nvm 管理）+ npm 换 npmmirror" ;;
    python)  echo "Python 3 + pip / venv + PyPI 清华源" ;;
    rust)    echo "Rust 工具链（rustup + cargo，走 rsproxy 国内源）" ;;
    docker)  echo "Docker Engine / Desktop + 国内 registry 加速" ;;
    jdk)     echo "OpenJDK 17（Temurin/发行版包）+ Maven 阿里源" ;;
    codex)   echo "OpenAI Codex CLI（npm 全局包 @openai/codex）" ;;
    dsh)     echo "DeepSeek Harness CLI（npm 全局包 @deepseek-ai/dsh）" ;;
    claude)  echo "Claude Code CLI（npm 全局包 @anthropic-ai/claude-code）" ;;
    *)       echo "" ;;
  esac
}

usage() {
  cat <<EOF
devkit 一键环境安装（当前系统：${OS_NAME}）

用法: ./install.sh [选项] [工具名...]
      ./install.sh                    交互式菜单
      ./install.sh all                安装全部
      ./install.sh list               列出可安装项和对应说明

工具名:
$(for t in $ALL_TOOLS; do printf '  %-8s %s\n' "$t" "$(tool_desc "$t")"; done)

选项:
  -y, --yes       全部自动确认
  -n, --dry-run   演练模式，不真正改动系统
  -h, --help      显示帮助

例子:
  ./install.sh mirrors node        # 先配源再装 Node
  ./install.sh -y all              # 无人值守全装
  ./install.sh check               # 打印已安装的版本
EOF
}

list_tools() {
  printf '\n当前系统：%s%s%s\n\n' "$C_BOLD" "$OS_NAME" "$C_OFF"
  for t in $ALL_TOOLS; do
    printf '  %s%-8s%s %s\n' "$C_CYAN" "$t" "$C_OFF" "$(tool_desc "$t")"
  done
  printf '\n用法: ./install.sh <工具名> [工具名...]   或   ./install.sh all\n\n'
}

menu() {
  # 注意：菜单 UI 全部走 stderr，stdout 只输出选中的工具名（调用方用 $(menu) 捕获）
  printf '\n%s请选择要安装的内容%s（可输入多个编号，空格分隔；直接回车=全部）\n\n' "$C_BOLD" "$C_OFF" >&2
  local i=1
  for t in $ALL_TOOLS; do
    printf '  %2d) %-8s %s\n' "$i" "$t" "$(tool_desc "$t")" >&2
    i=$((i + 1))
  done
  printf '\n   q) 退出\n\n> ' >&2
  local ans=""
  read -r ans || ans="q"
  case "$ans" in
    q|Q|quit|exit) printf '\n' >&2; ok "已退出，什么都没做。" >&2; exit 0 ;;
    "") set -- $ALL_TOOLS ;;
    *)  set -- $ans ;;
  esac
  for n in "$@"; do
    case "$n" in
      *[!0-9]*) echo "$n" ;;
      *) i=1; for t in $ALL_TOOLS; do [ "$i" = "$n" ] && echo "$t"; i=$((i + 1)); done ;;
    esac
  done
}

run_tool() {
  local tool="$1"
  local script="$DEVKIT_ROOT/$OS_NAME/$tool.sh"
  if [ ! -f "$script" ]; then
    err "不支持的工具「${tool}」，或缺少脚本 $script"
    echo "可用工具：$ALL_TOOLS"
    return 1
  fi
  print_header "$tool  |  $(tool_desc "$tool")"
  DRY_RUN="$DRY_RUN" ASSUME_YES="$ASSUME_YES" DEVKIT_ROOT="$DEVKIT_ROOT" bash "$script"
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "「${tool}」处理结束"
  else
    err "「${tool}」执行失败（退出码 ${rc}），可单独重跑：./install.sh $tool"
  fi
  return "$rc"
}

# 体检：打印关键工具版本
check_all() {
  print_header "环境体检"
  printf '系统      : %s %s (%s)\n' "$(uname -s)" "$(uname -r)" "$(uname -m)"
  [ "$OS_NAME" = "linux" ] && printf '发行版    : %s\n' "$(detect_distro)"
  printf 'Shell     : %s\n\n' "$SHELL"
  for c in git curl node npm python3 pip3 rustc cargo docker java go mvn codex dsh claude; do
    if has_cmd "$c"; then
      printf '  %s✓%s %-8s %s\n' "$C_GREEN" "$C_OFF" "$c" "$("$c" --version 2>&1 | head -1 | cut -c1-60)"
    else
      printf '  %s·%s %-8s %s\n' "$C_YELLOW" "$C_OFF" "$c" "未安装"
    fi
  done
  printf '\n镜像配置：\n'
  [ -f "$HOME/.npmrc" ] && printf '  npm : %s\n' "$(grep -m1 registry "$HOME/.npmrc" 2>/dev/null | tr -d ' ')"
  for f in "$HOME/.config/pip/pip.conf" "$HOME/.pip/pip.conf" "/etc/pip.conf"; do
    [ -f "$f" ] && printf '  pip : %s\n' "$(grep -m1 index-url "$f" 2>/dev/null | tr -d ' ')"
  done
  [ -f "$HOME/.cargo/config.toml" ] && printf '  cargo: %s\n' "$(grep -m1 'sparse+\|registry =' "$HOME/.cargo/config.toml" 2>/dev/null | tr -d ' ' | head -1)"
  printf '\n'
}

# ---------------- 参数解析 ----------------
WANT_MENU=0
TARGETS=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help|help) usage; exit 0 ;;
    -y|--yes) ASSUME_YES=1 ;;
    -n|--dry-run|--dryrun) DRY_RUN=1 ;;
    list|--list|-l) list_tools; exit 0 ;;
    check|doctor|--check) check_all; exit 0 ;;
    all) TARGETS="$TARGETS $ALL_TOOLS" ;;
    menu) WANT_MENU=1 ;;
    /*) TARGETS="$TARGETS $1" ;;
    *) TARGETS="$TARGETS $1" ;;
  esac
  shift
done
export DRY_RUN ASSUME_YES

if [ -z "$TARGETS" ] && [ "$WANT_MENU" = "0" ]; then
  WANT_MENU=1
fi
if [ "$WANT_MENU" = "1" ]; then
  TARGETS="$(menu)"
fi

if [ "$OS_NAME" = "unknown" ]; then
  die "无法识别的系统：$(uname -s)。本脚本只支持 macOS 与 Linux；Windows 请用 install.ps1"
fi

print_header "devkit | 系统 $OS_NAME"
[ "$DRY_RUN" = "1" ] && warn "演练模式：只显示将要执行的命令"
[ "$ASSUME_YES" = "1" ] && info "自动确认模式"

FAILED=""
DONE=""
for t in $TARGETS; do
  if run_tool "$t"; then DONE="$DONE $t"; else FAILED="$FAILED $t"; fi
done

printf '\n%s================ 总结 ================%s\n' "$C_BOLD" "$C_OFF"
[ -n "$DONE" ]   && ok "成功：$DONE"
[ -n "$FAILED" ] && err "失败：$FAILED （可单独重跑，例如 ./install.sh ${FAILED}）"
printf '体检命令：./install.sh check\n'
printf '重要：新装的工具可能需要%s重开终端%s（或 source ~/.zshrc / ~/.bashrc）才在 PATH 中生效。\n\n' "$C_BOLD" "$C_OFF"
[ -z "$FAILED" ]
