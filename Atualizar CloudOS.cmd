@echo off
setlocal
cd /d "%~dp0"

where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo [CloudOS] PowerShell nao foi encontrado.
  pause
  exit /b 1
)

powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\update\CloudOS-Updater.ps1"
set "CLOUDOS_UPDATER_EXIT=%ERRORLEVEL%"

if not "%CLOUDOS_UPDATER_EXIT%"=="0" (
  echo.
  echo [CloudOS] O atualizador encerrou com codigo %CLOUDOS_UPDATER_EXIT%.
  pause
)

exit /b %CLOUDOS_UPDATER_EXIT%
