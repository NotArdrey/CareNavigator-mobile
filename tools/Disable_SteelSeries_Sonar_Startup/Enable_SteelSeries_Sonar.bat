@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%SteelSeries_Sonar_Audio.ps1"
set "STOP_FILE=%SCRIPT_DIR%Disable_SteelSeries_Sonar.stop"

if not exist "%PS_SCRIPT%" (
    echo ERROR: SteelSeries_Sonar_Audio.ps1 is missing from this folder.
    exit /b 2
)

rem Stop the active monitor before enabling the devices, so it does not undo this action.
> "%STOP_FILE%" echo stop

if /I "%~1"=="/quiet" (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Action Enable -Quiet
) else (
    echo The startup monitor is being stopped, then the three exact SteelSeries Sonar names will be enabled.
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Action Enable
)

set "EXIT_CODE=%ERRORLEVEL%"
if not "%~1"=="/quiet" (
    if "%EXIT_CODE%"=="0" echo Done. Run Install_Startup.bat again if you want automatic disabling to resume.
    if not "%EXIT_CODE%"=="0" echo The helper reported an error.
)
exit /b %EXIT_CODE%
