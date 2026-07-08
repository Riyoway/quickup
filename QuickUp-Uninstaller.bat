@echo off
title QuickUp Uninstaller
echo.
echo   Removing QuickUp from your right-click menu...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Join-Path $env:LOCALAPPDATA 'QuickUp\quickup.ps1'; if (Test-Path $p) { & $p uninstall } else { Write-Host 'QuickUp does not appear to be installed.' -ForegroundColor Yellow }"
echo.
pause
