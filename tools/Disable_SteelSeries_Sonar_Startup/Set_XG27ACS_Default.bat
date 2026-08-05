@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%SteelSeries_Sonar_Audio.ps1"

if not exist "%PS_SCRIPT%" (
    echo ERROR: SteelSeries_Sonar_Audio.ps1 is missing from this folder.
    exit /b 2
)

echo Selecting only the exact XG27ACS (NVIDIA High Definition Audio) device as default playback.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Action SetDefault
set "EXIT_CODE=%ERRORLEVEL%"
if "%EXIT_CODE%"=="0" echo Done.
if not "%EXIT_CODE%"=="0" echo The exact XG27ACS device was not selected.
exit /b %EXIT_CODE%
