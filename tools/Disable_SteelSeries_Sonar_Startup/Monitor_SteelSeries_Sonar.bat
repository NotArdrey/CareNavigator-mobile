@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "DISABLE_SCRIPT=%SCRIPT_DIR%Disable_SteelSeries_Sonar.bat"
set "STOP_FILE=%SCRIPT_DIR%Disable_SteelSeries_Sonar.stop"
set "STARTUP_DELAY_SECONDS=10"

if not exist "%DISABLE_SCRIPT%" exit /b 2

if exist "%STOP_FILE%" exit /b 0

rem Wait 10 seconds for SteelSeries GG to initialize, then execute the first pass.
timeout /t %STARTUP_DELAY_SECONDS% /nobreak >nul 2>&1

if exist "%STOP_FILE%" exit /b 0

call "%DISABLE_SCRIPT%" /quiet >nul 2>&1

if exist "%STOP_FILE%" exit /b 0

rem Give GG another 10 seconds to finish creating its virtual endpoints.
timeout /t %STARTUP_DELAY_SECONDS% /nobreak >nul 2>&1

if exist "%STOP_FILE%" exit /b 0

rem Execute the second confirming pass, then exit.
call "%DISABLE_SCRIPT%" /quiet >nul 2>&1
exit /b %ERRORLEVEL%
