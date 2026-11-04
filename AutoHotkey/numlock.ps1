# Make NumLock "ON" by default for current user and default login

# Current user
Set-ItemProperty -Path 'HKCU:\Control Panel\Keyboard' `
    -Name InitialKeyboardIndicators -Value '2'

# Default user (affects logon screen / new profiles)
Set-ItemProperty -Path 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard' `
    -Name InitialKeyboardIndicators -Value '2'
