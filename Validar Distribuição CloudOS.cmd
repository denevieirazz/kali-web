@echo off
setlocal
where pwsh.exe >nul 2>&1 || (echo ERRO: PowerShell 7 ^(pwsh.exe^) e obrigatorio.& exit /b 1)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\productization\validate-distribution.ps1"
exit /b %ERRORLEVEL%
