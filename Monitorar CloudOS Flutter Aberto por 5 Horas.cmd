@echo off
setlocal EnableExtensions
title CloudOS Flutter V23 - Monitorar Sessao Aberta por 5 Horas

set "REPO_ROOT=%~dp0"
if "%REPO_ROOT:~-1%"=="\" set "REPO_ROOT=%REPO_ROOT:~0,-1%"
set "SOAK=%REPO_ROOT%\scripts\flutter\run-cloudos-flutter-soak-v23.ps1"
set "FLUTTER_EXE=%REPO_ROOT%\desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release\cloudos_flutter_shell.exe"

if not exist "%SOAK%" (
    echo [ERRO] Harness de soak nao encontrado: %SOAK%
    pause
    exit /b 2
)

if not exist "%FLUTTER_EXE%" (
    echo [ERRO] Release Flutter nao encontrado.
    echo Rode primeiro "Preparar e Testar CloudOS Flutter 5 Horas.cmd".
    pause
    exit /b 3
)

tasklist /FI "IMAGENAME eq cloudos_flutter_shell.exe" 2>nul | find /I "cloudos_flutter_shell.exe" >nul
if errorlevel 1 (
    echo [ERRO] cloudos_flutter_shell.exe nao esta aberto.
    echo Abra o CloudOS ou use o preparador de 5 horas.
    pause
    exit /b 4
)

echo Anexando o monitor a uma sessao CloudOS ja aberta.
echo O harness NAO encerrara essa sessao ao terminar.
echo.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%SOAK%" -AttachExisting -DurationMinutes 300 -SampleIntervalSeconds 60 -ExecutablePath "%FLUTTER_EXE%"
set "RESULT=%ERRORLEVEL%"
echo.
echo Evidencias: %REPO_ROOT%\TestResults\v23-flutter-soak
pause
exit /b %RESULT%
