# ============================================================
#  devkit bootstrap（Windows / PowerShell）
#
#  作用：从 CDN / GitHub 镜像把整套脚本拉到临时目录，逐个校验 SHA256，
#        然后交给 install.ps1 执行。
#
#  用法（一行，在 PowerShell 里）：
#    irm https://cdn.jsdelivr.net/gh/OWNER/devkit@main/bootstrap.ps1 | iex
#    $env:DEVKIT_ARGS='all'; irm ... | iex                 # 指定要装什么
#    irm ... -OutFile b.ps1; .\b.ps1 -Yes all              # 或存成文件再跑
#
#  环境变量：
#    DEVKIT_REPO=OWNER/devkit     仓库
#    DEVKIT_REF=main              分支 / tag / commit（版本固定建议用 tag）
#    DEVKIT_MIRRORS="前缀1 前缀2"  自定义镜像，按顺序尝试
#    DEVKIT_BASE_URL=前缀         只用一个指定地址
#    DEVKIT_LOCAL_DIR=路径         直接用本地目录，跳过下载（U 盘 / 内网）
#    DEVKIT_ARGS="mirrors node"   装什么（iex 方式没法传参时用）
#    DEVKIT_DIR=路径               指定下载目录
#    DEVKIT_NO_VERIFY=1           跳过 SHA256 校验（不推荐）
#    DEVKIT_KEEP=1                保留下载目录
# ============================================================
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Targets,
    [switch]$Keep,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

$repo = if ($env:DEVKIT_REPO) { $env:DEVKIT_REPO } else { 'jianghuifr/install' }
$ref  = if ($env:DEVKIT_REF)  { $env:DEVKIT_REF }  else { 'main' }
if ($Keep) { $env:DEVKIT_KEEP = '1' }

function Write-I  { param([string]$m) Write-Host "[bootstrap] $m" -ForegroundColor Cyan }
function Write-Ok { param([string]$m) Write-Host "[bootstrap] $m" -ForegroundColor Green }
function Write-W  { param([string]$m) Write-Host "[bootstrap] $m" -ForegroundColor Yellow }
function Write-E  { param([string]$m) Write-Host "[bootstrap] $m" -ForegroundColor Red }

# ---------------- 下载 ----------------
# 找可用的 curl：Windows 上是 curl.exe；Linux/macOS 上是 /usr/bin/curl。
# 注意不能用 PowerShell 的 curl 别名（5.1 里 curl 是 Invoke-WebRequest 的别名）。
function Get-CurlExe {
    $c = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $c = Get-Command curl -ErrorAction SilentlyContinue
    if ($c -and $c.CommandType -eq 'Application') { return $c.Source }
    return $null
}

$script:CurlExe = Get-CurlExe

function Get-Url {
    param([string]$Url, [string]$OutFile, [int]$TimeoutSec = 60)
    try {
        if ($script:CurlExe) {
            & $script:CurlExe -fsSL --connect-timeout 8 --max-time $TimeoutSec --retry 1 -o $OutFile $Url 2>$null
            if ($LASTEXITCODE -eq 0) { return $true }
        }
        $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec $TimeoutSec
        $ProgressPreference = $old
        return $true
    } catch { return $false }
}

function Get-UrlText {
    param([string]$Url, [int]$TimeoutSec = 12)
    try {
        if ($script:CurlExe) {
            $t = & $script:CurlExe -fsSL --connect-timeout 6 --max-time $TimeoutSec $Url 2>$null
            if ($LASTEXITCODE -eq 0) { return ($t | Out-String) }
        }
        $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec
        $ProgressPreference = $old
        $c = $r.Content
        # 非文本类型（如 .sha256 常被当作 octet-stream）时 Content 是 byte[]，
        # 直接拿去 -match 会静默失配，这里统一转成字符串
        if ($c -is [byte[]]) { $c = [System.Text.Encoding]::UTF8.GetString($c) }
        return [string]$c
    } catch { return '' }
}

function Get-Sha256 {
    param([string]$Path)
    try { return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower() } catch { return '' }
}

# ---------------- 镜像列表 ----------------
function Get-Mirrors {
    if ($env:DEVKIT_BASE_URL) { return @($env:DEVKIT_BASE_URL) }
    if ($env:DEVKIT_MIRRORS)  { return ($env:DEVKIT_MIRRORS -split '\s+' | Where-Object { $_ }) }
    return @(
        "https://cdn.jsdelivr.net/gh/$repo@$ref",
        "https://fastly.jsdelivr.net/gh/$repo@$ref",
        "https://gcore.jsdelivr.net/gh/$repo@$ref",
        "https://testingcf.jsdelivr.net/gh/$repo@$ref",
        "https://raw.githubusercontent.com/$repo/$ref",
        "https://ghproxy.net/https://raw.githubusercontent.com/$repo/$ref",
        "https://ghfast.top/https://raw.githubusercontent.com/$repo/$ref",
        "https://gitee.com/$repo/raw/$ref"
    )
}

function Select-Mirror {
    foreach ($m in (Get-Mirrors)) {
        Write-Host "  尝试 $m ... " -NoNewline
        $text = Get-UrlText "$m/manifest.sha256"
        if ($text -and $text -match 'install\.ps1') { Write-Host 'OK' -ForegroundColor Green; return $m }
        Write-Host '失败' -ForegroundColor Yellow
    }
    return $null
}

# ---------------- 主流程 ----------------
Write-Host ''
Write-Host ' devkit 引导安装（Windows）' -ForegroundColor White
Write-Host ''

$stage = $null
try {
    # 0) 离线模式
    if ($env:DEVKIT_LOCAL_DIR) {
        if (-not (Test-Path (Join-Path $env:DEVKIT_LOCAL_DIR 'install.ps1'))) {
            throw "DEVKIT_LOCAL_DIR 里没有 install.ps1：$($env:DEVKIT_LOCAL_DIR)"
        }
        Write-Ok "使用本地目录 $($env:DEVKIT_LOCAL_DIR)"
        $stage = $env:DEVKIT_LOCAL_DIR
    } else {
        $tmpRoot = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { [System.IO.Path]::GetTempPath() }
        $stage = if ($env:DEVKIT_DIR) { $env:DEVKIT_DIR } else { Join-Path $tmpRoot "devkit-$PID" }
        New-Item -ItemType Directory -Path $stage -Force | Out-Null

        # 1) 选镜像
        Write-I "探测可用镜像（仓库 $repo@${ref}）："
        $mirror = Select-Mirror
        if (-not $mirror) {
            Write-E '所有镜像都拿不到 manifest.sha256。'
            Write-E '可能原因：仓库/分支名写错、仓库私有、网络受限。'
            Write-Host '兜底办法（三选一）：'
            Write-Host '  1) 自解压单文件版：irm <CDN>/dist/devkit-standalone.ps1 -OutFile d.ps1; .\d.ps1 -Yes all'
            Write-Host "  2) 自定义镜像：`$env:DEVKIT_MIRRORS='https://你的反代/gh/$repo@$ref'; irm ... | iex"
            Write-Host '  3) 直接下载仓库 zip 解压后跑 .\install.ps1'
            throw '没有可用镜像'
        }
        Write-Ok "使用镜像：$mirror"

        # 2) manifest
        $mf = Join-Path $stage 'manifest.sha256'
        if (-not (Get-Url "$mirror/manifest.sha256" $mf)) { throw '下载 manifest.sha256 失败' }
        $entries = @(Get-Content $mf | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' })
        if ($entries.Count -eq 0) { throw 'manifest.sha256 内容为空' }
        Write-I "共 $($entries.Count) 个文件，开始下载到 $stage"

        # 3) 逐文件下载 + 校验；首选镜像失败时自动换其它镜像重试
        $fail = 0
        $cands = @($mirror) + (Get-Mirrors) | Select-Object -Unique
        foreach ($line in $entries) {
            $parts = $line -split '\s+', 2
            if ($parts.Count -lt 2) { continue }
            $hash = $parts[0].Trim()
            $path = $parts[1].Trim().TrimStart('*').Trim()
            $dest = Join-Path $stage ($path -replace '/', '\')
            $dir = Split-Path -Parent $dest
            if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $okOne = $false
            foreach ($alt in $cands) {
                if (-not (Get-Url "$alt/$path" $dest 25)) { continue }
                if ($env:DEVKIT_NO_VERIFY -ne '1') {
                    $got = Get-Sha256 $dest
                    if ($got -and $got -ne $hash) {
                        Write-W "$path 在 $alt 上校验不一致，换镜像重试"
                        Remove-Item $dest -Force -ErrorAction SilentlyContinue
                        continue
                    }
                }
                $okOne = $true
                break
            }
            if (-not $okOne) { Write-W "所有镜像都取不到（或校验不过）：$path"; $fail++ }
        }
        if ($fail -gt 0) {
            Write-E "$fail 个文件下载或校验失败，已中止（避免跑到一半缺文件）。"
            Write-E '重试一次通常就好；也可换镜像：$env:DEVKIT_MIRRORS="..."; irm ... | iex'
            throw '下载/校验失败'
        }
        Write-Ok "全部 $($entries.Count) 个文件下载完成并校验通过"
    }

    # 4) 交给 install.ps1
    $installPs1 = Join-Path $stage 'install.ps1'
    if (-not (Test-Path $installPs1)) { throw "没找到 $installPs1" }

    $argList = @()
    if ($Targets) { $argList += $Targets }
    if ($env:DEVKIT_ARGS) { $argList += ($env:DEVKIT_ARGS -split '\s+' | Where-Object { $_ }) }
    if ($Yes) { $argList += '-Yes' }

    Write-Host ''
    Write-I ("开始执行：install.ps1 " + ($(if ($argList) { $argList -join ' ' } else { '（交互菜单）' })))
    Write-Host ('─' * 60) -ForegroundColor White
    & $installPs1 @argList
    Write-Host ('─' * 60) -ForegroundColor White
    Write-I "脚本目录：$stage"
}
catch {
    Write-E $_.Exception.Message
    if ($env:DEVKIT_KEEP -ne '1' -and $stage -and (Test-Path $stage) -and -not $env:DEVKIT_LOCAL_DIR) {
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
    throw
}
finally {
    if ($env:DEVKIT_KEEP -ne '1' -and $stage -and (Test-Path $stage) -and -not $env:DEVKIT_LOCAL_DIR) {
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
        Write-I '临时目录已清理（想保留：$env:DEVKIT_KEEP=1）'
    }
}
