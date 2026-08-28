@echo off
setlocal
cd /d "%~dp0"

where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo [Updater] PowerShell nao foi encontrado.
  pause
  exit /b 1
)

powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\update\CloudOS-Updater.ps1"
set "UPDATER_EXIT=%ERRORLEVEL%"

if not "%UPDATER_EXIT%"=="0" (
  echo.
  echo [Updater] O atualizador encerrou com codigo %UPDATER_EXIT%.
  pause
)

exit /b %UPDATER_EXIT%
