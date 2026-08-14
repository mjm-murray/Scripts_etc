$names = 'OneDrive','FileSyncHelper','FileCoAuth','Sentinel*'
$cores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$now   = Get-Date

# PID -> start time, via CIM (Get-Process StartTime may be blocked on protected procs)
$births = @{}
Get-CimInstance Win32_Process | ForEach-Object { $births[[int]$_.ProcessId] = $_.CreationDate }

$before = @{}
Get-Process -Name $names -ErrorAction SilentlyContinue | ForEach-Object { $before[$_.Id] = $_.CPU }

Start-Sleep -Seconds 60

$rows = foreach ($p in Get-Process -Name $names -ErrorAction SilentlyContinue) {
    if (-not $before.ContainsKey($p.Id)) { continue }

    $delta = $p.CPU - $before[$p.Id]
    $birth = $births[$p.Id]

    $upHrs = $null
    $avg   = $null
    if ($birth) {
        $upSec = ($now - $birth).TotalSeconds
        $upHrs = [math]::Round($upSec / 3600, 1)
        if ($upSec -gt 0) { $avg = [math]::Round($p.CPU / $upSec / $cores * 100, 2) }
    }

    [pscustomobject]@{
        Name       = $p.Name
        Id         = $p.Id
        DeltaSec   = [math]::Round($delta, 2)
        PctMachine = [math]::Round($delta / 60 / $cores * 100, 2)
        UpHrs      = $upHrs
        AvgPct     = $avg
        WS_MB      = [math]::Round($p.WorkingSet64 / 1MB, 0)
    }
}

$rows | Sort-Object DeltaSec -Descending | Format-Table -AutoSize