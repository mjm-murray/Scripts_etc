[CmdletBinding()]
param(
    [string]$Folder,
    [string]$LogPath,
    [string]$ConfigPath
)

$ErrorActionPreference = 'Continue'

# $PSScriptRoot is empty inside the param block under Windows PowerShell 5.1 — resolve in the body.
$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $Folder)     { $Folder     = Split-Path -Parent $scriptRoot }
if (-not $LogPath)    { $LogPath    = Join-Path $scriptRoot 'watch.log' }
if (-not $ConfigPath) { $ConfigPath = Join-Path $scriptRoot 'config.json' }

# ---- Load config (defaults if file missing or invalid) ----
$cfg = [pscustomobject]@{
    whisperModel = 'turbo'
    language     = 'en'
    stages       = [pscustomobject]@{ format = $true; docx = $true; notes = $true }
}
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $loaded = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        if ($loaded.whisperModel) { $cfg.whisperModel = [string]$loaded.whisperModel }
        if ($loaded.language)     { $cfg.language     = [string]$loaded.language }
        if ($loaded.stages) {
            if ($null -ne $loaded.stages.format) { $cfg.stages.format = [bool]$loaded.stages.format }
            if ($null -ne $loaded.stages.docx)   { $cfg.stages.docx   = [bool]$loaded.stages.docx }
            if ($null -ne $loaded.stages.notes)  { $cfg.stages.notes  = [bool]$loaded.stages.notes }
        }
    } catch {
        # Fall back to defaults; log later once Write-Log is defined.
    }
}

function Write-Log {
    param([string]$Message)
    $line = "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $Message
    Add-Content -LiteralPath $LogPath -Value $line
}

function Wait-ForFileReady {
    param([string]$Path, [int]$TimeoutSec = 600)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'None')
            $fs.Close()
            return $true
        } catch {
            Start-Sleep -Seconds 3
        }
    }
    return $false
}

function Invoke-Transcribe {
    param([string]$Mp4Path)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($Mp4Path)
    $dir  = Split-Path -Parent $Mp4Path
    $transcript = Join-Path $dir "$stem.transcript.md"
    if (Test-Path -LiteralPath $transcript) {
        Write-Log "Skip (transcript exists): $Mp4Path"
        return
    }
    Write-Log "Waiting for write completion: $Mp4Path"
    if (-not (Wait-ForFileReady -Path $Mp4Path)) {
        Write-Log "Timeout waiting for file to be ready: $Mp4Path"
        return
    }
    Write-Log "Transcribing: $Mp4Path  (model=$($cfg.whisperModel), lang=$($cfg.language), format=$($cfg.stages.format), docx=$($cfg.stages.docx), notes=$($cfg.stages.notes))"
    try {
        # Hashtable splat: array splat under Windows PowerShell 5.1 passes elements
        # positionally even when '-Name' strings are present, which breaks named-param binding.
        $tArgs = @{ Path = $Mp4Path; Model = $cfg.whisperModel; Language = $cfg.language }
        if (-not $cfg.stages.format) { $tArgs.SkipFormat = $true }
        if (-not $cfg.stages.docx)   { $tArgs.SkipDocx   = $true }
        if (-not $cfg.stages.notes)  { $tArgs.SkipNotes  = $true }

        & (Join-Path $PSScriptRoot 'transcribe.ps1') @tArgs 2>&1 |
            ForEach-Object { Write-Log "  $_" }
        Write-Log "Done: $Mp4Path"
    } catch {
        Write-Log "ERROR transcribing $Mp4Path : $($_.Exception.Message)"
    }
}

Write-Log "Watcher starting. Folder=$Folder Config=$ConfigPath (loaded: $(Test-Path -LiteralPath $ConfigPath))"

# Process any existing un-transcribed MP4s at startup.
Get-ChildItem -LiteralPath $Folder -Filter *.mp4 -File -ErrorAction SilentlyContinue |
    ForEach-Object { Invoke-Transcribe -Mp4Path $_.FullName }

$fsw = New-Object System.IO.FileSystemWatcher
$fsw.Path = $Folder
$fsw.Filter = '*.mp4'
$fsw.IncludeSubdirectories = $false
$fsw.NotifyFilter = [System.IO.NotifyFilters]'FileName, LastWrite, Size'

$action = {
    $p = $Event.SourceEventArgs.FullPath
    try { Invoke-Transcribe -Mp4Path $p } catch { Write-Log "Handler error: $($_.Exception.Message)" }
}

Register-ObjectEvent -InputObject $fsw -EventName Created -Action $action | Out-Null
Register-ObjectEvent -InputObject $fsw -EventName Renamed -Action $action | Out-Null

$fsw.EnableRaisingEvents = $true
Write-Log "Watcher armed."

# Keep the script alive.
while ($true) { Start-Sleep -Seconds 60 }
