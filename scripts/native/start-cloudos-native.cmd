@echo off
setlocal EnableExtensions

set "ROOT=%~dp0..\.."
for %%I in ("%ROOT%") do set "ROOT=%%~fI"
set "OUT=%ROOT%\desktop\CloudOS.NativeShell\bin\Release"
set "EXE=%OUT%\CloudOS.exe"
set "DLL=%OUT%\CloudOS.NativeRuntime.dll"
set "SUPERVISOR=%OUT%\CloudOS.Supervisor.exe"
set "MANIFEST=%OUT%\cloudos-native-manifest.json"
set "HEAD_STAMP=%OUT%\.cloudos-build-head"
set "FINGERPRINT_STAMP=%OUT%\.cloudos-build-fingerprint"
set "FINGERPRINT_SCRIPT=%ROOT%\scripts\native\get-native-build-fingerprint.ps1"
set "VERIFY_SCRIPT=%ROOT%\scripts\native\verify-native-build-manifest.ps1"
set "REBUILD_REASON="
set "FORCE_REBUILD="
set "NO_BUILD="

:PARSE_ARGS
if "%~1"=="" goto ARGS_DONE
if /I "%~1"=="--force-rebuild" set "FORCE_REBUILD=1"
if /I "%~1"=="/force" set "FORCE_REBUILD=1"
if /I "%~1"=="--no-build" set "NO_BUILD=1"
if /I "%~1"=="/nobuild" set "NO_BUILD=1"
shift
goto PARSE_ARGS

:ARGS_DONE
if defined FORCE_REBUILD (
  set "REBUILD_REASON=rebuild forcado pelo usuario"
  goto NEED_BUILD
)

if not exist "%EXE%" (
  set "REBUILD_REASON=CloudOS.exe ausente"
  goto NEED_BUILD
)
if not exist "%DLL%" (
  set "REBUILD_REASON=CloudOS.NativeRuntime.dll ausente"
  goto NEED_BUILD
)
if not exist "%SUPERVISOR%" (
  set "REBUILD_REASON=CloudOS.Supervisor.exe ausente"
  goto NEED_BUILD
)
if not exist "%MANIFEST%" (
  set "REBUILD_REASON=manifesto de integridade ausente"
  goto NEED_BUILD
)
if not exist "%FINGERPRINT_STAMP%" (
  set "REBUILD_REASON=fingerprint da revisao compilada ausente"
  goto NEED_BUILD
)
if not exist "%FINGERPRINT_SCRIPT%" exit /b 20
if not exist "%VERIFY_SCRIPT%" exit /b 21

set "CURRENT_FINGERPRINT="
for /f "usebackq tokens=*" %%H in (`pwsh.exe -NoLogo -NoProfile -File "%FINGERPRINT_SCRIPT%" -Root "%ROOT%" 2^>nul`) do set "CURRENT_FINGERPRINT=%%H"
if not defined CURRENT_FINGERPRINT (
  set "REBUILD_REASON=nao foi possivel calcular o fingerprint atual das fontes"
  goto NEED_BUILD
)

set "BUILT_FINGERPRINT="
set /p BUILT_FINGERPRINT=<"%FINGERPRINT_STAMP%"
if not defined BUILT_FINGERPRINT (
  set "REBUILD_REASON=fingerprint compilado vazio"
  goto NEED_BUILD
)
if /I not "%CURRENT_FINGERPRINT%"=="%BUILT_FINGERPRINT%" (
  set "REBUILD_REASON=o codigo nativo mudou desde o ultimo build"
  goto NEED_BUILD
)

pwsh.exe -NoLogo -NoProfile -File "%VERIFY_SCRIPT%" -Root "%ROOT%" -Configuration Release -CheckSourceFingerprint >nul 2>&1
if errorlevel 1 (
  set "REBUILD_REASON=a verificacao de integridade/proveniencia falhou"
  goto NEED_BUILD
)

goto RUN

:NEED_BUILD
if defined NO_BUILD (
  echo [CloudOS Native] Build necessario, mas --no-build foi solicitado: %REBUILD_REASON%.
  exit /b 22
)

goto BUILD

:BUILD
if defined REBUILD_REASON echo [CloudOS Native] Rebuild necessario: %REBUILD_REASON%.
tasklist /FI "IMAGENAME eq CloudOS.exe" /NH 2>nul | findstr /I /C:"CloudOS.exe" >nul
if not errorlevel 1 (
  echo [CloudOS Native] Salve seu trabalho e encerre a instancia aberta normalmente antes do build.
  exit /b 24
)
echo [CloudOS Native] Validando, compilando e assinando o manifesto Release x64...
call "%ROOT%\scripts\native\build-cloudos-native.cmd" Release
if errorlevel 1 exit /b %ERRORLEVEL%

pwsh.exe -NoLogo -NoProfile -File "%VERIFY_SCRIPT%" -Root "%ROOT%" -Configuration Release -CheckSourceFingerprint
if errorlevel 1 exit /b %ERRORLEVEL%

:RUN
if not exist "%EXE%" exit /b 5
if not exist "%DLL%" exit /b 6
if not exist "%SUPERVISOR%" exit /b 7
if not exist "%MANIFEST%" exit /b 23

tasklist /FI "IMAGENAME eq CloudOS.exe" /NH 2>nul | findstr /I /C:"CloudOS.exe" >nul
if not errorlevel 1 (
  echo [CloudOS Native] Salve seu trabalho e encerre a instancia aberta normalmente antes de iniciar outra versao.
  exit /b 24
)

set "SOURCE_FINGERPRINT="
if exist "%FINGERPRINT_STAMP%" set /p SOURCE_FINGERPRINT=<"%FINGERPRINT_STAMP%"
set "BUILT_HEAD="
if exist "%HEAD_STAMP%" set /p BUILT_HEAD=<"%HEAD_STAMP%"

echo [CloudOS Native] Iniciando Shell Supervisor V11 verificado.
echo [CloudOS Native] O supervisor inicia CloudOS.exe --supervised, valida readiness/heartbeat e limita restart loops.
echo [CloudOS Native] SUPERVISOR=%SUPERVISOR%
echo [CloudOS Native] EXE=%EXE%
echo [CloudOS Native] MANIFEST=%MANIFEST%
if defined SOURCE_FINGERPRINT echo [CloudOS Native] SOURCE_FINGERPRINT=%SOURCE_FINGERPRINT%
if defined BUILT_HEAD echo [CloudOS Native] BUILD_HEAD=%BUILT_HEAD%
echo [CloudOS Native] Integridade SHA256 verificada antes da execucao.

pushd "%OUT%" >nul
start "CloudOS Supervisor V11" /D "%OUT%" "%SUPERVISOR%"
set "RC=%ERRORLEVEL%"
popd >nul
exit /b %RC%
