<#
.SYNOPSIS
    Build preflight: sets up build env and chains patch + release build.

.DESCRIPTION
    Single entry point that consolidates the build environment:
      1. locate Flutter SDK and an Android SDK containing the required NDK
      2. set FLUTTER_ROOT / GITHUB_WORKSPACE / ANDROID_HOME / ANDROID_SDK_ROOT
      3. prepend flutter bin to PATH (append on top of existing PATH, never replace)
      4. run lib/scripts/patch.ps1 android, then scripts/build_android_local.ps1

.PARAMETER SkipPatch
    Skip the Flutter / dependency patch step.
.PARAMETER SkipBuild
    Skip the release APK build step.
.PARAMETER Dev
    Build the dev package name (forwarded to build_android_local.ps1).
#>

param(
    [switch]$SkipPatch,
    [switch]$SkipBuild,
    [switch]$Dev
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $PSCommandPath
$ProjectRoot = Resolve-Path (Join-Path $ScriptDir "..")

# --- 1. Locate Flutter SDK ------------------------------------------------
$FlutterRoot = $null
if ($env:FLUTTER_ROOT -and (Test-Path $env:FLUTTER_ROOT)) { $FlutterRoot = $env:FLUTTER_ROOT }
if (-not $FlutterRoot -and (Test-Path "C:\tools\flutter-3.47.1")) { $FlutterRoot = "C:\tools\flutter-3.47.1" }
if (-not $FlutterRoot -and (Test-Path "C:\tools\flutter")) { $FlutterRoot = "C:\tools\flutter" }
if (-not $FlutterRoot) {
    throw "Flutter SDK not found. Set FLUTTER_ROOT or install to C:\tools\flutter-3.47.1"
}

# --- 2. Locate Android SDK (must contain the required NDK) ----------------
$requiredNdkVersion = "28.2.13676358"
function Test-AndroidSdk([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path -PathType Container)) {
        return $false
    }
    $ndkProps = Join-Path (Join-Path (Join-Path $Path "ndk") $requiredNdkVersion) "source.properties"
    return (Test-Path $ndkProps -PathType Leaf)
}

$AndroidHome = $null
$candidates = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "C:\Android") |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Select-Object -Unique
foreach ($c in $candidates) {
    if (Test-AndroidSdk $c) { $AndroidHome = (Resolve-Path $c).Path; break }
}
if (-not $AndroidHome) {
    throw "No complete Android SDK with NDK $requiredNdkVersion found. Install it, or use C:\Android."
}

# --- 3. Apply env vars; PREPEND to PATH (do not replace) ------------------
$env:FLUTTER_ROOT = $FlutterRoot
$env:GITHUB_WORKSPACE = $ProjectRoot
$env:ANDROID_HOME = $AndroidHome
$env:ANDROID_SDK_ROOT = $AndroidHome
$env:Path = "$FlutterRoot\bin;" + $env:Path

Write-Host "FLUTTER_ROOT:    $FlutterRoot"
Write-Host "GITHUB_WORKSPACE: $ProjectRoot"
Write-Host "ANDROID_HOME:    $AndroidHome"

# --- 4. Patch ---------------------------------------------------------------
if (-not $SkipPatch) {
    Write-Host "`n>> Applying Flutter/dependency patches (patch.ps1 android)..."
    & (Join-Path $ProjectRoot "lib\scripts\patch.ps1") "android"
}

# --- 5. Build ---------------------------------------------------------------
if (-not $SkipBuild) {
    Write-Host "`n>> Building release APK (build_android_local.ps1)..."
    $buildArgs = @()
    if ($Dev) { $buildArgs += "-Dev" }
    & (Join-Path $ProjectRoot "scripts\build_android_local.ps1") @buildArgs
}
