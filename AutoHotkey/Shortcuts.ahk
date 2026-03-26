;---------SYMBOLS ETC------------
::/*b::•
::/*sb::  ◦
:*?:/*dg::°
:*?:/*dl::Δ
:*?:/*dd::Ø
:*?:/*ge::≥
:*?:/*le::≤
:*?:/*pm::±
:*?:/*si::σ
:*?:/*Csi::Σ
:*?:/*mu::μ
:*?:/*th::Θ
:*?:/*tt::∴
:*?:/*al::α
::/*rd::site:reddit.com
::/*ar::→
::/*s::SOLIDWORKS
::/*ss::SOLIDWORKS Simulation
:*?:/*tau::τ
:*?:/*pi::π
:*?:/*usig::Σ
:*?:/*sqrt::√
:*?:/*dot::⋅
::/*iec::IEC 60068-2-52 Method 7
:*?:/*shut::bash sudo shutdown -h now
:*?:/*log::journalctl -u rfid-lock.service -f
:*:/*gm::mjm.murray@gmail.com
:*:/*pro::PROTOTYPE ONLY: NOT FOR SERIES MANUFACTURE
:*?:/*fn::$PRP:"SW-File Name"
:*?:/*wm::WELD MATERIAL: ER80S-D2 OR ER90S-D2


;-------RESTART SOLIDWORKS------

#+w::RestartSolidWorks()

RestartSolidWorks() {
    ; Force-close if running (ignore errors if not found)
    try ProcessClose("SLDWORKS.exe")
    catch

    try ProcessClose("SolidWorks.exe")
    catch

    try ProcessClose("STAR.exe")
    catch

    try ProcessClose("NSTAR.exe")
    catch

    Sleep 2000

    ; Adjust if your install path differs
    swPath := "C:\Program Files\SOLIDWORKS Corp\SOLIDWORKS\SLDWORKS.exe"

    if FileExist(swPath)
        Run swPath
    else
        MsgBox "SolidWorks executable not found.`nCheck swPath in the script."
}


;-------WORDS & SHORTCUTS-------
#---------ENTER YOUR EMAIL--------------
:*:/*e::YOUREMAIL@nevados.solar
:*:*/s::SOLIDWORKS

;------NUMLOCK------------
#SingleInstance Force
SetNumLockState "AlwaysOn"  ; keep NumLock on at startup

; Intercept NumLock key and send F22 instead
$NumLock::
{
    SetNumLockState "On"    ; make sure it stays on
    Send "• "               ; Output bullet + space
}

;---------ADDRESSES------------
::/*add::
{
    SendText("Nevados Engineering`nAttn: Mike Murray`n55 4th Street`nOakland, CA 94607")
}
::/*ad::55 4th Street
::/*z::94607

;---------- Teams mute/camera toggles -----------
#Requires AutoHotkey v2.0

FindBestTeamsWindow() {
    hwndFound := 0

    procs := ["ms-teams.exe", "Teams.exe"]

    for proc in procs {
        for hwnd in WinGetList("ahk_exe " proc) {
            try {
                cls := WinGetClass("ahk_id " hwnd)

                ; Skip UWP-ish shells / bogus windows
                if (cls = "Windows.UI.Core.CoreWindow")
                    continue

                WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
                if (w < 200 || h < 200)
                    continue

                return hwnd
            }
        }
    }
    return hwndFound
}

#F6 toggles mute
F6::TeamsToggle("^+m")
#Shift+F6 toggles camera
^F6::TeamsToggle("^+o")

TeamsToggle(keys) {
    ; Capture current active window (guarded; WinGetID("A") can throw)
    active := 0
    try active := WinGetID("A")

    ; If Teams is already active, just send
    try {
        if WinActive("ahk_exe ms-teams.exe") || WinActive("ahk_exe Teams.exe") {
            SendInput(keys)
            ShowNotify(keys)
            return
        }
    }

    DetectHiddenWindows true

    hwnd := FindBestTeamsWindow()
    if !hwnd {
        ShowNotify("notfound")
        return
    }

    ; Activate Teams, send, then restore focus
    wasMin := 0
    try wasMin := (WinGetMinMax("ahk_id " hwnd) = -1)

    try WinRestore("ahk_id " hwnd)
    try WinActivate("ahk_id " hwnd)

    if WinWaitActive("ahk_id " hwnd, , 1.0) {
        Sleep 60
        SendInput(keys)
        Sleep 60
        ShowNotify(keys)
    } else {
        ShowNotify("activatefail")
        return
    }

    if wasMin
        try WinMinimize("ahk_id " hwnd)

    ; Restore prior focus (only if we successfully captured an hwnd)
    if active && WinExist("ahk_id " active)
        try WinActivate("ahk_id " active)
}

ShowNotify(keysOrStatus) {
    ; Duration is in seconds in AHK v2.
    if (keysOrStatus = "^+m")
        TrayTip("Microsoft Teams", "Mic toggled (Ctrl+Shift+M)", 2)
    else if (keysOrStatus = "^+o")
        TrayTip("Microsoft Teams", "Camera toggled (Ctrl+Shift+O)", 2)
    else if (keysOrStatus = "notfound")
        TrayTip("Microsoft Teams", "No Teams window found", 2)
    else if (keysOrStatus = "activatefail")
        TrayTip("Microsoft Teams", "Couldn't activate Teams window", 2)
    else
        TrayTip("Microsoft Teams", "Action sent", 2)
}


;---------SHUTDOWN------------
; --- Function to run PowerShell close-all script ---
runCloseAll() {
    ps1 := "C:\Users\MikeMurray\Documents\AutoHotkey\CloseAll.ps1"
    if !FileExist(ps1) {
        MsgBox "Could not find " ps1, "Error"
        return
    }
    Run('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' ps1 '"', , "Hide")
}

; --- Win + Shift + X ---
#+X:: runCloseAll()

; --- Win + Shift + V ---
#+v:: {
    runCloseAll()
    Run('shutdown.exe /s /t 30')
}

; --- Win + Shift + E ---
#+e:: {
    psScript := "C:\Users\MikeMurray\Documents\AutoHotkey\restart_explorer.ps1"
    Run('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' psScript '"', , "Hide")
}