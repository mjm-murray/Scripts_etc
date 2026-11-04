; AutoHotkey v2
F3::{
    A_Clipboard := A_Clipboard  ; strip formatting
    Send "^v"
}