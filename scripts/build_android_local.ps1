<#
.SYNOPSIS
    一键构建 PiliPlus Android APK（仅 arm64-v8a）

.DESCRIPTION
    双击运行即可。完成以下操作：
      1. 检测 Flutter SDK、Java 21、Android SDK
      2. 计算版本号，生成构建配置文件
      3. 运行 flutter pub get
      4. 执行本机环境修复（TLS / 长路径 / 插件文件恢复）
      5. 构建 release APK（仅 arm64-v8a）
      6. 输出 APK 信息：路径、大小、SHA256、版本号、applicationId

.PARAMETER WithPatch
    应用 Flutter SDK 补丁（patch.ps1）。默认不启用。
.PARAMETER Dev
    构建 dev 版本（applicationId 带 .dev 后缀）。
#>

param(
    [switch]$WithPatch,
    [switch]$Dev
)

$ErrorActionPreference = "Stop"
$ScriptStart = Get-Date
$ScriptDir = Split-Path -Parent $PSCommandPath
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")
Set-Location $ProjectRoot

# ─── 颜色辅助 ──────────────────────────────────────────────────
function Write-Step  { Write-Host "`n>> $args" -Foreground Cyan }
function Write-Ok    { Write-Host "   OK  $args" -Foreground Green }
function Write-Warn  { Write-Host "   !   $args" -Foreground Yellow }
function Write-Err   { Write-Host "   ERROR $args" -Foreground Red; exit 1 }

# ─── 路径辅助（PowerShell 5.x Join-Path 只支持 2 段）───────────
function jp([string]$Root) { $r = $Root; foreach ($s in $args) { $r = Join-Path $r $s }; $r }

# Windows PowerShell 5.1 会把原生命令写入 stderr 的普通信息包装成
# NativeCommandError，并受全局 Stop 策略影响。局部改用 Continue，
# 再以进程退出码判断成败。
function Invoke-Native([string]$FilePath, [string[]]$ArgumentList) {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& $FilePath @ArgumentList 2>&1) | ForEach-Object { $_.ToString() }
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    [PSCustomObject]@{
        Output = $output
        ExitCode = $exitCode
    }
}

# ─── 1. 检测 Flutter SDK ───────────────────────────────────────
Write-Step "1/5  检测 Flutter SDK..."
$FlutterRoot = $null
# 1) .fvm/flutter_sdk
$fvmLink = jp $ProjectRoot ".fvm" "flutter_sdk"
if (Test-Path $fvmLink) {
    $target = (Get-Item $fvmLink).Target
    if ($target -and (Test-Path $target)) { $FlutterRoot = (Resolve-Path $target).Path }
}
# 2) FLUTTER_ROOT 环境变量
if (-not $FlutterRoot -and $env:FLUTTER_ROOT -and (Test-Path $env:FLUTTER_ROOT)) { $FlutterRoot = $env:FLUTTER_ROOT }
# 3) FVM 缓存
if (-not $FlutterRoot) {
    $fvmPath = jp $env:USERPROFILE ".fvm" "versions" "3.44.2"
    if (Test-Path $fvmPath) { $FlutterRoot = $fvmPath }
}
# 4) C:\tools\flutter（本机安装路径）
if (-not $FlutterRoot -and (Test-Path "C:\tools\flutter")) { $FlutterRoot = "C:\tools\flutter" }
# 5) 系统 PATH 上的 flutter
if (-not $FlutterRoot) {
    try { $exe = (Get-Command flutter.bat -ErrorAction Stop).Source; $FlutterRoot = (Get-Item $exe).Directory.Parent.FullName } catch {}
}
if (-not $FlutterRoot) { Write-Err "找不到 Flutter SDK。先安装: fvm install 3.44.2 && fvm use" }
Write-Ok "Flutter: $FlutterRoot"

# ─── 2. 检测 Java 21 ──────────────────────────────────────────
Write-Step "2/5  检测 Java 21..."
$javaHome = $env:JAVA_HOME
if (-not $javaHome) { Write-Err "JAVA_HOME 未设置。请安装 JDK 21 并设置环境变量。" }
$javaExe = jp $javaHome "bin" "java.exe"
if (-not (Test-Path $javaExe)) { $javaExe = jp $javaHome "bin" "java" }
if (-not (Test-Path $javaExe)) { Write-Err "在 JAVA_HOME 下找不到 java: $javaHome" }
$javaResult = Invoke-Native $javaExe @("-version")
$verOut = $javaResult.Output | Out-String
if ($javaResult.ExitCode -ne 0) { Write-Err "Java 无法正常运行（退出码 $($javaResult.ExitCode)）。" }
if ($verOut -match '"(\d+)') { $majorVer = [int]$matches[1] } else { $majorVer = 0 }
if ($majorVer -lt 21) { Write-Err "需要 Java 21+, 当前是 $majorVer。请安装 JDK 21。" }
Write-Ok "Java $majorVer at $javaHome"

# ─── 3. 检测 Android SDK ───────────────────────────────────────
Write-Step "3/5  检测 Android SDK..."
$androidHome = $env:ANDROID_HOME
if (-not $androidHome) { $androidHome = $env:ANDROID_SDK_ROOT }
if (-not $androidHome) {
    $candidates = @("C:\Android", (jp $env:LOCALAPPDATA "Android" "Sdk"), (jp $env:USERPROFILE "Android" "Sdk"))
    foreach ($c in $candidates) { if (Test-Path $c) { $androidHome = $c; break } }
}
if (-not $androidHome) { Write-Err "找不到 Android SDK。设置 ANDROID_HOME 环境变量。" }
$env:ANDROID_HOME = $androidHome
$env:ANDROID_SDK_ROOT = $androidHome
Write-Ok "Android SDK: $androidHome"

# ─── 4. 生成/更新 local.properties ─────────────────────────────
$localProps = jp $ProjectRoot "android" "local.properties"
@"
sdk.dir=$($androidHome -replace '\\', '/')
flutter.sdk=$($FlutterRoot -replace '\\', '/')
flutter.buildMode=release
"@ | Set-Content -Path $localProps -Encoding UTF8 -Force

# ─── 5. 版本计算 ───────────────────────────────────────────────
Write-Step "4/5  准备构建..."
$pubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
$pubspecContent = Get-Content $pubspecPath -Encoding UTF8

# 提取 versionName / versionCode
$versionLine = $pubspecContent | Where-Object { $_ -match '^\s*version:\s*([\d\.]+)\+(\d+)' } | Select-Object -First 1
if (-not $versionLine) { Write-Err "pubspec.yaml 中找不到 version 行" }
$versionName = $matches[1]  # e.g. 2.0.9
$versionCode = $matches[2]  # e.g. 1

# 生成 pili_release.json
$buildTime = [int]([DateTimeOffset]::Now.ToUnixTimeSeconds())
$commitHash = "local"
try { $commitHash = (git rev-parse HEAD 2>$null).Trim().Substring(0,9) } catch {}
$releaseData = @{ 'pili.name' = $versionName; 'pili.code' = [int]$versionCode; 'pili.hash' = $commitHash; 'pili.time' = $buildTime }
$releaseJsonPath = Join-Path $ProjectRoot "pili_release.json"
$releaseData | ConvertTo-Json -Compress | Set-Content $releaseJsonPath -Encoding UTF8

Write-Ok "Version: $versionName (build $versionCode)"

# ─── 6. Flutter pub get ────────────────────────────────────────
$flutterExe = jp $FlutterRoot "bin" "flutter.bat"
$pubResult = Invoke-Native $flutterExe @("pub", "get")
if ($pubResult.ExitCode -ne 0) {
    $pubResult.Output | ForEach-Object { Write-Host $_ }
    Write-Err "flutter pub get 失败，检查网络连接。"
}
Write-Ok "依赖安装完成"

# ─── 7. 本机环境修复 ──────────────────────────────────────────
# 这些是已验证的本机 workaround，不是项目修改

# 7a. Git 长路径（Windows 特有）
git config --global core.longpaths true 2>$null

# 7b. flutter_inappwebview 文件恢复
$inappwebviewDirs = Get-ChildItem (Join-Path $env:USERPROFILE "AppData\Local\Pub\Cache\git") -Directory -Filter "flutter_inappwebview*" -ErrorAction SilentlyContinue
foreach ($dir in $inappwebviewDirs) {
    Push-Location $dir.FullName
    $deleted = git diff --name-only --diff-filter=D HEAD 2>$null
    if ($deleted) {
        git checkout HEAD -- $deleted 2>$null
        Write-Ok "已恢复 $($dir.Name) 中被删除的源文件"
    }
    Pop-Location
}

# 7c. TLS 修复
$gradleProps = jp $ProjectRoot "android" "gradle.properties"
$gc = Get-Content $gradleProps -Raw -ErrorAction SilentlyContinue
if ($gc -and $gc -notmatch '-Dhttps\.protocols=') {
    $gc = $gc -replace 'org\.gradle\.jvmargs=(.*)', 'org.gradle.jvmargs=$1 -Dhttps.protocols=TLSv1.2'
    Set-Content -Path $gradleProps -Value $gc -Encoding UTF8
    Write-Ok "已应用 TLS 修复（gradle.properties）"
}

# 7d. 预下载 media-kit 原生库 jar（如果不存在）
$localJarsDir = jp $ProjectRoot "build" "local_jars"
$jarUrls = @(
    "https://github.com/bggRGjQaUbCoE/libmpv-android-video-build/releases/download/vnext/default-arm64-v8a.jar"
)
$jarPaths = @(
    "$localJarsDir/default-arm64-v8a.jar"
)
for ($i = 0; $i -lt $jarUrls.Count; $i++) {
    if (-not (Test-Path $jarPaths[$i])) {
        New-Item -ItemType Directory -Path $localJarsDir -Force | Out-Null
        Write-Warn "下载原生库中 ($($jarUrls[$i]))..."
        try {
            curl.exe -L --connect-timeout 30 -o $jarPaths[$i] $jarUrls[$i] 2>$null
            if (Test-Path $jarPaths[$i]) { Write-Ok "下载完成" } else { Write-Warn "下载失败，构建可能出错" }
        } catch { Write-Warn "下载失败，构建可能出错" }
    }
}

# ─── 8. 构建 APK ──────────────────────────────────────────────
Write-Step "5/5  构建 APK（arm64-v8a）..."
$buildArgs = @("build", "apk", "--release", "--target-platform", "android-arm64",
               "--split-per-abi", "--dart-define-from-file=pili_release.json", "--pub")
if ($Dev) { $buildArgs += "--android-project-arg"; $buildArgs += "dev=1" }

$buildResult = Invoke-Native $flutterExe $buildArgs
$buildResult.Output | ForEach-Object { Write-Host $_ }
if ($buildResult.ExitCode -ne 0) { Write-Err "构建失败，详见上方日志" }

# ─── 9. 查找产物 ──────────────────────────────────────────────
$apkDir = jp $ProjectRoot "build" "app" "outputs" "flutter-apk"
$suffix = if ($Dev) { "dev-release" } else { "release" }
$apk = Get-ChildItem (Join-Path $apkDir "app-arm64-v8a-$suffix.apk") -ErrorAction SilentlyContinue

if (-not $apk) {
    $apk = Get-ChildItem (Join-Path $apkDir "*.apk") -ErrorAction SilentlyContinue | Select-Object -First 1
}

if (-not $apk) { Write-Err "找不到构建产物 APK。" }

# ─── 10. 输出摘要 ─────────────────────────────────────────────
$Elapsed = (Get-Date) - $ScriptStart
$sizeMB = $apk.Length / 1MB
$sha256 = (Get-FileHash $apk.FullName -Algorithm SHA256).Hash.ToLower()
$appId = if ($Dev) { "com.example.piliplus.dev" } else { "com.example.piliplus" }

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════╗"
Write-Host "║          构建成功！                           ║"
Write-Host "╠═══════════════════════════════════════════════╣"
Write-Host "║ APK 路径:  $($apk.FullName)"
Write-Host "║ 大小:      $([math]::Round($sizeMB,1)) MB"
Write-Host "║ SHA256:    $sha256"
Write-Host "║ 版本名称:  $versionName"
Write-Host "║ 版本号:    $versionCode"
Write-Host "║ 包名:      $appId"
Write-Host "║ 用时:      $([math]::Round($Elapsed.TotalSeconds,0)) 秒"
Write-Host "╚═══════════════════════════════════════════════╝"
Write-Host ""
Write-Host "安装到手机：adb install `"$($apk.FullName)`""
Write-Host "（或把 APK 文件传到手机上点击安装）"
Write-Host ""

# ─── 11. 清理 ────────────────────────────────────────────────
if (Test-Path $releaseJsonPath) { Remove-Item $releaseJsonPath -Force }
