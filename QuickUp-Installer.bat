@echo off
title QuickUp Installer
echo.
echo   ==========================================
echo      QuickUp  -  Installer
echo   ==========================================
echo.
echo   Adds a "QuickUp" entry to your right-click menu so you can
echo   upload any file and copy a shareable link in one click.
echo.
echo   No administrator rights are required.
echo.
echo   Installing, please wait...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; irm https://raw.githubusercontent.com/Riyoway/quickup/main/quickup.ps1 | iex"
echo.
if errorlevel 1 (
  echo   Install failed. Check your internet connection and run this again.
) else (
  echo   All set. Right-click any file and choose QuickUp.
)
echo.
pause
