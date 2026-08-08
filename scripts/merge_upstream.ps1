<#
.SYNOPSIS
    同步并合并上游 PiliPlus，随后自动验证（依赖、静态分析、debug 构建）

.DESCRIPTION
    一键完成：
      1. 前置检查（分支、工作区、Flutter SDK）
      2. git fetch upstream --prune
      3. git merge-tree 冲突预检（无副作用）
      4. git merge upstream/main
      5. 已知 API 不兼容哨兵检查（TextPainter.layoutCache）
      6. flutter pub get（失败自动重试一次）
      7. flutter analyze（发现 error 即中止，快速失败检测）
      8. flutter build apk --debug（arm64，可跳过）
      9. 输出合并摘要与验证结果

    背景：上游 CI 通过 lib/scripts/patch.ps1 给 Flutter SDK 打补丁（如
    text_painter.patch 暴露 TextPainter.layoutCache），而本机本地构建
    不执行补丁步骤，故上游代码中依赖补丁 API 的写法在合并后才会暴露。
    本脚本在合并后先做静态哨兵检查与 analyze，避免直接进入必败的长构建。

.PARAMETER VerifyOnly
    跳过拉取/预检/合并，只执行第 5-9 步。用于手动解决冲突后重跑验证。

.PARAMETER SkipBuild
    跳过第 8 步 debug 构建，只做静态检测。
#>

param(
    [switch]$VerifyOnly,
    [switch]$SkipBuild
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

# ─── 1. 前置检查 ───────────────────────────────────────────────
Write-Step "1/8  前置检查..."
$branch = & git rev-parse --abbrev-ref HEAD 2>$null
if ($LASTEXITCODE -ne 0 -or $branch -ne "main") {
    Write-Err "当前分支为 '$branch'，请在 main 分支执行。"
}
Write-Ok "分支: $branch"

$dirty = @(& git status --porcelain 2>$null | Where-Object { $_ -notmatch '^\?\?' })
if ($dirty.Count -gt 0) {
    $dirty | ForEach-Object { Write-Host "    $_" }
    Write-Err "工作区有未提交的修改，请先提交或暂存。"
}
Write-Ok "工作区干净（未跟踪文件除外）"

# 定位 Flutter SDK（同 build_android_local.ps1 的候选逻辑）
$FlutterRoot = $null
$fvmLink = jp $ProjectRoot ".fvm" "flutter_sdk"
if (Test-Path $fvmLink) {
    $target = (Get-Item $fvmLink).Target
    if ($target -and (Test-Path $target)) { $FlutterRoot = (Resolve-Path $target).Path }
}
if (-not $FlutterRoot -and $env:FLUTTER_ROOT -and (Test-Path $env:FLUTTER_ROOT)) { $FlutterRoot = $env:FLUTTER_ROOT }
if (-not $FlutterRoot) {
    $fvmPath = jp $env:USERPROFILE ".fvm" "versions" "3.44.8"
    if (Test-Path $fvmPath) { $FlutterRoot = $fvmPath }
}
if (-not $FlutterRoot -and (Test-Path "C:\tools\flutter")) { $FlutterRoot = "C:\tools\flutter" }
if (-not $FlutterRoot) {
    try { $exe = (Get-Command flutter.bat -ErrorAction Stop).Source; $FlutterRoot = (Get-Item $exe).Directory.Parent.FullName } catch {}
}
if (-not $FlutterRoot) { Write-Err "找不到 Flutter SDK。先安装: fvm install 3.44.8 && fvm use" }
Write-Ok "Flutter: $FlutterRoot"

# ─── 2. 拉取上游（VerifyOnly 跳过）─────────────────────────────
if (-not $VerifyOnly) {
    Write-Step "2/8  拉取上游..."
    $fetch = Invoke-Native "git" @("fetch", "upstream", "--prune")
    if ($fetch.ExitCode -ne 0) {
        $fetch.Output | ForEach-Object { Write-Host $_ }
        Write-Err "git fetch upstream 失败，检查网络。"
    }
    $pending = @(& git log --oneline HEAD..upstream/main 2>$null)
    if ($pending.Count -eq 0) { Write-Ok "上游已是最新，无新提交。"; exit 0 }
    Write-Ok "待合并的上游提交（$($pending.Count) 个）："
    $pending | ForEach-Object { Write-Host "    $_" }

    # ─── 3. 冲突预检 ─────────────────────────────────────────
    Write-Step "3/8  冲突预检（merge-tree，无副作用）..."
    $precheck = Invoke-Native "git" @("merge-tree", "--write-tree", "HEAD", "upstream/main")
    if ($precheck.ExitCode -ne 0) {
        $precheck.Output | ForEach-Object { Write-Host $_ }
        Write-Err "预检发现合并冲突。手动解决后重跑: .\scripts\merge_upstream.ps1 -VerifyOnly"
    }
    Write-Ok "预检通过，无冲突"

    # ─── 4. 合并 ─────────────────────────────────────────────
    Write-Step "4/8  合并 upstream/main..."
    $merge = Invoke-Native "git" @("merge", "upstream/main", "--no-edit")
    if ($merge.ExitCode -ne 0) {
        $merge.Output | ForEach-Object { Write-Host $_ }
        Write-Err "git merge 失败。手动解决冲突后重跑: .\scripts\merge_upstream.ps1 -VerifyOnly"
    }
    Write-Ok "合并完成"
} else {
    Write-Step "2/8  （VerifyOnly：跳过拉取/预检/合并）"
}

# ─── 5. 已知 API 哨兵检查 ──────────────────────────────────────
# 精确匹配 TextPainter.layoutCache 的用法（上游 text_painter.patch 依赖），
# 避免误报 lib/utils/grid.dart 中 SliverGridLayout.layoutCache 自定义字段
# 以及 lib/scripts/*.patch 补丁文件自身。
Write-Step "5/8  检查已知 API 不兼容..."
$layoutHits = @(& git grep -nE "textPainter\.layoutCache|layoutCache\?\.lineMetrics" -- "*.dart" 2>$null)
if ($layoutHits.Count -gt 0) {
    $layoutHits | ForEach-Object { Write-Host "    $_" }
    Write-Err "检测到 TextPainter.layoutCache 用法（本机 Flutter 3.44.8 未应用上游 text_painter.patch）。改为 computeLineMetrics() 后重跑: .\scripts\merge_upstream.ps1 -VerifyOnly"
}
Write-Ok "未发现 TextPainter.layoutCache"

# ─── 6. 依赖 ───────────────────────────────────────────────────
Write-Step "6/8  安装依赖..."
$flutterExe = jp $FlutterRoot "bin" "flutter.bat"
$pub = Invoke-Native $flutterExe @("pub", "get")
if ($pub.ExitCode -ne 0) {
    Write-Warn "flutter pub get 失败，重试一次..."
    $pub = Invoke-Native $flutterExe @("pub", "get")
}
if ($pub.ExitCode -ne 0) {
    $pub.Output | ForEach-Object { Write-Host $_ }
    Write-Err "依赖安装失败。"
}
Write-Ok "依赖安装完成"

# ─── 7. 静态分析（快速失败检测）────────────────────────────────
# 注意：flutter analyze 在存在 info/warning 时退出码也为非 0，
# 因此只以输出中是否有 "error -" 行作为失败判定，避免误报。
Write-Step "7/8  静态分析（快速失败检测）..."
$analyze = Invoke-Native $flutterExe @("analyze")
$analyze.Output | ForEach-Object { Write-Host $_ }
$errorLines = @($analyze.Output | Where-Object { $_ -match '^\s*error -' })
if ($errorLines.Count -gt 0) {
    Write-Err "flutter analyze 发现 $($errorLines.Count) 个 error，修复后重跑: .\scripts\merge_upstream.ps1 -VerifyOnly"
}
Write-Ok "静态分析通过，无 error"

# ─── 8. 构建验证（SkipBuild 跳过）──────────────────────────────
if (-not $SkipBuild) {
    Write-Step "8/8  debug 构建验证..."
    $build = Invoke-Native $flutterExe @("build", "apk", "--debug", "--target-platform", "android-arm64")
    $build.Output | ForEach-Object { Write-Host $_ }
    if ($build.ExitCode -ne 0) { Write-Err "debug 构建失败，详见上方日志。" }
    Write-Ok "debug 构建成功"
} else {
    Write-Ok "（SkipBuild：跳过 debug 构建）"
}

# ─── 9. 摘要 ───────────────────────────────────────────────────
$Elapsed = (Get-Date) - $ScriptStart
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════╗"
Write-Host "║          合并验证完成！                       ║"
Write-Host "╠═══════════════════════════════════════════════╣"
Write-Host "║ HEAD:       $((& git rev-parse --short HEAD).Trim())"
Write-Host "║ 用时:       $([math]::Round($Elapsed.TotalSeconds,0)) 秒"
Write-Host "╚═══════════════════════════════════════════════╝"
Write-Host ""
Write-Host "最近提交："
& git log --oneline -3 | ForEach-Object { Write-Host "    $_" }
Write-Host ""
if ($VerifyOnly) {
    Write-Host "验证完成。如有兼容性修复或冲突解决改动，请 review 后单独提交。"
} else {
    Write-Host "合并已完成。如有兼容性修复，请 review 后单独提交（建议在提交消息中注明修复原因）。"
}
Write-Host ""
