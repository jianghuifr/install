# ============================================================
#  windows/rust.ps1 —— 安装 Rust 工具链（rustup + cargo）
#
#  1. rustup-init.exe 从 rsproxy 镜像下载
#  2. RUSTUP_DIST_SERVER / RUSTUP_UPDATE_ROOT 永久指向 rsproxy
#  3. crates.io 依赖换成 rsproxy 稀疏索引
#  注意：MSVC 工具链编译链接时需要 Visual Studio C++ 生成工具（体积大，脚本只提示不自动装）
#        想省事可用 GNU 工具链：DEVKIT_RUST_TARGET=gnu .\install.ps1 rust
# ============================================================
. (Join-Path $PSScriptRoot 'common.ps1')

Write-Header '安装 Rust 工具链'

$target = if ($env:DEVKIT_RUST_TARGET -eq 'gnu') { 'gnu' } else { 'msvc' }

function Get-Triple {
    param([string]$Kind)
    $arch = if ($env:PROCESSOR_ARCHITECTURE -match 'ARM64') { 'aarch64' } else { 'x86_64' }
    return "$arch-pc-windows-$Kind"
}

$triple = Get-Triple $target

if ((Test-Cmd rustc) -and (Test-Cmd cargo) -and $env:DEVKIT_FORCE -ne '1') {
    Write-Ok "已安装 $(& rustc -V)，跳过"
} else {
    Write-Step "设置 rustup 国内源（$env:DEVKIT_RUSTUP_MIRROR）"
    Set-EnvPersist -Name 'RUSTUP_DIST_SERVER' -Value $env:DEVKIT_RUSTUP_MIRROR
    Set-EnvPersist -Name 'RUSTUP_UPDATE_ROOT' -Value "$env:DEVKIT_RUSTUP_MIRROR/rustup"

    $url = "$env:DEVKIT_RUSTUP_MIRROR/rustup/dist/$triple/rustup-init.exe"
    $out = Join-Path (Get-TempDir) 'rustup-init.exe'
    Write-Step "下载 rustup-init（${triple}）"
    if (-not (Get-File $url $out)) {
        Write-Host ''
        Write-Err 'rustup-init 下载失败'
        Write-Hint "可手动下载：$url"
        Write-Hint '或使用 GNU 工具链：$env:DEVKIT_RUST_TARGET="gnu"; .\install.ps1 rust'
        exit 1
    }

    Write-Step '安装 stable 工具链（default profile）'
    Invoke-Dry "rustup-init.exe -y --profile default --default-toolchain stable --no-modify-path" {
        & $out -y --profile default --default-toolchain stable --no-modify-path
        if ($LASTEXITCODE -ne 0) { Write-Warn "rustup-init 退出码 $LASTEXITCODE" }
    }
    Add-UserPath (Join-Path $env:USERPROFILE '.cargo\bin')
    Update-SessionPath
}

Write-Step "配置 crates.io 国内源（$env:DEVKIT_CARGO_MIRROR）"
& (Join-Path $PSScriptRoot 'mirrors.ps1') -Section cargo
$cargoCfg = Join-Path $env:USERPROFILE '.cargo\config.toml'
if (Test-Path $cargoCfg) { Write-Ok "已写入 $cargoCfg" }

Write-Step '预装常用组件'
Invoke-Dry 'rustup component add rustfmt clippy' {
    & rustup component add rustfmt clippy 2>&1 | Out-Null
    & rustup default stable 2>&1 | Out-Null
    Write-Ok '已安装 rustfmt / clippy'
}

if ($target -eq 'msvc') {
    Write-Host ''
    Write-Warn 'MSVC 工具链需要「Visual Studio C++ 生成工具」才能编译链接（rustc 本身可运行）。'
    Write-Hint '需要的话执行（约 2~3 GB）：'
    Write-Hint 'winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"'
    Write-Hint '或改用 GNU 工具链：$env:DEVKIT_RUST_TARGET="gnu"; .\install.ps1 rust'
}

Write-Host ''
Update-SessionPath
foreach ($c in @('rustc', 'cargo', 'rustup')) {
    if (Test-Cmd $c) { Write-Ok "$c -> $(& $c --version 2>&1 | Select-Object -First 1)" }
    else { Write-Warn "$c 未在 PATH 中，请重开终端后验证" }
}
Write-Ok 'Rust 处理完毕。'
