# CloseAll.ps1
Add-Type -AssemblyName PresentationFramework

$result = [System.Windows.MessageBox]::Show(
    "Are you sure you want to close all open applications?",
    "Close All Apps",
    "YesNo",
    "Question"
)

if ($result -ne "Yes") {
    Write-Host "Operation cancelled."
    exit
}

Write-Host "Closing applications that can close without further input..."

# How many times to retry closing remaining apps
$maxPasses = 4

# Delay between passes, in milliseconds
$delayBetweenPasses = 2000

# Keep track of processes we've already asked to close in a given pass
for ($pass = 1; $pass -le $maxPasses; $pass++) {
    Write-Host ""
    Write-Host "Pass $pass of $maxPasses..."

    $processes = Get-Process | Where-Object {
        $_.MainWindowHandle -ne 0 -and
        $_.ProcessName -notin @("explorer", "ShellExperienceHost", "StartMenuExperienceHost", "SearchHost")
    }

    if (-not $processes) {
        Write-Host "No more open application windows found."
        break
    }

    foreach ($proc in $processes) {
        try {
            if (-not $proc.HasExited) {
                $sent = $proc.CloseMainWindow()

                if ($sent) {
                    Write-Host "Close requested: $($proc.ProcessName)"
                } else {
                    Write-Host "No close request sent: $($proc.ProcessName)"
                }
            }
        } catch {
            Write-Host "Could not access: $($proc.ProcessName)"
        }
    }

    Start-Sleep -Milliseconds $delayBetweenPasses
}

Write-Host ""
$remaining = Get-Process | Where-Object {
    $_.MainWindowHandle -ne 0 -and
    $_.ProcessName -notin @("explorer", "ShellExperienceHost", "StartMenuExperienceHost", "SearchHost")
} | Sort-Object ProcessName

if ($remaining) {
    Write-Host "These apps are still open, likely waiting for input or refusing to close:"
    $remaining | Select-Object -ExpandProperty ProcessName -Unique | ForEach-Object {
        Write-Host " - $_"
    }
} else {
    Write-Host "All closeable applications were closed."
}v
















<#
# CloseAll.ps1
Add-Type -AssemblyName PresentationFramework

$result = [System.Windows.MessageBox]::Show(
    "Are you sure you want to close all open applications?",
    "Close All Apps",
    "YesNo",
    "Question"
)

if ($result -eq "Yes") {
    Write-Host "Closing all open applications..."
    Get-Process | Where-Object { $_.MainWindowTitle } | ForEach-Object {
        try {
            $_.CloseMainWindow() | Out-Null
        } catch {
            Write-Host "Could not close $($_.ProcessName)"
        }
    }
    Write-Host "All close requests sent."
} else {
    Write-Host "Operation cancelled."
}#>