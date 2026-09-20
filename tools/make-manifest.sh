#!/usr/bin/env bash
# ============================================================
#  tools/make-manifest.sh —— 生成 manifest.sha256
#
#  只收录"要分发给用户"的文件（入口 / 库 / 各系统子脚本 / README），
#  不收录 bootstrap、tools、dist、.github —— 引导脚本无法校验自身。
#
#  用法：bash tools/make-manifest.sh
#  GitHub Actions 在打 tag 时会自动跑一次，见 .github/workflows/release.yml
# ============================================================
set -eu
cd "$(dirname "$0")/.."

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else openssl dgst -sha256 "$1" | sed 's/.*= *//'
  fi
}

# 注意：不要收录 install.cmd —— jsDelivr 拒绝代理 .cmd/.bat（HTTP 403），
# 收录它会让走 CDN 的 bootstrap 永远校验失败。它只在"下载 zip / Pages"路径里提供。
LIST="$(mktemp)"
{
  printf '%s\n' install.sh install.command install.ps1 README.md
  ls lib/*.sh linux/*.sh mac/*.sh windows/*.ps1
} | LC_ALL=C sort -u > "$LIST"

OUT="manifest.sha256"
: > "$OUT"
n=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  printf '%s  %s\n' "$(sha256_of "$f")" "$f" >> "$OUT"
  n=$((n + 1))
done < "$LIST"
rm -f "$LIST"

echo "已生成 ${OUT}（$n 个文件）"
echo "校验方式：sha256sum -c manifest.sha256    # Linux"
echo "          shasum -a 256 -c manifest.sha256   # macOS"
