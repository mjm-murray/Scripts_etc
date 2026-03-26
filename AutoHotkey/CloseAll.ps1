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
}