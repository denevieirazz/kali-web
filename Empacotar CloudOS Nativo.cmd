@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
echo [CloudOS Native] Validando build antes do pacote...
pwsh.exe -NoLogo -NoProfile -File "%ROOT%scripts\native\get-native-build-status.ps1" -Root "%ROOT%" >nul 2>&1
if errorlevel 1 (
  echo [CloudOS Native] Build ausente ou desatualizado. Compilando primeiro...
  call "%ROOT%scripts\native\build-cloudos-native.cmd" Release
  if errorlevel 1 exit /b %ERRORLEVEL%
)

echo [CloudOS Native] Criando pacote portatil verificado...
pwsh.exe -NoLogo -NoProfile -File "%ROOT%scripts\native\package-cloudos-native.ps1" -Root "%ROOT%" -Configuration Release
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" exit /b %RC%

echo.
echo [CloudOS Native] PACOTE_OK=%ROOT%desktop\CloudOS.NativeShell\artifacts\CloudOS-Native-Release-x64.zip
exit /b 0
