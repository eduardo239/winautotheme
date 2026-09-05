@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0WinAutoTheme.ps1" -Install
if errorlevel 1 (
    echo.
    echo Falha na instalacao. Execute este arquivo no Windows, nao no WSL.
)
echo.
pause
