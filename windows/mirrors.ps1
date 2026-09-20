# ============================================================
#  windows/mirrors.ps1 —— Windows 国内镜像源配置
#
#  覆盖：pip / npm / yarn / pnpm / cargo / go / maven
#  只改当前用户目录下的配置，不动系统级设置；改动前自动备份
#
#  也可只配某一项（供其它脚本调用）：
#    .\windows\mirrors.ps1 -Section pip
#    .\windows\mirrors.ps1 -Section cargo
# ============================================================
param([string]$Section = 'all')
. (Join-Path $PSScriptRoot 'common.ps1')

if ($Section -eq 'all') { Write-Header '配置国内镜像源（Windows）' }

$doPip    = ($Section -eq 'all' -or $Section -eq 'pip')
$doNpm    = ($Section -eq 'all' -or $Section -eq 'npm')
$doCargo  = ($Section -eq 'all' -or $Section -eq 'cargo')
$doGo     = ($Section -eq 'all' -or $Section -eq 'go')
$doMaven  = ($Section -eq 'all' -or $Section -eq 'maven')

# ---------------- pip ----------------
if ($doPip) {
    Write-Step "配置 pip 国内源（$env:DEVKIT_PIP_MIRROR）"
    $pipIni = Join-Path $env:APPDATA 'pip\pip.ini'
    Write-FileSafe -Path $pipIni -Content @"
[global]
index-url = $env:DEVKIT_PIP_MIRROR
trusted-host = $env:DEVKIT_PIP_HOST
timeout = 120
"@
}

# ---------------- npm / yarn / pnpm ----------------
if ($doNpm) {
    Write-Step "配置 npm 国内源（$env:DEVKIT_NPM_MIRROR）"
    if (Test-Cmd npm) {
        Invoke-Soft -Desc "npm config set registry $env:DEVKIT_NPM_MIRROR" -Cmd @("npm","config","set","registry",$env:DEVKIT_NPM_MIRROR) -TimeoutSec 30 | Out-Null
        Set-NpmrcBinaryMirrors
        Write-Ok "npm registry = $env:DEVKIT_NPM_MIRROR"
        if (Test-Cmd yarn) { Invoke-Soft -Desc "yarn config set registry" -Cmd @("yarn","config","set","registry",$env:DEVKIT_NPM_MIRROR) -TimeoutSec 20 | Out-Null }
        if (Test-Cmd pnpm) { Invoke-Soft -Desc "pnpm config set registry" -Cmd @("pnpm","config","set","registry",$env:DEVKIT_NPM_MIRROR) -TimeoutSec 20 | Out-Null }
    } else {
        Write-Warn '未安装 npm，跳过（装完 Node 后重跑：.\install.ps1 mirrors）'
    }
}

# ---------------- cargo ----------------
if ($doCargo) {
    Write-Step "配置 Rust 国内源（$env:DEVKIT_CARGO_MIRROR）"
    $cargoCfg = Join-Path $env:USERPROFILE '.cargo\config.toml'
    Write-FileSafe -Path $cargoCfg -Content @"
# 由 devkit 生成（crates.io 国内镜像：rsproxy）
[source.crates-io]
replace-with = 'rsproxy-sparse'

[source.rsproxy]
registry = "$env:DEVKIT_CARGO_MIRROR/crates.io-index"

[source.rsproxy-sparse]
registry = "sparse+$env:DEVKIT_CARGO_MIRROR/index/"

[registries.rsproxy]
index = "$env:DEVKIT_CARGO_MIRROR/crates.io-index"

[net]
git-fetch-with-cli = true
"@
}

# ---------------- go ----------------
if ($doGo) {
    Write-Step "配置 Go 国内源（$env:DEVKIT_GO_MIRROR）"
    if (Test-Cmd go) {
        Invoke-Dry 'go env -w GOPROXY' { & go env -w GOPROXY="$env:DEVKIT_GO_MIRROR" }
        Invoke-Dry 'go env -w GOSUMDB' { & go env -w GOSUMDB='sum.golang.google.cn' }
        Write-Ok "GOPROXY = $env:DEVKIT_GO_MIRROR"
    } else {
        Write-Warn '未安装 Go，跳过'
    }
}

# ---------------- maven ----------------
if ($doMaven) {
    Write-Step "配置 Maven 国内源（$env:DEVKIT_MAVEN_MIRROR）"
    $m2 = Join-Path $env:USERPROFILE '.m2\settings.xml'
    if (Test-Path $m2) {
        $content = Get-Content $m2 -Raw
        if ($content -match 'aliyun') {
            Write-Ok "$m2 已配置阿里云镜像，跳过"
        } else {
            Write-Warn "$m2 已存在且未含阿里云镜像，为避免破坏已有仓库/私服配置，这里不覆盖。"
            Write-Hint "手动在 <mirrors> 中加入：<mirror><id>aliyun</id><mirrorOf>central</mirrorOf><url>$env:DEVKIT_MAVEN_MIRROR</url></mirror>"
        }
    } else {
        Write-FileSafe -Path $m2 -Content @"
<?xml version="1.0" encoding="UTF-8"?>
<!-- 由 devkit 生成 -->
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 https://maven.apache.org/xsd/settings-1.0.0.xsd">
  <mirrors>
    <mirror>
      <id>aliyun-central</id>
      <name>aliyun public</name>
      <mirrorOf>central</mirrorOf>
      <url>$env:DEVKIT_MAVEN_MIRROR</url>
    </mirror>
  </mirrors>
</settings>
"@
    }
}

if ($Section -eq 'all') {
    Write-Host ''
    Write-Ok '镜像源配置完成。'
    Write-Hint "已写入：$(Join-Path $env:APPDATA 'pip\pip.ini')"
    Write-Hint "        $(Join-Path $env:USERPROFILE '.npmrc')（npm config 自动维护）"
    Write-Hint "        $(Join-Path $env:USERPROFILE '.cargo\config.toml')"
}
