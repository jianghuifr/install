#!/usr/bin/env bash
# ============================================================
#  devkit bootstrap —— 一条命令拉起整套 devkit
#
#  作用：从 CDN / GitHub 镜像把整套脚本拉到临时目录，逐个校验 SHA256，
#        然后交给 install.sh 执行（本文件自身是唯一的引导入口）。
#
#  用法（一行）：
#    curl -fsSL https://cdn.jsdelivr.net/gh/OWNER/devkit@main/bootstrap.sh | bash
#    curl -fsSL https://cdn.jsdelivr.net/gh/OWNER/devkit@main/bootstrap.sh | bash -s -- all
#    curl -fsSL https://cdn.jsdelivr.net/gh/OWNER/devkit@main/bootstrap.sh | bash -s -- -n mirrors
#    curl -fsSL ... | bash -s -- --keep node      # 保留下载目录
#
#  环境变量：
#    DEVKIT_REPO=OWNER/devkit     GitHub 仓库（也可是 gitee 的 用户/仓库）
#    DEVKIT_REF=main              分支 / tag / commit（版本固定建议用 tag，如 v1.0.0）
#    DEVKIT_MIRRORS="前缀1 前缀2"  自定义镜像，按顺序尝试（空格分隔）
#    DEVKIT_DIR=/path             指定下载目录（默认 $TMPDIR/devkit-<随机>）
#    DEVKIT_LOCAL_DIR=/path       直接用本地目录，跳过所有下载（离线 / 内网 / U 盘）
#    DEVKIT_NO_VERIFY=1           跳过 SHA256 校验（不推荐）
#    DEVKIT_ARGS="all"            等价于命令行参数（给 irm | iex 这种没法传参的场景用）
# ============================================================
set -u

DEVKIT_REPO="${DEVKIT_REPO:-jianghuifr/install}"   # GitHub 仓库（可用环境变量覆盖）
DEVKIT_REF="${DEVKIT_REF:-main}"
DEVKIT_DIR="${DEVKIT_DIR:-}"
DEVKIT_KEEP="${DEVKIT_KEEP:-0}"
PROBE_TIMEOUT="${DEVKIT_PROBE_TIMEOUT:-12}"
FETCH_TIMEOUT="${DEVKIT_FETCH_TIMEOUT:-60}"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_C=$'\033[36m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_B=$'\033[1m'; C_0=$'\033[0m'
else
  C_C=""; C_G=""; C_Y=""; C_R=""; C_B=""; C_0=""
fi
i()  { printf '%s[bootstrap]%s %s\n' "$C_C" "$C_0" "$*"; }
ok() { printf '%s[bootstrap]%s %s\n' "$C_G" "$C_0" "$*"; }
w()  { printf '%s[bootstrap]%s %s\n' "$C_Y" "$C_0" "$*"; }
e()  { printf '%s[bootstrap]%s %s\n' "$C_R" "$C_0" "$*" >&2; }
die() { e "$*"; exit 1; }

# ---------------- 下载器 ----------------
have() { command -v "$1" >/dev/null 2>&1; }

fetch() { # fetch <url> <out> [timeout]
  local url="$1" out="$2" tmo="${3:-$FETCH_TIMEOUT}"
  if have curl; then
    curl -fsSL --connect-timeout 8 --max-time "$tmo" --retry 1 -o "$out" "$url" 2>/dev/null && return 0
    return 1
  fi
  if have wget; then
    wget -q -T "$tmo" -O "$out" "$url" 2>/dev/null && return 0
    return 1
  fi
  die "既没有 curl 也没有 wget，无法下载。请先安装其一，或把 devkit 目录拷到本机后用 ./install.sh"
}

# 读一行文本（用于探测镜像连通性）
fetch_text() { # fetch_text <url> [timeout]
  local url="$1" tmo="${2:-$PROBE_TIMEOUT}"
  if have curl; then
    curl -fsSL --connect-timeout 6 --max-time "$tmo" "$url" 2>/dev/null && return 0
    return 1
  fi
  if have wget; then
    wget -q -T "$tmo" -O - "$url" 2>/dev/null && return 0
    return 1
  fi
  return 1
}

sha256_of() { # sha256_of <file>  → 打印 64 位十六进制，失败则空
  local f="$1"
  if have sha256sum; then sha256sum "$f" 2>/dev/null | awk '{print $1}'; return 0; fi
  if have shasum;    then shasum -a 256 "$f" 2>/dev/null | awk '{print $1}'; return 0; fi
  if have openssl;   then openssl dgst -sha256 "$f" 2>/dev/null | sed 's/.*= *//'; return 0; fi
  printf ''
}

# ---------------- 镜像列表 ----------------
mirror_list() {
  if [ -n "${DEVKIT_MIRRORS:-}" ]; then
    printf '%s\n' $DEVKIT_MIRRORS
    return 0
  fi
  # jsDelivr 三个域名互为备份；后面是 GitHub 直连与常用加速前缀（代理站会失效，可用 DEVKIT_MIRRORS 覆盖）
  cat <<EOF
https://cdn.jsdelivr.net/gh/${DEVKIT_REPO}@${DEVKIT_REF}
https://fastly.jsdelivr.net/gh/${DEVKIT_REPO}@${DEVKIT_REF}
https://gcore.jsdelivr.net/gh/${DEVKIT_REPO}@${DEVKIT_REF}
https://testingcf.jsdelivr.net/gh/${DEVKIT_REPO}@${DEVKIT_REF}
https://raw.githubusercontent.com/${DEVKIT_REPO}/${DEVKIT_REF}
https://ghproxy.net/https://raw.githubusercontent.com/${DEVKIT_REPO}/${DEVKIT_REF}
https://ghfast.top/https://raw.githubusercontent.com/${DEVKIT_REPO}/${DEVKIT_REF}
https://gitee.com/${DEVKIT_REPO}/raw/${DEVKIT_REF}
EOF
}

# 找到第一个能提供 manifest.sha256 的镜像
pick_mirror() {
  local m text
  for m in $(mirror_list); do
    printf '  尝试 %s ... ' "$m" >&2
    if text="$(fetch_text "$m/manifest.sha256")" && printf '%s' "$text" | grep -q 'install.sh'; then
      printf '%s✓%s\n' "$C_G" "$C_0" >&2
      printf '%s' "$m"
      return 0
    fi
    printf '%s✗%s\n' "$C_Y" "$C_0" >&2
  done
  return 1
}

# ---------------- 主流程 ----------------
main() {
  local args="$*"
  printf '\n%s devkit 引导安装 %s\n\n' "$C_B" "$C_0"

  # curl | bash 时 stdin 是管道，交互菜单读不到输入；这种情况默认装全部
  if [ -z "$args" ] && [ ! -t 0 ]; then
    w "非交互环境且没指定工具 → 按 all 处理（只装某项：... | bash -s -- node codex）"
    args="all"
  fi

  # 0) 离线模式：直接用本地目录
  if [ -n "${DEVKIT_LOCAL_DIR:-}" ]; then
    [ -f "$DEVKIT_LOCAL_DIR/install.sh" ] || die "DEVKIT_LOCAL_DIR 里没有 install.sh：$DEVKIT_LOCAL_DIR"
    ok "使用本地目录 $DEVKIT_LOCAL_DIR"
    exec bash "$DEVKIT_LOCAL_DIR/install.sh" $args
  fi

  local stage="${DEVKIT_DIR:-${TMPDIR:-/tmp}/devkit-$$}"
  mkdir -p "$stage" || die "无法创建目录 $stage"
  trap '[ "$DEVKIT_KEEP" = "1" ] || rm -rf "'"$stage"'"' EXIT

  # 1) 选镜像（不指定 DEVKIT_MIRRORS 时按顺序探测）
  local mirror=""
  if [ -n "${DEVKIT_BASE_URL:-}" ]; then
    mirror="$DEVKIT_BASE_URL"
    i "使用指定地址：$mirror"
  else
    i "探测可用镜像（仓库 $DEVKIT_REPO@${DEVKIT_REF}）："
    if ! mirror="$(pick_mirror)"; then
      printf '\n'
      e "所有镜像都拿不到 manifest.sha256。"
      e "可能原因：仓库/分支名写错、仓库是私有的、网络受限。"
      e "兜底办法（三选一）："
      e "  1) 用自解压单文件版：curl -fsSL <CDN>/dist/devkit-standalone.sh | bash -s -- all"
      e "  2) 自定义镜像：DEVKIT_MIRRORS=\"https://你的反代/gh/$DEVKIT_REPO@$DEVKIT_REF\" bash bootstrap.sh"
      e "  3) 直接从 GitHub 下载 zip 解压后跑 ./install.sh"
      exit 1
    fi
  fi
  ok "使用镜像：$mirror"

  # 2) 取 manifest
  local mf="$stage/manifest.sha256"
  fetch "$mirror/manifest.sha256" "$mf" || die "下载 manifest.sha256 失败"
  local total; total="$(grep -c '  ' "$mf" 2>/dev/null || echo 0)"
  [ "$total" -gt 0 ] || die "manifest.sha256 内容为空或格式不对"
  i "共 $total 个文件，开始下载到 $stage"

  # 3) 逐文件下载 + 校验；某个文件在首选镜像上失败时，自动换其它镜像重试
  local fail=0 line hash path alt got done_one
  local cands; cands="$mirror $(mirror_list | tr '\n' ' ')"
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    hash="${line%% *}"
    path="${line##* }"
    path="${path#\*}"; path="${path# }"
    mkdir -p "$stage/$(dirname "$path")"
    done_one=0
    for alt in $cands; do
      fetch "$alt/$path" "$stage/$path" 25 || continue
      if [ "${DEVKIT_NO_VERIFY:-0}" != "1" ]; then
        got="$(sha256_of "$stage/$path")"
        if [ -n "$got" ] && [ "$got" != "$hash" ]; then
          w "${path} 在 ${alt} 上校验不一致（期望 ${hash:0:12}…，实际 ${got:0:12}…），换镜像重试"
          rm -f "$stage/$path"
          continue
        fi
      fi
      done_one=1
      break
    done
    if [ "$done_one" != "1" ]; then
      w "所有镜像都取不到（或校验不过）：$path"
      fail=$((fail + 1))
    fi
  done < "$mf"

  if [ "$fail" -gt 0 ]; then
    e "$fail 个文件下载或校验失败，已中止（避免跑到一半缺文件）。"
    e "重试一次通常就好；也可指定其它镜像：DEVKIT_MIRRORS=\"...\" bash bootstrap.sh"
    [ "$DEVKIT_KEEP" = "1" ] && e "已保留目录：$stage"
    exit 1
  fi
  ok "全部 $total 个文件下载完成并校验通过"

  # 4) 交给 install.sh
  chmod +x "$stage/install.sh" 2>/dev/null || true
  chmod +x "$stage"/*/*.sh 2>/dev/null || true
  [ -f "$stage/install.command" ] && chmod +x "$stage/install.command" 2>/dev/null

  printf '\n'
  i "开始执行：install.sh ${args:-（交互菜单）}"
  printf '%s────────────────────────────────────────────────────────%s\n' "$C_B" "$C_0"
  DEVKIT_ROOT="$stage" bash "$stage/install.sh" $args
  local rc=$?
  printf '%s────────────────────────────────────────────────────────%s\n' "$C_B" "$C_0"
  i "脚本目录：$stage"
  [ "$DEVKIT_KEEP" = "1" ] && ok "已按 --keep 保留目录" || i "退出后临时目录会被清理（想保留用 --keep）"
  exit $rc
}

# 参数处理：--keep 只影响引导自身，其余透传给 install.sh
PASS_ARGS=""
for a in "$@"; do
  case "$a" in
    --keep) DEVKIT_KEEP=1 ;;
    *) PASS_ARGS="$PASS_ARGS $a" ;;
  esac
done
[ -n "${DEVKIT_ARGS:-}" ] && PASS_ARGS="$PASS_ARGS $DEVKIT_ARGS"
main $PASS_ARGS
