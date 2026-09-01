@echo off
setlocal
cd /d "%~dp0"
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\flutter\preview-cloudos-flutter-v21.ps1" -Run
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" (
  echo.
  echo CloudOS V21 Preview falhou com codigo %EXITCODE%.
  pause
)
exit /b %EXITCODE%
