# Check low latency mode settings on Windows 10 25H2
Write-Host "=== Windows Version ==="
Get-ItemProperty 'HKLM:SOFTWARE\Microsoft\Windows NT\CurrentVersion' | Select-Object ProductName, DisplayVersion, CurrentBuild, UBR
Write-Host ""

# Check Game Mode settings
Write-Host "=== GameConfigStore (Game Mode Settings) ==="
Get-ItemProperty 'HKCU:\System\GameConfigStore' -ErrorAction SilentlyContinue | Format-List
Write-Host ""

# Check DirectX Graphics Settings
Write-Host "=== DirectX Graphics Settings ==="
if (Test-Path 'HKCU:\Software\Microsoft\DirectX') {
    Get-ChildItem 'HKCU:\Software\Microsoft\DirectX' -ErrorAction SilentlyContinue -Recurse | ForEach-Object {
        Write-Host ("Path: " + $_.PSPath)
        Get-ItemProperty $_.PSPath | Format-List
        Write-Host "---"
    }
} else {
    Write-Host "DirectX key not found"
}
Write-Host ""

# Check GameBar Settings
Write-Host "=== GameBar Settings ==="
Get-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -ErrorAction SilentlyContinue | Format-List
Write-Host ""

# Check specific paths for low latency settings
Write-Host "=== Checking specific paths ==="
foreach ($k in @(
    'HKCU:\Software\Microsoft\DirectX\GraphicsSettings',
    'HKCU:\Software\Microsoft\Direct3D\GraphicsSettings',
    'HKCU:\Software\Microsoft\Windows\Dwm'
)) {
    if (Test-Path $k) {
        Write-Host ("Found: " + $k)
        Get-ItemProperty $k | Format-List
    }
}
Write-Host ""

# Search for any key containing "LowLatency"
Write-Host "=== Searching for LowLatency ==="
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match 'LowLatency' } | ForEach-Object {
    Write-Host ("Found: " + $_.PSPath)
}

# Also search for "Opt" (optimization) related
Write-Host "=== Search for optimization settings ==="
Get-ChildItem 'HKCU:\Software\Microsoft' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match 'Optimiz|LowLatenc|DisableLow' } | ForEach-Object {
    Write-Host ("Found: " + $_.PSPath)
    Get-ItemProperty $_.PSPath | Format-List
}
