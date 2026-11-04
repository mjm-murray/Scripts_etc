#Requires AutoHotkey v2.0
#SingleInstance Force

; --- Hotkeys ---
F13::ToggleTeamsMute()   ; F13 toggles Teams mute
^F13::ToggleTeamsCamera() ; Ctrl+F13 toggles Teams camera

ToggleTeamsMute() => SendToTeams("^+m")   ; Ctrl+Shift+M inside Teams
ToggleTeamsCamera() => SendToTeams("^+o") ; Ctrl+Shift+O inside Teams

SendToTeams(keys) {
    activeHwnd := WinExist("A")

    ; Try both new and classic Teams executables
    procs := ["ms-teams.exe", "Teams.exe"]
    exclude := Map("Microsoft Teams Notification", true)

    for proc in procs {
        for hwnd in WinGetList("ahk_exe " proc) {
            title := WinGetTitle("ahk_id " hwnd)
            if (title != "" && !exclude.Has(title)) {
                WinActivate("ahk_id " hwnd)
                if WinWaitActive("ahk_id " hwnd, , 0.5) {
                    Sleep 80
                    Send(keys)
                    Sleep 80
                }
            }
        }
    }

    ; Return focus to the previous window
    if activeHwnd
        WinActivate("ahk_id " activeHwnd)
}
