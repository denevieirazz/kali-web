@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Instalar-Correcao-Core-UI.ps1"
echo.
pause
