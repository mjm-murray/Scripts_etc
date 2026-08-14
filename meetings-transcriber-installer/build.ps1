[CmdletBinding()]
param(
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

if ($Clean) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue build, dist, '*.spec'
    Write-Host "Cleaned build artifacts."
}

# Make sure tooling is present.
$pyi = (python -m pip show pyinstaller 2>$null | Select-String -Pattern '^Version:').Count
if ($pyi -eq 0) {
    Write-Host "PyInstaller not found - installing..."
    python -m pip install --user -U pyinstaller
}

Write-Host "Building setup_gui.exe ..."

# --windowed   = no console window (we're a GUI)
# --onefile    = single .exe
# --name       = exe name
# --add-data   = bundle the resources folder (semicolon separator on Windows)
python -m PyInstaller `
    --noconfirm `
    --windowed `
    --onefile `
    --name "MeetingsTranscriberSetup" `
    --add-data "resources;resources" `
    setup_gui.py

$exe = Join-Path $PSScriptRoot 'dist\MeetingsTranscriberSetup.exe'
if (Test-Path $exe) {
    $size = '{0:N1} MB' -f ((Get-Item $exe).Length / 1MB)
    Write-Host ""
    Write-Host "Build OK: $exe  ($size)"
} else {
    Write-Error "Build failed - no exe at $exe"
}
