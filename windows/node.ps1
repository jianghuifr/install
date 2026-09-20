# ============================================================
#  windows/node.ps1 —— 安装 Node.js LTS
#
#  顺序：winget（OpenJS.NodeJS.LTS）→ choco（nodejs-lts）
#        → 兜底：从 npmmirror 直接下官方 MSI 静默安装
# ============================================================
. (Join-Path $PSScriptRoot 'common.ps1')

Write-Header '安装 Node.js'

function Test-NodePresent {
    Update-SessionPath
    if (-not (Test-Cmd node)) { return $false }
    $out = (& node -v 2>&1 | Out-String)
    return ($out -match '^v\d+')
}

function Install-NodeByMsi {
    Write-Step '兜底方案：从 npmmirror 下载 Node 官方 MSI'
    $channel = if ($env:NODE_CHANNEL) { "latest-v$($env:NODE_CHANNEL).x" } else { 'latest-v22.x' }
    $base = "$env:DEVKIT_NODE_DIST_MIRROR/$channel"
    $arch = if ($env:PROCESSOR_ARCHITECTURE -match 'ARM64') { 'arm64' } else { 'x64' }

    $html = Get-WebText "$base/"
    $file = $null
    if ($html) {
        $m = [regex]::Matches($html, "node-v[\d.]+-$arch\.msi")
        if ($m.Count -gt 0) { $file = $m[0].Value }
    }
    if (-not $file) {
        Write-Err "无法从 $base 解析 MSI 文件名，请手动下载安装：https://nodejs.org/zh-cn/download"
        return $false
    }

    $out = Join-Path (Get-TempDir) $file
    if (-not (Get-File "$base/$file" $out)) { return $false }
    if ($script:DevkitDryRun) { return $true }
    Write-Step "静默安装 $file"
    $p = Start-Process msiexec.exe -ArgumentList "/i", "`"$out`"", '/qn', '/norestart' -Wait -PassThru
    if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
        Write-Ok "Node 安装完成（${file}）"
        return $true
    }
    Write-Err "MSI 安装失败（退出码 $($p.ExitCode)）"
    return $false
}

$ok = $false
if (Test-NodePresent) {
    Write-Ok "已安装 Node $(node -v) / npm $(npm -v)，跳过"
    $ok = $true
} else {
    if (Test-Winget) { $ok = Install-WingetPackage -Id 'OpenJS.NodeJS.LTS' -Name 'Node.js LTS' }
    if (-not $ok) { $ok = Install-ChocoPackage -Name 'nodejs-lts' -Display 'Node.js LTS' }
    if (-not $ok) { $ok = Install-NodeByMsi }
    Update-SessionPath
    if (-not $ok -and -not (Test-NodePresent)) { Die 'Node.js 安装失败：可手动到 https://nodejs.org/zh-cn 下载 LTS 安装包' }
}

Write-Step "配置 npm 国内源（$env:DEVKIT_NPM_MIRROR）"
if (Test-Cmd npm) {
    Invoke-Soft -Desc "npm config set registry $env:DEVKIT_NPM_MIRROR" -Cmd @("npm","config","set","registry",$env:DEVKIT_NPM_MIRROR) -TimeoutSec 30 | Out-Null
    Set-NpmrcBinaryMirrors
    Write-Ok "npm registry = $env:DEVKIT_NPM_MIRROR"
    if (Test-Cmd yarn) { Invoke-Soft -Desc 'yarn config set registry' -Cmd @("yarn","config","set","registry",$env:DEVKIT_NPM_MIRROR) -TimeoutSec 20 | Out-Null }
    if (Test-Cmd pnpm) { Invoke-Soft -Desc 'pnpm config set registry' -Cmd @("pnpm","config","set","registry",$env:DEVKIT_NPM_MIRROR) -TimeoutSec 20 | Out-Null }
} else {
    Write-Warn '当前会话没找到 npm，请重开终端后执行：npm config set registry https://registry.npmmirror.com'
}

Write-Host ''
if (-not $script:DevkitDryRun) { Test-CommandInstalled -Command 'node' -VersionArg '-v' | Out-Null }
Write-Ok 'Node 处理完毕。'
Write-Hint '新开一个 PowerShell 窗口执行 node -v 验证。'
