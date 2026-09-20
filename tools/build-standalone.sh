#!/usr/bin/env bash
# ============================================================
#  tools/build-standalone.sh —— 打包"自解压单文件版"
#
#  产出：
#    dist/devkit-standalone.sh   内含整套脚本（tar.gz + base64，自解压后执行）
#    dist/devkit-standalone.ps1  Windows 版（zip + base64）
#
#  为什么需要它：bootstrap 要从 CDN 拉十几个文件，弱网下容易中途失败；
#  单文件版只需要一次请求就能拿到全部内容，弱网/被墙环境成功率更高。
#
#  用法：bash tools/make-manifest.sh && bash tools/build-standalone.sh [版本号]
# ============================================================
set -eu
cd "$(dirname "$0")/.."

REF="${1:-$(git describe --tags --always 2>/dev/null || echo dev)}"
[ -f manifest.sha256 ] || { echo "缺少 manifest.sha256，请先跑：bash tools/make-manifest.sh" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

LIST="$WORK/list"
{
  printf '%s\n' install.sh install.command install.ps1 install.cmd README.md manifest.sha256
  ls lib/*.sh linux/*.sh mac/*.sh windows/*.ps1
} | LC_ALL=C sort -u > "$LIST"

# ---- 打包（COPYFILE_DISABLE 避免 macOS 塞进 ._ 元数据文件）----
COPYFILE_DISABLE=1 tar -czf "$WORK/payload.tar.gz" -T "$LIST"
( cd . && zip -q -X "$WORK/payload.zip" -@ < "$LIST" )

mkdir -p dist
B64_TAR="$WORK/payload.tar.gz.b64"
B64_ZIP="$WORK/payload.zip.b64"
base64 < "$WORK/payload.tar.gz" > "$B64_TAR"
base64 < "$WORK/payload.zip"    > "$B64_ZIP"

# ============================================================
#  dist/devkit-standalone.sh
# ============================================================
{
  cat <<'HEADER'
#!/usr/bin/env bash
# ============================================================
#  devkit 单文件自解压版（由 tools/build-standalone.sh 生成，请勿手改）
#
#  一条命令安装（弱网/被墙环境推荐）：
#    curl -fsSL https://cdn.jsdelivr.net/gh/jianghuifr/install@main/dist/devkit-standalone.sh | bash
#    curl -fsSL .../devkit-standalone.sh | bash -s -- all          # 装全部
#    curl -fsSL .../devkit-standalone.sh | bash -s -- -n mirrors   # 演练
#    curl -fsSL .../devkit-standalone.sh | bash -s -- --keep node  # 保留下载目录
#
#  环境变量：DEVKIT_DIR=/path 指定解压目录；DEVKIT_KEEP=1 保留目录
# ============================================================
set -u

DEVKIT_KEEP="${DEVKIT_KEEP:-0}"
stage="${DEVKIT_DIR:-${TMPDIR:-/tmp}}"; stage="${stage%/}/devkit-standalone-$$"

# 引导自身认识的参数（--keep）不能透传给 install.sh，否则会被当成未知工具名
PASS_ARGS=""
for a in "$@"; do
  case "$a" in --keep) DEVKIT_KEEP=1 ;; *) PASS_ARGS="$PASS_ARGS $a" ;; esac
done

cleanup() { [ "$DEVKIT_KEEP" = "1" ] || rm -rf "$stage"; }
trap cleanup EXIT

echo
echo " devkit 单文件版（内置整套脚本）"
echo " 版本：__DEVKIT_REF__"
echo

mkdir -p "$stage" || { echo "无法创建目录：$stage" >&2; exit 1; }

decode() {
  if base64 --help 2>&1 | grep -q -- '-d'; then base64 -d; else base64 -D; fi
}

PAYLOAD_B64=$(cat <<'DEVKIT_PAYLOAD'
HEADER
  cat "$B64_TAR"
  cat <<'FOOTER'
DEVKIT_PAYLOAD
)

printf '%s' "$PAYLOAD_B64" | decode | tar -xzf - -C "$stage" || {
  echo "解压失败：请确认系统有 base64 / tar / gzip" >&2; exit 1; }

# 解压后校验（有 manifest 就校验，缺工具就跳过，不阻断）
if [ "${DEVKIT_NO_VERIFY:-0}" != "1" ] && [ -f "$stage/manifest.sha256" ]; then
  if command -v sha256sum >/dev/null 2>&1; then
    ( cd "$stage" && sha256sum -c manifest.sha256 --status ) 2>/dev/null \
      && echo " 完整性校验通过" || echo " 注意：校验未全部通过（继续执行）"
  elif command -v shasum >/dev/null 2>&1; then
    ( cd "$stage" && shasum -a 256 -c manifest.sha256 ) >/dev/null 2>&1 \
      && echo " 完整性校验通过" || echo " 注意：校验未全部通过（继续执行）"
  fi
fi

chmod +x "$stage/install.sh" 2>/dev/null || true
chmod +x "$stage"/*/*.sh 2>/dev/null || true
[ -f "$stage/install.command" ] && chmod +x "$stage/install.command" 2>/dev/null || true

echo " 脚本目录：$stage"
echo "────────────────────────────────────────────────────────"
DEVKIT_ROOT="$stage" bash "$stage/install.sh" $PASS_ARGS
rc=$?
echo "────────────────────────────────────────────────────────"
[ "$DEVKIT_KEEP" = "1" ] && echo "已按 --keep 保留目录：$stage" || echo "解压目录已清理（想保留：--keep 或 DEVKIT_KEEP=1）"
exit $rc
FOOTER
} | sed "s|__DEVKIT_REF__|${REF}|" > dist/devkit-standalone.sh
chmod +x dist/devkit-standalone.sh

# ============================================================
#  dist/devkit-standalone.ps1
# ============================================================
{
  cat <<'HEADER'
# ============================================================
#  devkit 单文件自解压版（Windows / PowerShell，由 tools/build-standalone.sh 生成）
#
#  一条命令安装（弱网/被墙环境推荐）：
#    irm https://cdn.jsdelivr.net/gh/jianghuifr/install@main/dist/devkit-standalone.ps1 -OutFile d.ps1
#    .\d.ps1 -Yes all          # 装全部
#    .\d.ps1 -DryRun mirrors   # 演练
#    $env:DEVKIT_ARGS='all'; irm <同上> | iex      # 不想存文件时
#
#  环境变量：DEVKIT_DIR=路径 指定解压目录；DEVKIT_KEEP=1 保留目录
# ============================================================
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Targets,
    [switch]$Yes,
    [switch]$DryRun,
    [switch]$Keep
)
$ErrorActionPreference = 'Stop'
if ($Keep) { $env:DEVKIT_KEEP = '1' }

Write-Host ''
Write-Host ' devkit 单文件版（内置整套脚本）' -ForegroundColor White
Write-Host ' 版本：__DEVKIT_REF__' -ForegroundColor Gray
Write-Host ''

# $env:TEMP 在 Windows 上一定有；这里做兜底，顺便让脚本在 Linux/macOS 的 pwsh 上也能跑（便于测试）
$tmpRoot = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { [System.IO.Path]::GetTempPath() }
$stage = if ($env:DEVKIT_DIR) { $env:DEVKIT_DIR } else { Join-Path $tmpRoot "devkit-standalone-$PID" }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$PAYLOAD_B64 = @'
HEADER
  cat "$B64_ZIP"
  cat <<'FOOTER'
'@

try {
    $zip = Join-Path $stage 'payload.zip'
    [System.IO.File]::WriteAllBytes($zip, [Convert]::FromBase64String(($PAYLOAD_B64 -replace '\s', '')))
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $stage, $true)
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Write-Host ' 已解压完成' -ForegroundColor Green
} catch {
    Write-Host " 解压失败：$($_.Exception.Message)" -ForegroundColor Red
    throw
}

$installPs1 = Join-Path $stage 'install.ps1'
$argList = @()
if ($Targets) { $argList += $Targets }
if ($env:DEVKIT_ARGS) { $argList += ($env:DEVKIT_ARGS -split '\s+' | Where-Object { $_ }) }
if ($Yes) { $argList += '-Yes' }
if ($DryRun) { $argList += '-DryRun' }

Write-Host " 脚本目录：$stage" -ForegroundColor Gray
Write-Host ('─' * 60) -ForegroundColor White
try {
    & $installPs1 @argList
} finally {
    if ($env:DEVKIT_KEEP -eq '1') {
        Write-Host "已按 -Keep 保留目录：$stage" -ForegroundColor Gray
    } else {
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host '解压目录已清理（想保留：-Keep 或 $env:DEVKIT_KEEP=1）' -ForegroundColor Gray
    }
}
FOOTER
} | sed "s|__DEVKIT_REF__|${REF}|" > dist/devkit-standalone.ps1

printf '\n生成完成（版本 %s）：\n' "$REF"
ls -lh dist | tail -n +2 | awk '{printf "  %-32s %s\n", $NF, $5}'
printf '\n提示：单文件版把脚本内容内联在文件里，改完源码要重新生成一次。\n'
