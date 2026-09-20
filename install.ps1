# ============================================================
#  devkit 统一入口（Windows / PowerShell）
#
#  用法（在 PowerShell 里执行）：
#    .\install.ps1                     # 交互式菜单
#    .\install.ps1 list                # 列出可安装项
#    .\install.ps1 all                 # 依次安装全部（先配镜像源）
#    .\install.ps1 node                # 只装 Node.js
#    .\install.ps1 node python rust    # 一次装多个
#    .\install.ps1 check               # 体检：打印已装版本
#
#  选项：
#    -Yes      全部自动确认（无人值守）
#    -DryRun   演练模式：只打印要执行的命令
#    -Help     帮助
#
#  如果提示「禁止运行脚本」，用这条命令绕过（不改系统策略）：
#    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 all
#  或直接双击同目录的 install.cmd
# ============================================================
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Targets,
    [switch]$Yes,
    [switch]$DryRun,
    [switch]$Help
)

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
. (Join-Path $root 'windows\common.ps1')

if ($Yes)    { $env:DEVKIT_ASSUME_YES = '1'; $script:DevkitAssumeYes = $true }
if ($DryRun) { $env:DEVKIT_DRY_RUN = '1';    $script:DevkitDryRun = $true }

$AllTools = @('mirrors', 'node', 'python', 'rust', 'docker', 'jdk', 'codex', 'dsh', 'claude')

function Get-ToolDesc {
    param([string]$Tool)
    switch ($Tool) {
        'mirrors' { '配置国内镜像源：pip / npm / yarn / pnpm / cargo / maven / go' }
        'node'    { 'Node.js LTS（winget / 官方 MSI，走 npmmirror）+ npm 换 npmmirror' }
        'python'  { 'Python 3 + pip + PyPI 清华源（winget / 华为镜像安装包）' }
        'rust'    { 'Rust 工具链（rustup + cargo，走 rsproxy 国内源）' }
        'docker'  { 'Docker Desktop + 国内 registry 加速（需要 WSL2）' }
        'jdk'     { 'OpenJDK 17（Temurin）+ Maven 阿里源' }
        'codex'   { 'OpenAI Codex CLI（npm 全局包 @openai/codex）' }
        'dsh'     { 'DeepSeek Harness CLI（npm 全局包 @deepseek-ai/dsh）' }
        'claude'  { 'Claude Code CLI（npm 全局包 @anthropic-ai/claude-code）' }
        default   { '' }
    }
}

function Show-Usage {
    Write-Host @"
devkit 一键环境安装（Windows / PowerShell）

用法: .\install.ps1 [选项] [工具名...]
      .\install.ps1                交互式菜单
      .\install.ps1 all            安装全部
      .\install.ps1 list           列出可安装项

工具名:
"@
    foreach ($t in $AllTools) { Write-Host ("  {0,-8} {1}" -f $t, (Get-ToolDesc $t)) }
    Write-Host @"

选项:
  -Yes      全部自动确认
  -DryRun   演练模式，不真正改动系统
  -Help     显示帮助

例子:
  .\install.ps1 mirrors node      # 先配源再装 Node
  .\install.ps1 -Yes all          # 无人值守全装
  .\install.ps1 check             # 打印已安装的版本
"@
}

function Show-ToolList {
    Write-Host "`n当前系统：Windows $([Environment]::OSVersion.Version)`n"
    foreach ($t in $AllTools) { Write-Host ("  {0,-8} {1}" -f $t, (Get-ToolDesc $t)) }
    Write-Host "`n用法: .\install.ps1 <工具名> [工具名...]   或   .\install.ps1 all`n"
}

function Show-Menu {
    Write-Host "`n请选择要安装的内容（可输入多个编号，空格分隔；直接回车=全部）`n"
    for ($i = 0; $i -lt $AllTools.Count; $i++) {
        Write-Host ("  {0,2}) {1,-8} {2}" -f ($i + 1), $AllTools[$i], (Get-ToolDesc $AllTools[$i]))
    }
    Write-Host "`n   q) 退出`n"
    $ans = Read-Host "> "
    if ($ans -match '^(q|Q|quit|exit)$') { Write-Ok '已退出，什么都没做。'; exit 0 }
    if ([string]::IsNullOrWhiteSpace($ans)) { return $AllTools }
    $picked = @()
    foreach ($n in ($ans -split '\s+')) {
        if ($n -match '^\d+$') {
            $idx = [int]$n - 1
            if ($idx -ge 0 -and $idx -lt $AllTools.Count) { $picked += $AllTools[$idx] }
        } elseif ($n) { $picked += $n }
    }
    return $picked
}

function Invoke-Tool {
    param([string]$Tool)
    $scriptPath = Join-Path $root "windows\$Tool.ps1"
    if (-not (Test-Path $scriptPath)) {
        Write-Err "不支持的工具「${Tool}」，或缺少脚本 $scriptPath"
        Write-Host "可用工具：$($AllTools -join ', ')"
        return $false
    }
    Write-Header "$Tool  |  $(Get-ToolDesc $Tool)"
    try {
        & $scriptPath
        Write-Ok "「${Tool}」处理结束"
        return $true
    } catch {
        Write-Err "「${Tool}」执行失败：$($_.Exception.Message)"
        Write-Hint "可单独重跑：.\install.ps1 $Tool"
        return $false
    }
}

function Show-Check {
    Write-Header '环境体检'
    Write-Host "系统   : Windows $([Environment]::OSVersion.Version)  $env:PROCESSOR_ARCHITECTURE"
    Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
    Write-Host ''
    Update-SessionPath
    foreach ($c in @('git', 'curl', 'node', 'npm', 'python', 'pip', 'rustc', 'cargo', 'docker', 'java', 'go', 'mvn', 'codex', 'dsh', 'claude')) {
        if (Test-Cmd $c) {
            $v = (& $c --version 2>&1 | Select-Object -First 1)
            Write-Host ("  [有] {0,-8} {1}" -f $c, $v) -ForegroundColor Green
        } else {
            Write-Host ("  [无] {0,-8} 未安装" -f $c) -ForegroundColor DarkGray
        }
    }
    Write-Host ''
    Write-Host '镜像配置：'
    $npmrc = Join-Path $env:USERPROFILE '.npmrc'
    if (Test-Path $npmrc) { Write-Host ("  npm  : " + ((Get-Content $npmrc | Select-String 'registry') -join ' ')) }
    $pipini = Join-Path $env:APPDATA 'pip\pip.ini'
    if (Test-Path $pipini) { Write-Host ("  pip  : " + ((Get-Content $pipini | Select-String 'index-url') -join ' ')) }
    $cargocfg = Join-Path $env:USERPROFILE '.cargo\config.toml'
    if (Test-Path $cargocfg) { Write-Host ("  cargo: " + ((Get-Content $cargocfg | Select-String 'rsproxy') | Select-Object -First 1)) }
    Write-Host ''
}

# ---------------- 主流程 ----------------
if ($Help) { Show-Usage; exit 0 }

if ($env:OS -ne 'Windows_NT') {
    Write-Warn '本脚本用于 Windows；macOS / Linux 请用 ./install.sh'
}

if (-not $Targets -or $Targets.Count -eq 0) {
    $Targets = Show-Menu
}
elseif ($Targets.Count -eq 1) {
    switch ($Targets[0]) {
        { $_ -in 'list', '--list', '-l' } { Show-ToolList; exit 0 }
        { $_ -in 'check', 'doctor' }      { Show-Check; exit 0 }
        { $_ -in 'help', '-h', '--help' } { Show-Usage; exit 0 }
        'all' { $Targets = $AllTools }
    }
}
else {
    $expanded = @()
    foreach ($t in $Targets) { if ($t -eq 'all') { $expanded += $AllTools } else { $expanded += $t } }
    $Targets = $expanded
}

Write-Header "devkit | Windows"
if ($script:DevkitDryRun) { Write-Warn '演练模式：只显示将要执行的命令' }
if ($script:DevkitAssumeYes) { Write-Info '自动确认模式' }

$done = @(); $failed = @()
foreach ($t in $Targets) {
    if (Invoke-Tool $t) { $done += $t } else { $failed += $t }
}

Write-Host "`n================ 总结 ================" -ForegroundColor White
if ($done.Count)   { Write-Ok "成功：$($done -join ' ')" }
if ($failed.Count) { Write-Err "失败：$($failed -join ' ') （可单独重跑，例如 .\install.ps1 $($failed[0])）" }
Write-Host '体检命令：.\install.ps1 check'
Write-Host "重要：新装的工具通常需要重开一个终端才会进入 PATH。`n"
if ($failed.Count) { exit 1 }
