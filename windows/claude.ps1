# ============================================================
#  windows/claude.ps1 —— 安装 Claude Code CLI（@anthropic-ai/claude-code）
#
#  npm 包可从 npmmirror 装；运行需要 Anthropic 接口访问能力。
#  有中转端点时：
#    $env:DEVKIT_ANTHROPIC_BASE_URL='https://your-endpoint'
#    $env:DEVKIT_ANTHROPIC_AUTH_TOKEN='sk-xxx'
#    .\install.ps1 claude
# ============================================================
. (Join-Path $PSScriptRoot 'common.ps1')

Write-Header '安装 Claude Code'

$pkg = if ($env:CLAUDE_PKG) { $env:CLAUDE_PKG } else { '@anthropic-ai/claude-code' }
$ok = Install-NpmGlobal -Package $pkg

if ($env:DEVKIT_ANTHROPIC_BASE_URL) { Set-EnvPersist -Name 'ANTHROPIC_BASE_URL' -Value $env:DEVKIT_ANTHROPIC_BASE_URL }
if ($env:DEVKIT_ANTHROPIC_AUTH_TOKEN) { Set-EnvPersist -Name 'ANTHROPIC_AUTH_TOKEN' -Value $env:DEVKIT_ANTHROPIC_AUTH_TOKEN }
if ($env:DEVKIT_ANTHROPIC_BASE_URL -or $env:DEVKIT_ANTHROPIC_AUTH_TOKEN) {
    Write-Hint '已写入用户环境变量，重开终端生效；注意不要提交到 git'
}

Write-Host ''
Test-CommandInstalled -Command 'claude' | Out-Null
if ($ok) { Write-Ok 'Claude Code 处理完毕。' } else { Write-Err 'Claude Code 安装失败' }
Write-Hint '启动：claude     版本：claude --version'
Write-Hint '国内直连 Anthropic 通常不通，可配 ANTHROPIC_BASE_URL + ANTHROPIC_AUTH_TOKEN'
if (-not $ok) { exit 1 }
