@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
echo [CloudOS Native] Build verificado Release x64
echo.
call "%ROOT%scripts\native\build-cloudos-native.cmd" Release
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
  echo [CloudOS Native] BUILD FALHOU com codigo %RC%.
  exit /b %RC%
)
echo [CloudOS Native] BUILD OK.
echo [CloudOS Native] Execute "Verificar CloudOS Nativo.cmd" para consultar fingerprint e hashes.
exit /b 0
