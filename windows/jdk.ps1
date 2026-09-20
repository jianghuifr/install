# ============================================================
#  windows/jdk.ps1 —— 安装 JDK（默认 Temurin 17）与 Maven
#
#  顺序：winget（EclipseAdoptium.Temurin.<ver>.JDK）→ choco（temurin<ver>）
#        → 兜底：从清华 Adoptium 镜像下 MSI 静默安装
#  Maven：winget（Apache.Maven）→ choco（maven）→ 清华 apache 镜像下 zip
# ============================================================
. (Join-Path $PSScriptRoot 'common.ps1')

Write-Header '安装 JDK 与 Maven'

$JdkVer = if ($env:DEVKIT_JDK_VERSION) { $env:DEVKIT_JDK_VERSION } else { '17' }
$arch = if ($env:PROCESSOR_ARCHITECTURE -match 'ARM64') { 'aarch64' } else { 'x64' }

function Find-JavaHome {
    $patterns = @(
        "C:\Program Files\Eclipse Adoptium\jdk-$JdkVer*",
        "C:\Program Files\Microsoft\jdk-$JdkVer*",
        "C:\Program Files\Java\jdk-$JdkVer*",
        "C:\Program Files\Amazon Corretto\jdk$JdkVer*"
    )
    foreach ($p in $patterns) {
        $hit = Get-Item $p -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

# ---------- JDK ----------
if ((Test-Cmd java) -and $env:DEVKIT_FORCE -ne '1') {
    Write-Ok "已安装 $(& java -version 2>&1 | Select-Object -First 1)"
} else {
    $ok = $false
    if (Test-Winget) { $ok = Install-WingetPackage -Id "EclipseAdoptium.Temurin.$JdkVer.JDK" -Name "Temurin JDK $JdkVer" }
    if (-not $ok) { $ok = Install-ChocoPackage -Name "temurin$JdkVer" -Display "Temurin JDK $JdkVer" }

    if (-not $ok) {
        Write-Step '兜底方案：从清华 Adoptium 镜像下载 JDK MSI'
        $base = "https://mirrors.tuna.tsinghua.edu.cn/Adoptium/$JdkVer/jdk/$arch/windows"
        $html = Get-WebText "$base/"
        $file = $null
        if ($html) {
            $m = [regex]::Matches($html, "OpenJDK${JdkVer}U-jdk_${arch}_windows_hotspot_[\d._]+\.msi")
            if ($m.Count -gt 0) { $file = $m[0].Value }
        }
        if (-not $file) {
            Write-Err "无法从 $base 解析安装包名"
            Write-Hint '可手动下载：https://adoptium.net/zh-CN/temurin/releases/'
            exit 1
        }
        $out = Join-Path (Get-TempDir) $file
        if (-not (Get-File "$base/$file" $out)) { exit 1 }
        Invoke-Dry "msiexec /i $file /qn" {
            $p = Start-Process msiexec.exe -ArgumentList '/i', "`"$out`"", '/qn', '/norestart' -Wait -PassThru
            if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) { Write-Ok "JDK $JdkVer 安装完成" }
            else { Write-Err "JDK 安装失败（退出码 $($p.ExitCode)）" }
        }
    }
    Update-SessionPath
}

# ---------- JAVA_HOME ----------
Write-Step '配置 JAVA_HOME 与 PATH'
$jh = Find-JavaHome
if ($jh) {
    Set-EnvPersist -Name 'JAVA_HOME' -Value $jh
    Add-UserPath (Join-Path $jh 'bin')
    Write-Ok "JAVA_HOME = $jh"
} else {
    Write-Warn '没找到 JDK 安装目录，JAVA_HOME 未设置（可手动设置到 JDK 根目录）'
}

# ---------- Maven ----------
if ((Test-Cmd mvn) -and $env:DEVKIT_FORCE -ne '1') {
    Write-Ok "已安装 $(& mvn -v 2>&1 | Select-Object -First 1)"
} else {
    $ok = $false
    if (Test-Winget) { $ok = Install-WingetPackage -Id 'Apache.Maven' -Name 'Apache Maven' }
    if (-not $ok) { $ok = Install-ChocoPackage -Name 'maven' -Display 'Apache Maven' }

    if (-not $ok) {
        Write-Step '兜底方案：从清华 apache 镜像下载 Maven zip'
        $index = Get-WebText 'https://mirrors.tuna.tsinghua.edu.cn/apache/maven/maven-3/'
        $ver = $null
        if ($index) {
            $vers = [regex]::Matches($index, '>(3\.\d+\.\d+)/<') |
                ForEach-Object { $_.Groups[1].Value } |
                Sort-Object { [version]$_ } -Descending
            if ($vers.Count -gt 0) { $ver = $vers[0] }
        }
        if (-not $ver) {
            Write-Err '无法解析 Maven 版本'
            Write-Hint '可手动下载：https://maven.apache.org/download.cgi'
            exit 1
        }
        $file = "apache-maven-$ver-bin.zip"
        $url = "https://mirrors.tuna.tsinghua.edu.cn/apache/maven/maven-3/$ver/binaries/$file"
        $zip = Join-Path (Get-TempDir) $file
        if (-not (Get-File $url $zip)) { exit 1 }
        $dest = 'C:\dev'
        if (-not $script:DevkitDryRun) {
            if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
            Expand-Archive -Path $zip -DestinationPath $dest -Force
        }
        $mvnHome = Join-Path $dest "apache-maven-$ver"
        Set-EnvPersist -Name 'MAVEN_HOME' -Value $mvnHome
        Add-UserPath (Join-Path $mvnHome 'bin')
        Write-Ok "Maven $ver 解压到 $mvnHome"
    }
    Update-SessionPath
}

# ---------- 阿里云中央仓库 ----------
& (Join-Path $PSScriptRoot 'mirrors.ps1') -Section maven

Write-Host ''
Update-SessionPath
foreach ($c in @('java', 'mvn')) {
    if (Test-Cmd $c) { Write-Ok "$c -> $(& $c -version 2>&1 | Select-Object -First 1)" }
    else { Write-Warn "$c 未进 PATH，请重开终端验证" }
}
Write-Ok 'JDK 处理完毕。'
Write-Hint "想装 21：`$env:DEVKIT_JDK_VERSION='21'; .\install.ps1 jdk"
