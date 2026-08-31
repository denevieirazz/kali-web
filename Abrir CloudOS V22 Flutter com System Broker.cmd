@echo off
setlocal enabledelayedexpansion
title CloudOS V22 - Flutter Presentation + System Broker (Unified Files)

echo ========================================================
echo  CloudOS V22 - Flutter UI + Native System Broker
echo  Milestone: Unified Files ^& Open With Windows/Linux
echo ========================================================
echo.

set "REPO_ROOT=%~dp0"
if "%REPO_ROOT:~-1%"=="\" set "REPO_ROOT=%REPO_ROOT:~0,-1%"

set "BROKER_BIN=%REPO_ROOT%\desktop\CloudOS.NativeShell\bin\Release\CloudOS.SystemBroker.exe"
set "PROBE_BIN=%REPO_ROOT%\desktop\CloudOS.NativeShell\bin\Release\CloudOS.BrokerProbe.exe"
set "FLUTTER_APP=%REPO_ROOT%\desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release\cloudos_flutter_shell.exe"

if not exist "%BROKER_BIN%" (
    echo [1/3] Compilando binarios nativos do CloudOS System Broker V22...
    call "%REPO_ROOT%\scripts\native\build-cloudos-native.cmd" Release
    if errorlevel 1 (
        echo [ERRO] Falha ao compilar binarios nativos.
        pause
        exit /b 1
    )
)

echo [2/3] Executando auto-teste do System Broker V22...
"%BROKER_BIN%" --self-test
if errorlevel 1 (
    echo [ERRO] Auto-teste do System Broker falhou.
    pause
    exit /b 1
)

echo [3/3] Iniciando System Broker V22 em segundo plano...
start "" "%BROKER_BIN%"

timeout /t 1 /nobreak >nul

if exist "%FLUTTER_APP%" (
    echo Iniciando CloudOS Flutter Shell integrado...
    start "" "%FLUTTER_APP%"
) else (
    echo.
    echo System Broker V22 ativo e aguardando conexoes IPC.
    echo Para testar os comandos de arquivos via CLI:
    echo   "%PROBE_BIN%" list home
    echo   "%PROBE_BIN%" drives
    echo   "%PROBE_BIN%" known-folders
    echo   "%PROBE_BIN%" open-with "%REPO_ROOT%\README.md"
    echo.
)

echo Pronto.
