@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"

if not exist "%PWSH%" (
  echo [CloudOS] PowerShell 7 x64 nao encontrado.
  echo [CloudOS] Instale o PowerShell 7 x64 e tente novamente.
  exit /b 1
)

"%PWSH%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\validate\run-stabilization-batch1.ps1" %*
exit /b %ERRORLEVEL%
