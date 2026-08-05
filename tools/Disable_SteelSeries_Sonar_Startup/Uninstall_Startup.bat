@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "PACKAGE_DIR=%~dp0"
set "STOP_FILE=%PACKAGE_DIR%Disable_SteelSeries_Sonar.stop"
set "STARTUP_LINK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Disable SteelSeries Sonar.lnk"

rem Ask any currently running monitor to stop on its next five-second check.
> "%STOP_FILE%" echo stop

if exist "%STARTUP_LINK%" (
    del /f /q "%STARTUP_LINK%" >nul 2>&1
    if exist "%STARTUP_LINK%" (
        echo ERROR: Could not remove %STARTUP_LINK%
        exit /b 1
    )
    echo Removed: %STARTUP_LINK%
) else (
    echo Startup shortcut was not installed.
)

echo Automatic disabling is uninstalled. This did not delete the package files.
exit /b 0
