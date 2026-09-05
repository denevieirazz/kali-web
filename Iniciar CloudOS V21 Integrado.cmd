@echo off
setlocal EnableExtensions
set "ROOT=%~dp0desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release"
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\start-cloudos-v21-integrated.ps1" -Root "%ROOT%"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" pause
exit /b %RC%
