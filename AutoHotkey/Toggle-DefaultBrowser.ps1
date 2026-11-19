<#
.SYNOPSIS
  Silently toggle the Windows default browser between Brave and Chrome.

.NOTES
  Windows 11's UCPD driver blocks scripts from writing the default-browser registry
  keys, so this drives the Settings > Default apps page with UI Automation instead:
  open page, pick the browser, press "Set default", verify, close Settings.
  Settings flashes on screen for a few seconds.
#>

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$A = [System.Windows.Automation.AutomationElement]
$CT = [System.Windows.Automation.ControlType]
$P = [System.Windows.Automation.PropertyCondition]

$httpsKey = 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice'
$current = (Get-ItemProperty $httpsKey -ErrorAction SilentlyContinue).ProgId

# Chrome -> Brave, anything else -> Chrome
if ($current -eq 'ChromeHTML') { $targetName = 'Brave';         $targetProgId = 'BraveHTML' }
else                           { $targetName = 'Google Chrome'; $targetProgId = 'ChromeHTML' }

Write-Host "Current default: $current  ->  switching to $targetName"

function Find-Element($root, $cond, $timeoutSec = 10) {
    $end = (Get-Date).AddSeconds($timeoutSec)
    do {
        $el = $root.FindFirst('Descendants', $cond)
        if ($el) { return $el }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $end)
    return $null
}

function Invoke-Element($el) {
    $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}

Start-Process 'ms-settings:defaultapps'

# Find the Settings window
$win = $null
$end = (Get-Date).AddSeconds(10)
while (-not $win -and (Get-Date) -lt $end) {
    $win = $A::RootElement.FindFirst('Children', (New-Object $P($A::NameProperty, 'Settings')))
    Start-Sleep -Milliseconds 250
}
if (-not $win) { throw 'Settings window did not appear.' }

# Open the target browser's page (list button named exactly "Brave" / "Google Chrome")
$listBtn = Find-Element $win (New-Object System.Windows.Automation.AndCondition(
        (New-Object $P($A::NameProperty, $targetName)),
        (New-Object $P($A::ControlTypeProperty, $CT::Button))))
if (-not $listBtn) { throw "Couldn't find '$targetName' in the Default apps list." }
Invoke-Element $listBtn

# Press "Set default"
$setBtn = Find-Element $win (New-Object $P($A::AutomationIdProperty,
        'SystemSettings_DefaultApps_DefaultBrowserWithPinToStartAndTaskbarAction_Button'))
if (-not $setBtn) { throw "Couldn't find the 'Set default' button." }
Invoke-Element $setBtn

# Verify
$ok = $false
$end = (Get-Date).AddSeconds(5)
while (-not $ok -and (Get-Date) -lt $end) {
    Start-Sleep -Milliseconds 300
    $ok = ((Get-ItemProperty $httpsKey -ErrorAction SilentlyContinue).ProgId -eq $targetProgId)
}

# Close Settings
try { $win.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close() } catch {}

if ($ok) { Write-Host "Default browser is now $targetName." }
else     { Write-Warning "Clicked 'Set default' but registry still shows a different default." ; exit 1 }
