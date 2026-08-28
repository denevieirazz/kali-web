@echo off
setlocal
where pwsh.exe >nul 2>&1 || (echo ERRO: PowerShell 7 ^(pwsh.exe^) e obrigatorio. & exit /b 1)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\native\prepare-native-runtime.ps1"
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" pause
exit /b %CODE%
