@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
pwsh.exe -NoLogo -NoProfile -File "%ROOT%scripts\native\get-native-build-status.ps1" -Root "%ROOT%"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
  echo [CloudOS Native] O build precisa ser atualizado ou reparado.
  echo [CloudOS Native] Execute: "Iniciar CloudOS Nativo.cmd" --force-rebuild
) else (
  echo [CloudOS Native] Build pronto para executar.
)
exit /b %RC%
