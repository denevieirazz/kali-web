@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "PACKAGED_ROOT=C:\CloudOS-Flutter-Preview-V21\app"
set "LOCAL_FLUTTER=%~dp0desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release"
set "LOCAL_NATIVE=%~dp0desktop\CloudOS.NativeShell\bin\Release"
set "SCRIPT=%~dp0scripts\flutter\start-cloudos-v21-integrated.ps1"

if exist "%PACKAGED_ROOT%\cloudos-v21-integrated-manifest.json" (
  echo [CloudOS V21] Iniciando bundle integrado verificado...
  pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Root "%PACKAGED_ROOT%"
  set "RC=%ERRORLEVEL%"
  if not "%RC%"=="0" pause
  exit /b %RC%
)

if not exist "%LOCAL_FLUTTER%\cloudos_flutter_shell.exe" (
  echo [CloudOS V21] Flutter Release local nao encontrado: %LOCAL_FLUTTER%
  echo [CloudOS V21] Use o artifact integrado da CI ou compile o Flutter Windows Release.
  pause
  exit /b 1
)
if not exist "%LOCAL_NATIVE%\cloudos-native-manifest.json" (
  echo [CloudOS V21] Runtime nativo Release nao encontrado: %LOCAL_NATIVE%
  echo [CloudOS V21] Execute "Compilar CloudOS Nativo.cmd" antes do modo integrado local.
  pause
  exit /b 2
)

echo [CloudOS V21] Iniciando layout de desenvolvimento integrado...
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Root "%LOCAL_FLUTTER%" -NativeRoot "%LOCAL_NATIVE%" -AllowDevelopmentLayout
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" pause
exit /b %RC%
