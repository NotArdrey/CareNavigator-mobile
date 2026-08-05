@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%SteelSeries_Sonar_Audio.ps1"

if not exist "%PS_SCRIPT%" (
    echo ERROR: SteelSeries_Sonar_Audio.ps1 is missing from this folder.
    exit /b 2
)

if /I "%~1"=="/quiet" (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Action Disable -Quiet
) else (
    echo This pass disables only Sonar Gaming and Chat output; keeps both Microphone endpoints enabled, keeps Microphone input default, and selects XG27ACS as default playback.
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Action Disable
)

set "EXIT_CODE=%ERRORLEVEL%"
if not "%~1"=="/quiet" (
    if "%EXIT_CODE%"=="0" echo Done.
    if not "%EXIT_CODE%"=="0" echo No changes were made or the helper reported an error.
)
exit /b %EXIT_CODE%
