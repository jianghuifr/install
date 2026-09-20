# ============================================================
#  windows/dsh.ps1 —— 安装 DeepSeek Harness CLI（@deepseek-ai/dsh）
#
#  默认装 npm 上 latest 标签；想装别的 tag/版本：
#    $env:DSH_TAG='alpha'; .\install.ps1 dsh
# ============================================================
. (Join-Path $PSScriptRoot 'common.ps1')

Write-Header '安装 DeepSeek Harness (dsh)'

$pkg = '@deepseek-ai/dsh'
if ($env:DSH_TAG) { $pkg = "@deepseek-ai/dsh@$($env:DSH_TAG)" }

$ok = Install-NpmGlobal -Package $pkg

Write-Host ''
Test-CommandInstalled -Command 'dsh' | Out-Null
if ($ok) { Write-Ok 'dsh 处理完毕。' } else { Write-Err 'dsh 安装失败' }
Write-Hint '启动：dsh     版本：dsh --version'
Write-Hint '首次运行按提示配置模型与 API Key。'
if (-not $env:DSH_TAG) { Write-Hint "npm 上 dsh 的 latest 为 RC；要装 alpha：`$env:DSH_TAG='alpha'; .\install.ps1 dsh" }
if (-not $ok) { exit 1 }
