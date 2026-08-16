@echo off
setlocal
set "MODE=%~1"
if "%MODE%"=="" set "MODE=Full"
where pwsh.exe >nul 2>nul || (echo PowerShell 7 ^(pwsh^) e obrigatorio. & exit /b 1)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\launch\start-cloudos.ps1" -Mode "%MODE%"
exit /b %ERRORLEVEL%
