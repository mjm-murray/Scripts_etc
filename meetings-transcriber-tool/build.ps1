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

# Ensure PyInstaller + runtime deps are present in the building Python.
$reqs = @('pyinstaller','faster-whisper','imageio-ffmpeg','python-docx')
foreach ($pkg in $reqs) {
    $line = (python -m pip show $pkg 2>$null | Select-String -Pattern '^Version:').Line
    if (-not $line) {
        Write-Host "Installing missing build dep: $pkg"
        python -m pip install --user -U $pkg
    }
}

Write-Host "Building TranscribeVideo.exe ..."

# --collect-data faster_whisper        - the package ships data files for tokenizers etc.
# --collect-binaries ctranslate2       - native .pyd / .dll files
# --collect-binaries onnxruntime       - VAD path (optional but bundled to be safe)
# --collect-all av                     - PyAV (used by faster-whisper to decode media without subprocess ffmpeg)
# --collect-binaries imageio_ffmpeg    - bundled portable ffmpeg.exe
# --collect-data imageio_ffmpeg        - data file that maps to the bundled ffmpeg binary
python -m PyInstaller `
    --noconfirm `
    --windowed `
    --onefile `
    --name "TranscribeVideo" `
    --collect-data faster_whisper `
    --collect-binaries ctranslate2 `
    --collect-binaries onnxruntime `
    --collect-all av `
    --collect-binaries imageio_ffmpeg `
    --collect-data imageio_ffmpeg `
    transcribe_gui.py

$exe = Join-Path $PSScriptRoot 'dist\TranscribeVideo.exe'
if (Test-Path $exe) {
    $size = '{0:N1} MB' -f ((Get-Item $exe).Length / 1MB)
    Write-Host ""
    Write-Host "Build OK: $exe  ($size)"
} else {
    Write-Error "Build failed - no exe at $exe"
}
