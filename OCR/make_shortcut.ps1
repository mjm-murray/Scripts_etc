# Creates the "OCR Tool" shortcut on the Desktop and in this folder.
# The shortcut launches the GUI via pythonw.exe (no console, instant start).

$ErrorActionPreference = "Stop"
$work = Split-Path -Parent $MyInvocation.MyCommand.Path
$gui  = Join-Path $work "ocr_gui.pyw"

# Find pythonw.exe: prefer the one next to the active python, else the launcher.
$pw = $null
$srcs = @(
    (& python -c "import sys,os;print(os.path.join(os.path.dirname(sys.executable),'pythonw.exe'))" 2>$null),
    "$env:LOCALAPPDATA\Microsoft\WindowsApps\pythonw.exe"
)
foreach ($s in $srcs) { if ($s -and (Test-Path $s)) { $pw = $s; break } }
if (-not $pw) { throw "Could not find pythonw.exe. Is Python installed?" }

# Use the python.exe icon if we can find it; otherwise fall back to a shell icon.
$icon = ($pw -replace "pythonw\.exe$", "python.exe")
if (-not (Test-Path $icon)) { $icon = "$env:SystemRoot\System32\imageres.dll,165" }

$targets = @(
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'OCR Tool.lnk'),
    (Join-Path $work 'OCR Tool.lnk')
)

$wsh = New-Object -ComObject WScript.Shell
foreach ($t in $targets) {
    $sc = $wsh.CreateShortcut($t)
    $sc.TargetPath       = $pw
    $sc.Arguments        = '"' + $gui + '"'
    $sc.WorkingDirectory = $work
    $sc.IconLocation     = $icon
    $sc.Description       = 'Make scanned PDFs and images searchable (OCR)'
    $sc.WindowStyle       = 1
    $sc.Save()
    Write-Host "Created: $t"
}
