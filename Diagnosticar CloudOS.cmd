@echo off
setlocal
where pwsh.exe >nul 2>nul || (echo PowerShell 7 ^(pwsh^) e obrigatorio. & exit /b 1)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\diagnostics\diagnose-cloudos.ps1" %*
exit /b %ERRORLEVEL%
