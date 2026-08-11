@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Instalar-Hotfix-UI-02.1.ps1"
echo.
pause
