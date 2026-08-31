@echo off
setlocal
cd /d "%~dp0"
echo [CloudOS V21] Iniciando CloudOS System Broker e Flutter Shell...

set "APP_DIR=C:\CloudOS-Flutter-Preview-V21\app"
if not exist "%APP_DIR%\cloudos_flutter_shell.exe" (
  set "APP_DIR=%~dp0desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release"
)

if not exist "%APP_DIR%\cloudos_flutter_shell.exe" (
  echo [CloudOS V21] Executavel nao encontrado em %APP_DIR%.
  echo Execute o build local ou baixe o artifact da CI.
  pause
  exit /b 1
)

start "" "%APP_DIR%\CloudOS.SystemBroker.exe"
timeout /t 1 /nobreak >nul
start "" "%APP_DIR%\cloudos_flutter_shell.exe"
exit /b 0
