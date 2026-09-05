@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0WinAutoTheme.ps1" -Uninstall
echo.
pause
