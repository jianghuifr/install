# ============================================================
#  windows/docker.ps1 —— 安装 Docker Desktop + 国内 registry 加速
#
#  前置条件：Windows 10 21H2+ / Windows 11，开启 WSL2 或 Hyper-V
#  企业使用需注意 Docker Desktop 的授权条款；仅用 CLI 也可考虑 WSL 里装 docker engine
# ============================================================
. (Join-Path $PSScriptRoot 'common.ps1')

Write-Header '安装 Docker（Windows）'

$candidates = @(
    'https://docker.m.daocloud.io',
    'https://docker.1ms.run',
    'https://docker.xuanyuan.me',
    'https://dockerproxy.cn',
    'https://hub.rat.dev'
)
if ($env:DEVKIT_DOCKER_REGISTRIES) { $candidates = $env:DEVKIT_DOCKER_REGISTRIES -split '\s+' }

# ---------- WSL2 检查 ----------
Write-Step '检查 WSL2 / 虚拟化支持'
if (Test-Cmd wsl) {
    $wslOut = (& wsl --status 2>&1 | Out-String)
    if ($wslOut -match '默认版本|Default Version') {
        Write-Ok "WSL 已就绪：$((($wslOut -split "`n") | Where-Object { $_ -match '默认版本|Default Version' }) -join ' ')"
    } else {
        Write-Warn 'wsl --status 输出异常，WSL2 可能未安装'
    }
    if ($wslOut -match 'WSL 2|2') { } # 版本判断较宽松，继续
} else {
    Write-Warn '未检测到 wsl.exe：Docker Desktop 需要 WSL2 后端'
    Write-Hint '管理员 PowerShell 里执行（执行完需要重启）：wsl --install'
    Write-Hint '或启用 Hyper-V：dism /online /enable-feature /featurename:Microsoft-Hyper-V-All /all'
    if (-not (Confirm-Action '是否继续安装 Docker Desktop？')) { Write-Ok '已取消'; exit 0 }
}

# ---------- 安装 ----------
if ((Test-Cmd docker) -and $env:DEVKIT_FORCE -ne '1') {
    Write-Ok "已检测到 docker：$(& docker --version 2>&1 | Select-Object -First 1)"
} else {
    $ok = $false
    if (Test-Winget) { $ok = Install-WingetPackage -Id 'Docker.DockerDesktop' -Name 'Docker Desktop' }
    if (-not $ok) { $ok = Install-ChocoPackage -Name 'docker-desktop' -Display 'Docker Desktop' }
    if (-not $ok) {
        Write-Err 'Docker Desktop 自动安装失败'
        Write-Hint '可手动下载：https://www.docker.com/products/docker-desktop/'
        Write-Hint '国内网络较慢时，建议改用 WSL2 里安装 docker engine（apt 源已可换国内镜像）'
        exit 1
    }
}

# ---------- registry 加速 ----------
Write-Step '配置 registry 国内加速（写入 %USERPROFILE%\.docker\daemon.json）'
$good = @()
foreach ($m in $candidates) {
    if ($script:DevkitDryRun) { $good += $m; continue }
    try {
        $curlExe = Get-CurlExe
        $code = if ($curlExe) { (& $curlExe -s -o NUL -w '%{http_code}' --max-time 6 "$m/v2/" 2>$null) } else { '000' }
        if ($code -in @('200', '401', '403')) { $good += $m; Write-Info "可用加速站：${m}（HTTP ${code}）" }
        else { Write-Info "跳过 ${m}（HTTP ${code}）" }
    } catch { Write-Info "跳过 $m" }
}

if ($good.Count -eq 0) {
    Write-Warn '没有探测到可用的国内加速站，跳过 daemon.json'
} else {
    Write-Hint '注意：镜像会经过第三方中转，私有/敏感镜像请谨慎。'
    $json = ($good | ForEach-Object { "    `"$_`"" }) -join ",`n"
    $cfgPath = Join-Path $env:USERPROFILE '.docker\daemon.json'
    $existing = if (Test-Path $cfgPath) { Get-Content $cfgPath -Raw } else { '' }
    if ($existing -and ($existing -notmatch 'registry-mirrors')) {
        Write-Warn "$cfgPath 已存在自定义配置，未自动覆盖。"
        Write-Hint "请手动加入：`"registry-mirrors`": [ $($good -join ', ') ]"
    } else {
        Write-FileSafe -Path $cfgPath -Content @"
{
  "registry-mirrors": [
$json
  ]
}
"@
        Write-Info '重启 Docker Desktop 后生效（托盘图标右键 -> Restart）'
    }
}

Write-Host ''
if (Test-Cmd docker) { Write-Ok "docker：$(& docker --version 2>&1 | Select-Object -First 1)" }
else { Write-Warn 'docker 命令还没进 PATH，重开终端后再试' }
Write-Ok 'Docker 处理完毕。'
Write-Hint '验证：docker run --rm hello-world'
