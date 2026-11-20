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
:*?:/*nn::Michael Murray
:*?:/*tt::∴
:*?:/*uu::is:unread
:*?:/*al::α
:*?:/*pos::⌖
:*?T:/*pp::b00L3an!!##
:*?T:/*ff::Spindoctors00
:*?:/*x::×
::/*rd::site:reddit.com
:*?:/*ar::→
::/*s::SOLIDWORKS
:*?:/*st::My resume, design portfolio, manufacturing experience, and employment timeline are all available on my website: https://mjm-murray.github.io/. The direct link to my resume is: https://mjm-murray.github.io/Resume-Michael_Murray.pdf.
:*?:/*hy::Could you please let me know what city the position would be in and whether it's 5 days in office or if it's hybrid, what that entails?
:*?:/*rel::I'm not interested in relocating at the moment, but thank you for reaching out.
:*?:/*tau::τ
:*?:/*pi::π
:*?:/*sag::Sagar Shrivastava
:*?:/*usig::Σ
:*?:/*sqrt::√
:*?:/*dot::⋅
:*?:/*pn::9198241597
:*?:/*lnd::https://www.linkedin.com/in/michaeljohnmurray/
:*?:/*git::https://mjm-murray.github.io/
:*?:/*SF::San Francisco
::/*iec::IEC 60068-2-52 Method 7
:*?:/*shut::bash sudo shutdown -h now
:*?:/*log::journalctl -u rfid-lock.service -f
:*?:/*roc::sudo systemctl restart rocker_servo_lock.service
:*:/*pro::PROTOTYPE ONLY: NOT FOR SERIES MANUFACTURE
:*?:/*fn::$PRP:"SW-File Name"
:*?:/*bb::{Text}V1cV1negar!!&&
:*?:/*wm::WELD MATERIAL: ER80S-D2 OR ER90S-D2
:*?:/*fmpeg::ffmpeg -i recording.mkv -vn -c:a copy audio.m4a

;------------PART NUMBERS-----------

;------------PYTHON-----------------
:*?:/*log::journalctl -u rfid-lock.service -f
:*?:/*pykill::sudo killall python3
:*?:/*pyopen::python3 servo_motor_rotation.py open
:*?:/*pycdocs::cd ~/Documents/
:*?:/*pyprocs::ps aux | grep python
:*?:/*pyreset::sudo systemctl restart rfid-escape
:*?:/*log::journalctl -u rfid-lock.service -f
:*?:/*shut::bash sudo shutdown -h now
:*?:/*pyread::journalctl -u rfid-escape -f


;-------SOLIDWORKS------
::/*s::SOLIDWORKS
::/*ss::SOLIDWORKS Simulation

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

#+k::RestartSTAR()

RestartSTAR() {
    try {
        ProcessClose("STAR.exe")
    } catch {
    }

    try {
        ProcessClose("NSTAR.exe")
    } catch {
    }
}


;-------WORDS & SHORTCUTS-------
:*:/*e::mmurray@formenergy.com
:*:*/s::SOLIDWORKS
:*:/*mj::mjm.murray@gmail.com

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
::/*addd::
{
    SendText("Michael Murray`n878 Shotwell St.`nGate Code C1789X`nSan Francisco, CA 94110")
}
::/*ad::878 Shotwell St.
::/*add::Gate Code C1789X
{
    SendText("Michael Murray`n878 Shotwell St.`nGate Code C1789X`nSan Francisco, CA 94110")
}
::/*aaad::878 Shotwell St.
::/*z::94110

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

;F6 toggles mic/mute
F6::TeamsToggle("^+m")
;F6+Shift toggles camera
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
    ps1 := "C:\Users\mjmmu\Documents\Scripts_etc\AutoHotkey\CloseAll.ps1"
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
    psScript := "C:\Users\mjmmu\Documents\Scripts_etc\AutoHotkey\restart_explorer.ps1"
    Run('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' psScript '"', , "Hide")
}

;---------TOGGLE DEFAULT BROWSER------------
; --- Win + Shift + B: switch default browser Brave <-> Chrome ---
#+b:: {
    ps1 := A_ScriptDir "\Toggle-DefaultBrowser.ps1"
    if !FileExist(ps1) {
        MsgBox "Could not find " ps1, "Error"
        return
    }
    ; Only the PowerShell window is hidden; Settings must stay visible for UI Automation.
    Run('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' ps1 '"', , "Hide")
}


/*
================================================================================
AHK v2 Hotstring Options Reference
Structure: :<Options>:<Trigger>::<Replacement or Action>
================================================================================

--- Common Option Flags ---
*  : Instant trigger — fires immediately without waiting for an EndChar (Space/Enter/Tab).
?  : Trigger inside words — fires even if typed immediately after alphanumeric characters.
O  : Omit EndChar — triggers after an EndChar, but deletes the EndChar from output.
C  : Case-sensitive — matches exact uppercase/lowercase trigger only.
C1 : Do NOT conform case — replacement keeps exact case defined, ignoring typed case.
B0 : No backspacing — prevents AHK from automatically deleting the trigger characters.
T  : Raw text mode — sends replacement as literal text without interpreting special keys.
X  : Execute mode — executes the replacement as an expression/function rather than text.

--- Variations of /s & */s Triggers ---

::/s::replacement
  - Default behavior.
  - Requires a word boundary before '/s' and an EndChar (Space/Enter) after to fire.
  - The EndChar is kept in the output.

:*:/s::replacement
  - Immediate trigger.
  - Fires instantly upon typing '/s' without needing Space/Enter.
  - Still requires a preceding word boundary/space.

:?:/s::replacement
  - Inside-word trigger.
  - Fires anywhere (e.g., typing 'abc/s' works), but still requires an EndChar after.

:*:*/s::replacement
  - Immediate trigger with literal '*/s' as trigger text.
  - Fires instantly as soon as '*/s' is typed.

:?::/s::replacement
  - Inside-word + Default ending.
  - Fires even if embedded inside other characters, but waits for an EndChar.

:*?:/s::replacement
  - Immediate + Inside words (Most aggressive).
  - Fires instantly anywhere you type '/s' (even inside other words, like 'test/s').

:O:/s::replacement
  - Omit ending character.
  - Waits for an EndChar (e.g., Space) to fire, but automatically strips the space.

:*B0:/s::replacement
  - Immediate + No backspace.
  - Fires immediately without deleting the '/s' text you just typed.

:X:/s::MyFunction()
  - Execute mode.
  - Runs 'MyFunction()' when triggered instead of outputting replacement text.
================================================================================
*/