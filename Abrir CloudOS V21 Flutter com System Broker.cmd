@echo off
setlocal
cd /d "%~dp0"
echo [CloudOS V21] Iniciando Flutter Shell + System Broker...

rem 1) Pacote extraido: executaveis ao lado deste launcher.
set "APP_DIR=%~dp0"

rem 2) Instalacao/preview fixa opcional.
if not exist "%APP_DIR%\cloudos_flutter_shell.exe" (
  set "APP_DIR=C:\CloudOS-Flutter-Preview-V21\app"
)

rem 3) Build local do repositorio.
if not exist "%APP_DIR%\cloudos_flutter_shell.exe" (
  set "APP_DIR=%~dp0desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release"
)

if not exist "%APP_DIR%\cloudos_flutter_shell.exe" (
  echo [CloudOS V21] cloudos_flutter_shell.exe nao encontrado.
  echo Use o artifact da CI ou execute "Abrir CloudOS Flutter Preview.cmd" no repositorio.
  pause
  exit /b 1
)

if not exist "%APP_DIR%\CloudOS.SystemBroker.exe" (
  echo [CloudOS V21] CloudOS.SystemBroker.exe nao encontrado em:
  echo %APP_DIR%
  pause
  exit /b 2
)

rem O Native Bridge V21 inicia o broker em background quando necessario.
start "" /D "%APP_DIR%" "%APP_DIR%\cloudos_flutter_shell.exe"
exit /b 0
