#!/usr/bin/env bash
# ============================================================
#  tools/lint-var-cjk.sh —— 禁止「变量紧跟非 ASCII 字符」的写法
#
#  为什么：在非 UTF-8 locale（LC_ALL=C）下，bash 会把中文/全角标点的字节
#  当成变量名的一部分，于是 "「${tool}」" 会被解析成变量 ${tool「} →
#  set -u 报 unbound variable，脚本直接崩。加花括号 "${tool}" 即可避免。
#  PowerShell 同理（汉字是合法变量名字符），所以 .ps1 也一起查。
#
#  用法：bash tools/lint-var-cjk.sh        # 有违规返回 1
# ============================================================
set -u
cd "$(dirname "$0")/.."

FILES=""
for f in install.sh bootstrap.sh lib/*.sh linux/*.sh mac/*.sh tools/*.sh; do
  [ -f "$f" ] && FILES="$FILES $f"
done
for f in install.ps1 bootstrap.ps1 windows/*.ps1 tools/*.ps1; do
  [ -f "$f" ] && FILES="$FILES $f"
done

# 用 perl 按字节扫描：$名字 后面紧跟 0x80-0xFF 即为违规
BAD="$(perl -ne 'print "$ARGV:$.: $_" if /\$[A-Za-z_][A-Za-z0-9_]*[\x80-\xFF]/' $FILES)"

if [ -n "$BAD" ]; then
  echo "发现「变量后紧跟非 ASCII 字符」的写法（会把变量名解析错，请加花括号）：" >&2
  printf '%s\n' "$BAD" >&2
  echo "" >&2
  echo "正确写法：\"\${tool}」处理结束\"   错误写法：\"\${tool}」处理结束\"" >&2
  exit 1
fi

echo "lint 通过：没有「变量后紧跟非 ASCII」的写法"
