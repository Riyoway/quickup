@echo off
setlocal
rem QuickUp installer/uninstaller. Double-click to run.
set "SCRIPT=%~dp0quickup.ps1"

if not exist "%SCRIPT%" (
    echo Could not find quickup.ps1 next to this file.
    pause
    exit /b 1
)

echo ==================================
echo   QuickUp
echo ==================================
echo   [1] Install    add to the right-click menu
echo   [2] Uninstall  remove from the right-click menu
echo.
set /p "choice=Select [1/2]: "

if "%choice%"=="1" set "verb=install"
if "%choice%"=="2" set "verb=uninstall"

if not defined verb (
    echo Cancelled.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %verb%
echo.
pause
