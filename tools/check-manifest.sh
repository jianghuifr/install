#!/usr/bin/env bash
# ============================================================
#  tools/check-manifest.sh —— 校验 manifest.sha256 与当前仓库内容是否一致
#
#  为什么需要：bootstrap 会逐个文件校验 SHA256，如果 manifest 与内容不一致
#  （常见于"改了文件但忘了重新生成 manifest"，或 tag 打在了 manifest 之前的提交上），
#  用户那边会在校验阶段直接失败。所以 CI 必须先跑这个脚本把问题拦住。
#
#  用法：bash tools/check-manifest.sh     # 不一致返回 1
# ============================================================
set -u
cd "$(dirname "$0")/.."

[ -f manifest.sha256 ] || { echo "缺少 manifest.sha256（先跑 tools/make-manifest.sh）" >&2; exit 1; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else openssl dgst -sha256 "$1" | sed 's/.*= *//'
  fi
}

bad=0
n=0
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  want="${line%% *}"
  path="${line##* }"
  path="${path#\*}"; path="${path# }"
  n=$((n + 1))
  if [ ! -f "$path" ]; then
    echo "  缺失文件：${path}（manifest 里有，仓库里没有）" >&2
    bad=$((bad + 1)); continue
  fi
  got="$(sha256_of "$path")"
  if [ "$got" != "$want" ]; then
    echo "  内容与 manifest 不一致：$path" >&2
    echo "      manifest: ${want:0:16}…" >&2
    echo "      实际    : ${got:0:16}…" >&2
    bad=$((bad + 1))
  fi
done < manifest.sha256

if [ "$bad" -gt 0 ]; then
  echo "" >&2
  echo "$bad/$n 个文件与 manifest.sha256 不一致 —— 跑一下：bash tools/make-manifest.sh" >&2
  echo "（注意：tag 必须打在已经更新过 manifest 的提交上，否则 CDN 上的 bootstrap 会校验失败）" >&2
  exit 1
fi

echo "manifest 校验通过（$n 个文件全部一致）"
