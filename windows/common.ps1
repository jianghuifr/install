# ============================================================
#  windows/common.ps1 —— Windows 公共函数库
#  被 install.ps1 与 windows/*.ps1 通过 dot-source 加载
#  文件以 UTF-8 with BOM 保存，保证 Windows PowerShell 5.1 下中文不乱码
# ============================================================

$script:DevkitRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$env:DEVKIT_ROOT = $script:DevkitRoot

$script:DevkitDryRun    = ($env:DEVKIT_DRY_RUN -eq '1')
$script:DevkitAssumeYes = ($env:DEVKIT_ASSUME_YES -eq '1')

# ---------- 镜像地址（可用环境变量覆盖） ----------
if (-not $env:DEVKIT_PIP_MIRROR)        { $env:DEVKIT_PIP_MIRROR = 'https://pypi.tuna.tsinghua.edu.cn/simple' }
if (-not $env:DEVKIT_PIP_HOST)          { $env:DEVKIT_PIP_HOST = 'pypi.tuna.tsinghua.edu.cn' }
if (-not $env:DEVKIT_NPM_MIRROR)        { $env:DEVKIT_NPM_MIRROR = 'https://registry.npmmirror.com' }
if (-not $env:DEVKIT_NODE_DIST_MIRROR)  { $env:DEVKIT_NODE_DIST_MIRROR = 'https://npmmirror.com/mirrors/node' }
if (-not $env:DEVKIT_CARGO_MIRROR)      { $env:DEVKIT_CARGO_MIRROR = 'https://rsproxy.cn' }
if (-not $env:DEVKIT_GO_MIRROR)         { $env:DEVKIT_GO_MIRROR = 'https://goproxy.cn,direct' }
if (-not $env:DEVKIT_MAVEN_MIRROR)      { $env:DEVKIT_MAVEN_MIRROR = 'https://maven.aliyun.com/repository/public' }
if (-not $env:DEVKIT_RUSTUP_MIRROR)     { $env:DEVKIT_RUSTUP_MIRROR = 'https://rsproxy.cn' }

# ---------- 日志 ----------
function Write-Info { param([string]$Message) Write-Host "[信息] $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "[完成] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[注意] $Message" -ForegroundColor Yellow }
function Write-Err  { param([string]$Message) Write-Host "[错误] $Message" -ForegroundColor Red }
function Write-Step { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor White }
function Write-Hint { param([string]$Message) Write-Host "        $Message" -ForegroundColor DarkGray }
function Die        { param([string]$Message) Write-Err $Message; exit 1 }

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor White
    Write-Host " devkit | $Title" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor White
}

# ---------- 基础工具 ----------
# 临时目录：Windows 上 $env:TEMP 一定有，这里加兜底以便在其它平台测试
function Get-TempDir {
    if ($env:TEMP) { return $env:TEMP }
    if ($env:TMPDIR) { return $env:TMPDIR }
    return [System.IO.Path]::GetTempPath()
}

function Test-Cmd {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 演练模式包装：DryRun 时只打印不执行
function Invoke-Dry {
    param([string]$Desc, [scriptblock]$Action)
    if ($script:DevkitDryRun) { Write-Info "[演练] $Desc"; return }
    & $Action
}

# 带超时执行外部命令：超时或失败都不中断主流程
# 用途：corepack 垫片版 pnpm / yarn 首次运行会联网拉包，可能长时间卡住
function Invoke-Soft {
    param([string]$Desc, [string[]]$Cmd, [int]$TimeoutSec = 20)
    if ($script:DevkitDryRun) { Write-Info "[演练] $Desc"; return $true }
    try {
        # 统一用 cmd /c 启动：Windows 上 npm/yarn/pnpm 是 .cmd 垫片，
        # 直接 Start-Process 会因为找不到可执行文件而失败，cmd 能按 PATHEXT 解析
        $cmdline = ($Cmd | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
        $p = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" `
             -ArgumentList @('/c', $cmdline) -NoNewWindow -PassThru -ErrorAction Stop
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch { }
            Write-Warn "命令超时（${TimeoutSec}s）已放弃：$Desc"
            return $false
        }
        if ($p.ExitCode -eq 0) { return $true }
        Write-Warn "$Desc 失败（退出码 $($p.ExitCode)）"
        return $false
    } catch {
        Write-Warn "$Desc 执行失败：$($_.Exception.Message)"
        return $false
    }
}

function Confirm-Action {
    param([string]$Prompt = '是否继续？')
    if ($script:DevkitAssumeYes) { return $true }
    $ans = Read-Host "$Prompt [Y/n]"
    if ([string]::IsNullOrWhiteSpace($ans)) { return $true }
    return ($ans -match '^(y|Y|yes|YES)$')
}

# 写用户级环境变量（永久 + 当前会话）
function Set-EnvPersist {
    param([string]$Name, [string]$Value)
    if ($script:DevkitDryRun) { Write-Info "[演练] 设置用户环境变量 $Name=$Value"; return }
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
    Set-Item -Path "env:$Name" -Value $Value
    Write-Ok "已设置环境变量 $Name"
}

# 加入用户 PATH（幂等）
function Add-UserPath {
    param([string]$Dir)
    if (-not (Test-Path $Dir)) { return }
    $old = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($old -and ($old -split ';' -contains $Dir)) { return }
    if ($script:DevkitDryRun) { Write-Info "[演练] 把 $Dir 加入用户 PATH"; return }
    $new = if ([string]::IsNullOrEmpty($old)) { $Dir } else { "$old;$Dir" }
    [Environment]::SetEnvironmentVariable('Path', $new, 'User')
    $env:Path = "$env:Path;$Dir"
    Write-Ok "已把 $Dir 加入用户 PATH（重开终端生效）"
}

# 写文件（自动备份；UTF-8 无 BOM，适合配置文件）
function Write-FileSafe {
    param([string]$Path, [string]$Content)
    if ($script:DevkitDryRun) { Write-Info "[演练] 写入 $Path"; return }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (Test-Path $Path) {
        $bak = "$Path.devkit.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item $Path $bak -Force
        Write-Info "已备份原文件 -> $bak"
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
    Write-Ok "已写入 $Path"
}

# 找可用的 curl：Windows 上是 curl.exe；其它平台是 /usr/bin/curl
# （不能用 PowerShell 的 curl 别名，5.1 里它指向 Invoke-WebRequest）
function Get-CurlExe {
    $c = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $c = Get-Command curl -ErrorAction SilentlyContinue
    if ($c -and $c.CommandType -eq 'Application') { return $c.Source }
    return $null
}

# 下载文件：优先 curl，否则 Invoke-WebRequest
function Get-File {
    param([string]$Url, [string]$OutFile)
    if ($script:DevkitDryRun) { Write-Info "[演练] 下载 $Url -> $OutFile"; return $true }
    Write-Info "下载 $Url"
    $curlExe = Get-CurlExe
    if ($curlExe) {
        & $curlExe -fL --retry 2 --connect-timeout 20 -o $OutFile $Url
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    try {
        $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 120
        $ProgressPreference = $old
        return $true
    } catch {
        Write-Warn "下载失败：$($_.Exception.Message)"
        return $false
    }
}

# 取网页文本（用于从镜像目录列表里解析文件名）
function Get-WebText {
    param([string]$Url)
    if ($script:DevkitDryRun) {
        # 演练模式：不发请求，返回一份"假目录列表"，让后续解析/下载流程能走通并被打印出来
        Write-Info "[演练] 读取 $Url"
        return @'
node-v22.20.0-x64.msi node-v22.20.0-arm64.msi
>3.10.99/< >3.11.99/< >3.12.99/< >3.13.99/<
python-3.12.99-amd64.exe
OpenJDK17U-jdk_x64_windows_hotspot_17.0.13_11.msi
OpenJDK17U-jdk_aarch64_windows_hotspot_17.0.13_11.msi
OpenJDK21U-jdk_x64_windows_hotspot_21.0.5_11.msi
OpenJDK21U-jdk_aarch64_windows_hotspot_21.0.5_11.msi
>3.9.9/<
'@
    }
    try {
        $curlExe = Get-CurlExe
        if ($curlExe) {
            $t = & $curlExe -fsSL --max-time 25 $Url 2>$null
            if ($LASTEXITCODE -eq 0) { return ($t | Out-String) }
        }
        $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 30
        $ProgressPreference = $old
        $c = $r.Content
        if ($c -is [byte[]]) { $c = [System.Text.Encoding]::UTF8.GetString($c) }
        return [string]$c
    } catch {
        return ''
    }
}

# ---------- winget / choco ----------
function Test-Winget { return (Test-Cmd winget) }

function Install-WingetPackage {
    param([string]$Id, [string]$Name = $Id)
    if (-not (Test-Winget)) { return $false }
    Write-Step "winget 安装 ${Name}（${Id}）"
    if ($script:DevkitDryRun) { Write-Info "[演练] winget install --id $Id -e"; return $true }
    & winget install --id $Id -e --source winget --accept-package-agreements --accept-source-agreements `
        --disable-interactivity 2>&1 | ForEach-Object { Write-Host "    $_" }
    if ($LASTEXITCODE -eq 0) { Write-Ok "$Name 安装完成"; return $true }
    Write-Warn "winget 安装 $Name 失败（退出码 ${LASTEXITCODE}）"
    return $false
}

function Install-ChocoPackage {
    param([string]$Name, [string]$Display = $Name)
    if (-not (Test-Cmd choco)) { return $false }
    Write-Step "choco 安装 $Display"
    if ($script:DevkitDryRun) { Write-Info "[演练] choco install $Name -y"; return $true }
    & choco install $Name -y --no-progress 2>&1 | ForEach-Object { Write-Host "    $_" }
    if ($LASTEXITCODE -eq 0) { Write-Ok "$Display 安装完成"; return $true }
    Write-Warn "choco 安装 $Display 失败"
    return $false
}

# 刷新当前会话 PATH，让刚装好的工具立刻可用
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

# ---------- Node / npm ----------
function Test-NodeReady { return ((Test-Cmd node) -and (Test-Cmd npm)) }

function Ensure-Node {
    if (Test-NodeReady) { Write-Info "已检测到 Node $(node -v) / npm $(npm -v)"; return $true }
    Write-Warn "未检测到 Node.js，先自动安装（codex / dsh / claude code 都依赖它）"
    Update-SessionPath
    if (Test-NodeReady) { return $true }
    $nodeScript = Join-Path $script:DevkitRoot 'windows\node.ps1'
    if (-not (Test-Path $nodeScript)) { Die "找不到 $nodeScript" }
    & $nodeScript
    Update-SessionPath
    return (Test-NodeReady)
}

function Install-NpmGlobal {
    param([string]$Package)
    if (-not (Ensure-Node)) { Die "Node 不可用，无法安装 $Package" }
    Write-Step "npm 全局安装 ${Package}（源：$env:DEVKIT_NPM_MIRROR）"
    if ($script:DevkitDryRun) { Write-Info "[演练] npm install -g $Package --registry=$env:DEVKIT_NPM_MIRROR"; return $true }
    & npm install -g $Package --registry="$env:DEVKIT_NPM_MIRROR"
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "npm 安装失败，尝试用国内源 + 强制重装"
        & npm install -g $Package --registry="$env:DEVKIT_NPM_MIRROR" --force
    }
    if ($LASTEXITCODE -eq 0) { Write-Ok "$Package 安装完成"; return $true }
    Write-Err "$Package 安装失败"
    return $false
}

# npm 12 起 `npm config set` 会丢弃 disturl / electron_mirror 等非标准键，
# 这些二进制包镜像直接写进 ~/.npmrc（npm 仍会读取并传给 lifecycle 脚本）
function Set-NpmrcBinaryMirrors {
    $npmrc = Join-Path $env:USERPROFILE '.npmrc'
    if ($script:DevkitDryRun) { Write-Info "[演练] 把二进制包镜像追加到 $npmrc"; return }
    $block = @(
        '# devkit:binary-mirrors:start',
        "disturl=$env:DEVKIT_NODE_DIST_MIRROR",
        'electron_mirror=https://npmmirror.com/mirrors/electron/',
        'sass_binary_site=https://npmmirror.com/mirrors/node-sass',
        'puppeteer_download_host=https://npmmirror.com/mirrors',
        '# devkit:binary-mirrors:end'
    )
    $lines = @()
    if (Test-Path $npmrc) {
        # 按"键名"去重（npm 重写 .npmrc 时会吃掉注释行，只靠标记会不断堆积）
        foreach ($l in (Get-Content $npmrc)) {
            if ($l -match '^\s*(disturl|electron_mirror|sass_binary_site|puppeteer_download_host)\s*=') { continue }
            if ($l -match 'devkit:binary-mirrors') { continue }
            $lines += $l
        }
    }
    $lines += $block
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($npmrc, [string[]]$lines, $utf8)
    Write-Ok "已把二进制包镜像写入 ${npmrc}（electron / node-sass / puppeteer / node 头文件）"
}

function Test-CommandInstalled {
    param([string]$Command, [string]$VersionArg = '--version')
    Update-SessionPath
    if (Test-Cmd $Command) {
        $v = (& $Command $VersionArg 2>&1 | Select-Object -First 1)
        Write-Ok "$Command 可用：$v"
        return $true
    }
    $guess = Join-Path $env:APPDATA 'npm'
    if (Test-Path (Join-Path $guess "$Command.cmd")) {
        Write-Ok "$Command 已安装于 ${guess}（重开终端后可用）"
        return $true
    }
    Write-Warn "$Command 未在 PATH 中找到，请重开终端后再验证"
    return $false
}
