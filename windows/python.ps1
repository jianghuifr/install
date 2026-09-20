# ============================================================
#  windows/python.ps1 —— 安装 Python 3 + pip，配置 PyPI 清华源
#
#  顺序：winget（Python.Python.3.12）→ choco（python312）
#        → 兜底：从华为云镜像下 python-3.x.x-amd64.exe 静默安装
# ============================================================
. (Join-Path $PSScriptRoot 'common.ps1')

Write-Header '安装 Python 3'

$PyVer = if ($env:DEVKIT_PY_VERSION) { $env:DEVKIT_PY_VERSION } else { '3.12' }

function Test-PythonPresent {
    Update-SessionPath
    foreach ($c in @('python', 'python3')) {
        if (Test-Cmd $c) {
            $out = (& $c --version 2>&1 | Out-String)
            if ($out -match 'Python 3\.\d+') { return $true }
        }
    }
    return $false
}

function Install-PythonByExe {
    Write-Step '兜底方案：从华为云镜像下载 Python 官方安装包'
    $index = Get-WebText 'https://mirrors.huaweicloud.com/python/'
    if (-not $index) { Write-Err '无法访问华为云镜像'; return $false }

    $versions = [regex]::Matches($index, ">$PyVer\.(\d+)/<") |
        ForEach-Object { "$PyVer.$($_.Groups[1].Value)" } |
        Sort-Object { [int]($_ -split '\.')[-1] } -Descending
    if (-not $versions -or $versions.Count -eq 0) {
        Write-Err "镜像上没有找到 $PyVer.x 版本"
        return $false
    }
    $ver = $versions[0]
    $arch = if ($env:PROCESSOR_ARCHITECTURE -match 'ARM64') { 'arm64' } else { 'amd64' }
    $file = "python-$ver-$arch.exe"
    $url = "https://mirrors.huaweicloud.com/python/$ver/$file"
    $out = Join-Path (Get-TempDir) $file
    if (-not (Get-File $url $out)) { return $false }
    if ($script:DevkitDryRun) { return $true }

    Write-Step "静默安装 Python ${ver}（当前用户，自动加入 PATH）"
    $args = @('/quiet', 'InstallAllUsers=0', 'PrependPath=1', 'Include_launcher=1',
              'Include_test=0', 'Include_pip=1', 'AssociateFiles=1')
    $p = Start-Process $out -ArgumentList $args -Wait -PassThru
    if ($p.ExitCode -eq 0) { Write-Ok "Python $ver 安装完成"; return $true }
    Write-Err "Python 安装失败（退出码 $($p.ExitCode)）"
    return $false
}

$ok = $false
if (Test-PythonPresent) {
    Update-SessionPath
    $cur = if (Test-Cmd python) { (& python --version 2>&1) } else { (& python3 --version 2>&1) }
    Write-Ok "已安装 ${cur}，跳过"
    $ok = $true
} else {
    if (Test-Winget) { $ok = Install-WingetPackage -Id "Python.Python.$PyVer" -Name "Python $PyVer" }
    if (-not $ok) { $ok = Install-ChocoPackage -Name "python$($PyVer -replace '\.','')" -Display "Python $PyVer" }
    if (-not $ok) { $ok = Install-PythonByExe }
    Update-SessionPath
    if (-not $ok -and -not (Test-PythonPresent)) { Die 'Python 安装失败：可手动到 https://www.python.org/downloads/windows/ 下载安装' }
}

Write-Step "配置 PyPI 国内源（$env:DEVKIT_PIP_MIRROR）"
$pipIni = Join-Path $env:APPDATA 'pip\pip.ini'
$pipConf = @"
[global]
index-url = $env:DEVKIT_PIP_MIRROR
trusted-host = $env:DEVKIT_PIP_HOST
timeout = 120
"@
Write-FileSafe -Path $pipIni -Content $pipConf

Write-Step '升级 pip 工具链'
Invoke-Dry 'python -m pip install -U pip setuptools wheel' {
    & python -m pip install -U pip setuptools wheel 2>&1 | Select-Object -Last 3 | ForEach-Object { Write-Host "    $_" }
}

Write-Host ''
Update-SessionPath
if (-not $script:DevkitDryRun -and (Test-PythonPresent)) {
    Write-Info "python -> $((Get-Command python -ErrorAction SilentlyContinue).Source)"
}
Write-Ok 'Python 处理完毕。'
Write-Hint '建议用虚拟环境：python -m venv .venv ; .\.venv\Scripts\activate'
Write-Hint "装命令行工具可先装 pipx：python -m pip install --user pipx"
