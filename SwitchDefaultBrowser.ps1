#Requires -Version 5.1
# SwitchDefaultBrowser.ps1 - GUI tool to switch default browser on Windows 11
# Click a browser button to set it as your default.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Browser detection ---

function Get-Browsers {
    $list = [ordered]@{}

    $defs = @(
        @{
            Name           = 'Chrome'
            Display        = 'Google Chrome'
            ProgIds        = @('ChromeHTML')
            AppPathExe     = 'chrome.exe'
            SetDefaultArgs = '--make-default-browser'
        }
        @{
            Name           = 'Edge'
            Display        = 'Microsoft Edge'
            ProgIds        = @('MSEdgeHTM', 'MSEdgeDHTML', 'MSEdgeBHTML')
            AppPathExe     = 'msedge.exe'
            SetDefaultArgs = '--make-default-browser'
        }
        @{
            Name           = 'Brave'
            Display        = 'Brave'
            ProgIds        = @('BraveHTML', 'BraveSSHTM')
            AppPathExe     = 'brave.exe'
            SetDefaultArgs = '--make-default-browser'
        }
        @{
            Name           = 'Firefox'
            Display        = 'Mozilla Firefox'
            ProgIds        = @('FirefoxURL', 'FirefoxHTML')
            AppPathExe     = 'firefox.exe'
            SetDefaultArgs = '-setDefaultBrowser'
        }
    )

    $appPathsRoot = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths'
    $startMenuRoot = 'HKLM:\SOFTWARE\Clients\StartMenuInternet'

    foreach ($def in $defs) {
        $exe = $null

        # 1) Check App Paths registry (most reliable)
        $appPathKey = Join-Path $appPathsRoot $def.AppPathExe
        $appPathVal = (Get-ItemProperty $appPathKey -ErrorAction SilentlyContinue).'(default)'
        if ($appPathVal) {
            $clean = $appPathVal -replace '"', ''
            if (Test-Path $clean) { $exe = $clean }
        }

        # 2) Check StartMenuInternet registry
        if (-not $exe) {
            $smiEntries = Get-ChildItem $startMenuRoot -ErrorAction SilentlyContinue
            foreach ($entry in $smiEntries) {
                if ($entry.PSChildName -like "$($def.Name)*") {
                    $cmd = (Get-ItemProperty "$($entry.PSPath)\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
                    if ($cmd) {
                        $clean = ($cmd -replace '"', '').Trim()
                        if (Test-Path $clean) { $exe = $clean; break }
                    }
                }
            }
        }

        $list[$def.Name] = @{
            Display        = $def.Display
            Installed      = ($null -ne $exe)
            Path           = $exe
            ProgIds        = $def.ProgIds
            SetDefaultArgs = $def.SetDefaultArgs
        }
    }
    return $list
}

function Get-DefaultBrowserName {
    param($Browsers)
    try {
        $progId = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' -ErrorAction Stop).ProgId
    }
    catch { return $null }

    foreach ($name in $Browsers.Keys) {
        foreach ($pattern in $Browsers[$name].ProgIds) {
            if ($progId -like "$pattern*") { return $name }
        }
    }
    return $null
}

# --- Initialise state ---

$script:browsers       = Get-Browsers
$script:currentDefault = Get-DefaultBrowserName $script:browsers
$script:buttons        = @{}

# --- Colours ---

$bgDark    = [System.Drawing.Color]::FromArgb(32, 32, 32)
$bgPanel   = [System.Drawing.Color]::FromArgb(45, 45, 45)
$fgPrimary = [System.Drawing.Color]::White
$fgMuted   = [System.Drawing.Color]::FromArgb(170, 170, 170)
$fgSuccess = [System.Drawing.Color]::FromArgb(130, 220, 130)

$brandColours = @{
    Chrome  = [System.Drawing.Color]::FromArgb(34, 139, 34)
    Edge    = [System.Drawing.Color]::FromArgb(0, 120, 212)
    Brave   = [System.Drawing.Color]::FromArgb(187, 10, 30)
    Firefox = [System.Drawing.Color]::FromArgb(255, 149, 0)
}

$defaultBorder = [System.Drawing.Color]::FromArgb(100, 255, 100)

# --- Build form ---

$form = New-Object System.Windows.Forms.Form -Property @{
    Text            = 'Default Browser Switcher'
    Size            = New-Object System.Drawing.Size(420, 400)
    StartPosition   = 'CenterScreen'
    FormBorderStyle = 'FixedDialog'
    MaximizeBox     = $false
    BackColor       = $bgDark
    ForeColor       = $fgPrimary
    Font            = New-Object System.Drawing.Font('Segoe UI', 10)
}

# Title
$lblTitle = New-Object System.Windows.Forms.Label -Property @{
    Text     = 'Default Browser Switcher'
    Font     = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
    AutoSize = $true
    Location = New-Object System.Drawing.Point(24, 16)
}
$form.Controls.Add($lblTitle)

# Current-default indicator
$lblCurrent = New-Object System.Windows.Forms.Label -Property @{
    Font      = New-Object System.Drawing.Font('Segoe UI', 10)
    ForeColor = $fgMuted
    AutoSize  = $true
    Location  = New-Object System.Drawing.Point(24, 52)
}
$form.Controls.Add($lblCurrent)

# --- Helper to refresh the UI ---

function Update-UI {
    $new = Get-DefaultBrowserName $script:browsers
    $changed = $new -ne $script:currentDefault
    $script:currentDefault = $new

    $friendlyName = if ($new) { $script:browsers[$new].Display } else { 'Unknown' }
    $lblCurrent.Text = "Current default:  $friendlyName"

    foreach ($name in $script:buttons.Keys) {
        $btn  = $script:buttons[$name]
        $info = $script:browsers[$name]
        $isCurrent = ($name -eq $script:currentDefault)

        if ($info.Installed) {
            $btn.Text = if ($isCurrent) { "$($info.Display)  [DEFAULT]" } else { $info.Display }
            $btn.FlatAppearance.BorderSize  = if ($isCurrent) { 2 } else { 0 }
            $btn.FlatAppearance.BorderColor = $defaultBorder
        }
    }

    if ($changed -and $new) {
        $lblStatus.ForeColor = $fgSuccess
        $lblStatus.Text = "Default changed to $friendlyName!"
    }
}

# --- Browser buttons ---

$y = 88
$btnW = 360
$btnH = 48

foreach ($name in @('Chrome', 'Edge', 'Brave', 'Firefox')) {
    $info = $script:browsers[$name]

    $btn = New-Object System.Windows.Forms.Button -Property @{
        Size      = New-Object System.Drawing.Size($btnW, $btnH)
        Location  = New-Object System.Drawing.Point(24, $y)
        FlatStyle = 'Flat'
        Font      = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
        Cursor    = [System.Windows.Forms.Cursors]::Hand
        Tag       = $name
    }
    $btn.FlatAppearance.BorderSize = 0

    if ($info.Installed) {
        $isCurrent = ($name -eq $script:currentDefault)
        $btn.Text      = if ($isCurrent) { "$($info.Display)  [DEFAULT]" } else { $info.Display }
        $btn.BackColor  = $brandColours[$name]
        $btn.ForeColor  = $fgPrimary
        if ($isCurrent) {
            $btn.FlatAppearance.BorderSize  = 2
            $btn.FlatAppearance.BorderColor = $defaultBorder
        }

        $btn.Add_Click({
            param($sender)
            $bName = $sender.Tag
            $bInfo = $script:browsers[$bName]

            if ($bName -eq $script:currentDefault) {
                $lblStatus.ForeColor = $fgMuted
                $lblStatus.Text = "$($bInfo.Display) is already the default."
                return
            }

            # Launch the browser's own "set as default" flow
            try {
                Start-Process -FilePath $bInfo.Path -ArgumentList $bInfo.SetDefaultArgs -ErrorAction Stop
                $lblStatus.ForeColor = $fgSuccess
                $lblStatus.Text = "$($bInfo.Display) was asked to set itself as default.  Follow its prompt."
            }
            catch {
                # Fallback: open Windows Settings
                Start-Process 'ms-settings:defaultapps'
                $lblStatus.ForeColor = $fgMuted
                $lblStatus.Text = "Settings opened. Find '$($bInfo.Display)' and click 'Set default'."
            }
        })
    }
    else {
        $btn.Text      = "$($info.Display)  [Not Installed]"
        $btn.BackColor  = [System.Drawing.Color]::FromArgb(55, 55, 55)
        $btn.ForeColor  = [System.Drawing.Color]::FromArgb(110, 110, 110)
        $btn.Enabled    = $false
    }

    $script:buttons[$name] = $btn
    $form.Controls.Add($btn)
    $y += $btnH + 10
}

# Status label
$lblStatus = New-Object System.Windows.Forms.Label -Property @{
    Font      = New-Object System.Drawing.Font('Segoe UI', 9)
    ForeColor = $fgMuted
    Location  = New-Object System.Drawing.Point(24, ($y + 4))
    Size      = New-Object System.Drawing.Size($btnW, 40)
    Text      = 'Click a browser to set it as your default.'
}
$form.Controls.Add($lblStatus)

# Open Settings link (fallback)
$lnkSettings = New-Object System.Windows.Forms.LinkLabel -Property @{
    Text         = 'Open Default Apps Settings'
    Font         = New-Object System.Drawing.Font('Segoe UI', 9)
    AutoSize     = $true
    Location     = New-Object System.Drawing.Point(24, ($y + 40))
    LinkColor    = [System.Drawing.Color]::FromArgb(100, 180, 255)
    ActiveLinkColor   = [System.Drawing.Color]::FromArgb(140, 200, 255)
    VisitedLinkColor  = [System.Drawing.Color]::FromArgb(100, 180, 255)
}
$lnkSettings.Add_LinkClicked({ Start-Process 'ms-settings:defaultapps' })
$form.Controls.Add($lnkSettings)

# Timer: poll the registry every 2 s so the UI updates after the user changes the default
$timer = New-Object System.Windows.Forms.Timer -Property @{ Interval = 2000 }
$timer.Add_Tick({ Update-UI })
$timer.Start()

# Initial paint
Update-UI

$form.Add_FormClosing({ $timer.Stop(); $timer.Dispose() })
[void]$form.ShowDialog()
