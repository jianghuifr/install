# ============================================================
#  windows/codex.ps1 —— 安装 OpenAI Codex CLI（@openai/codex）
#
#  纯国内网络下 npm 包能从 npmmirror 装下来，但运行需要能访问 OpenAI 接口。
#  有中转端点时可带参执行：
#    $env:DEVKIT_CODEX_BASE_URL='https://your-endpoint/v1'
#    $env:DEVKIT_CODEX_API_KEY='sk-xxx'
#    .\install.ps1 codex
# ============================================================
. (Join-Path $PSScriptRoot 'common.ps1')

Write-Header '安装 Codex CLI'

$pkg = if ($env:CODEX_PKG) { $env:CODEX_PKG } else { '@openai/codex' }
$ok = Install-NpmGlobal -Package $pkg

if ($env:DEVKIT_CODEX_BASE_URL) {
    Write-Step '写入 %USERPROFILE%\.codex\config.toml（自定义端点）'
    $cfg = Join-Path $env:USERPROFILE '.codex\config.toml'
    Write-FileSafe -Path $cfg -Content @"
# 由 devkit 生成：自定义 model provider
model_provider = "custom"

[model_providers.custom]
name = "custom"
base_url = "$env:DEVKIT_CODEX_BASE_URL"
env_key = "OPENAI_API_KEY"
wire_api = "responses"
"@
    if ($env:DEVKIT_CODEX_API_KEY) {
        Set-EnvPersist -Name 'OPENAI_API_KEY' -Value $env:DEVKIT_CODEX_API_KEY
        Write-Hint '密钥只写入当前用户环境变量，注意不要提交到 git'
    }
}

Write-Host ''
Test-CommandInstalled -Command 'codex' | Out-Null
if ($ok) { Write-Ok 'Codex CLI 处理完毕。' } else { Write-Err 'Codex CLI 安装失败' }
Write-Hint '启动：codex     版本：codex --version     登录：codex login'
Write-Hint '国内直连 OpenAI 通常不通，需要中转端点或代理。'
if (-not $ok) { exit 1 }
