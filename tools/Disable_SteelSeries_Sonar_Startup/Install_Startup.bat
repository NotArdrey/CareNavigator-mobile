@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "PACKAGE_DIR=%~dp0"
set "SVV=%PACKAGE_DIR%SoundVolumeView.exe"
set "LAUNCHER=%PACKAGE_DIR%Disable_SteelSeries_Sonar_Startup.vbs"
set "STOP_FILE=%PACKAGE_DIR%Disable_SteelSeries_Sonar.stop"
set "STARTUP_DIR=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "STARTUP_LINK=%STARTUP_DIR%\Disable SteelSeries Sonar.lnk"
set "WSCRIPT_PATH=%SystemRoot%\System32\wscript.exe"

if not exist "%SVV%" (
    echo ERROR: SoundVolumeView.exe was not found.
    echo Download it from https://www.nirsoft.net/utils/soundvolumeview.html
    echo Then put SoundVolumeView.exe next to these scripts and run this installer again.
    exit /b 2
)

if not exist "%LAUNCHER%" (
    echo ERROR: Disable_SteelSeries_Sonar_Startup.vbs is missing.
    exit /b 2
)

if exist "%STOP_FILE%" del /f /q "%STOP_FILE%" >nul 2>&1
if not exist "%STARTUP_DIR%" mkdir "%STARTUP_DIR%" >nul 2>&1
if not exist "%STARTUP_DIR%" (
    echo ERROR: Could not access the current user's Startup folder.
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $ws=New-Object -ComObject WScript.Shell; $shortcut=$ws.CreateShortcut($env:STARTUP_LINK); $shortcut.TargetPath=$env:WSCRIPT_PATH; $shortcut.Arguments='//nologo ' + [char]34 + $env:LAUNCHER + [char]34; $shortcut.WorkingDirectory=$env:PACKAGE_DIR; $shortcut.Description='Disable only Sonar Gaming and Chat output while preserving both Microphone endpoints'; $shortcut.Save()"
if errorlevel 1 (
    echo ERROR: Could not create the Startup shortcut.
    exit /b 1
)

echo Installed: %STARTUP_LINK%
echo The hidden one-shot will wait 10 seconds, execute, wait another 10 seconds, execute again, and then exit.
exit /b 0
