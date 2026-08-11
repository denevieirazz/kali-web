@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Reverter-Ultima-Correcao-Core-UI.ps1"
echo.
pause
