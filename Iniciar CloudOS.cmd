@echo off
setlocal
set "MODE=%~1"
if "%MODE%"=="" set "MODE=Full"

if /I "%MODE%"=="Native" (
  call "%~dp0scripts\native\start-cloudos-native.cmd"
  exit /b %ERRORLEVEL%
)

where pwsh.exe >nul 2>nul || (echo PowerShell 7 ^(pwsh^) e obrigatorio. & exit /b 1)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\launch\start-cloudos.ps1" -Mode "%MODE%"
exit /b %ERRORLEVEL%
