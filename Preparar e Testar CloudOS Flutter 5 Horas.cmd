@echo off
setlocal EnableExtensions
title CloudOS Flutter V23 - Preparar e Testar 5 Horas

set "REPO_ROOT=%~dp0"
if "%REPO_ROOT:~-1%"=="\" set "REPO_ROOT=%REPO_ROOT:~0,-1%"

set "FLUTTER_CMD=flutter"
where flutter >nul 2>&1
if errorlevel 1 (
    if exist "C:\src\flutter\bin\flutter.bat" (
        set "FLUTTER_CMD=C:\src\flutter\bin\flutter.bat"
    ) else (
        echo [ERRO] Flutter nao foi encontrado no PATH nem em C:\src\flutter\bin\flutter.bat.
        echo Instale/configure Flutter antes de continuar.
        pause
        exit /b 2
    )
)

set "FLUTTER_DIR=%REPO_ROOT%\desktop\CloudOS.FlutterShell"
set "NATIVE_BIN=%REPO_ROOT%\desktop\CloudOS.NativeShell\bin\Release"
set "BROKER_BIN=%NATIVE_BIN%\CloudOS.SystemBroker.exe"
set "PROBE_BIN=%NATIVE_BIN%\CloudOS.BrokerProbe.exe"
set "RELEASE_DIR=%FLUTTER_DIR%\build\windows\x64\runner\Release"
set "FLUTTER_EXE=%RELEASE_DIR%\cloudos_flutter_shell.exe"
set "SOAK=%REPO_ROOT%\scripts\flutter\run-cloudos-flutter-soak-v23.ps1"

if not exist "%SOAK%" (
    echo [ERRO] Harness de soak V23 nao encontrado: %SOAK%
    pause
    exit /b 3
)

echo ==============================================================
echo  CloudOS Flutter V23 - preparacao para sessao real de 5 horas
echo ==============================================================
echo.
echo [1/7] Validando/compilando camada nativa e System Broker...
call "%REPO_ROOT%\scripts\native\build-cloudos-native.cmd" Release
if errorlevel 1 (
    echo [ERRO] Build nativo falhou. O CloudOS nao sera iniciado com binario antigo.
    pause
    exit /b 10
)

if not exist "%BROKER_BIN%" (
    echo [ERRO] System Broker nao foi produzido: %BROKER_BIN%
    pause
    exit /b 11
)
if not exist "%PROBE_BIN%" (
    echo [ERRO] Broker Probe nao foi produzido: %PROBE_BIN%
    pause
    exit /b 12
)

echo [2/7] Executando self-test do System Broker...
"%BROKER_BIN%" --self-test
if errorlevel 1 (
    echo [ERRO] O System Broker falhou no self-test. Nao vou abrir uma sessao de 5h quebrada.
    pause
    exit /b 13
)

echo [3/7] Resolvendo dependencias Flutter...
pushd "%FLUTTER_DIR%"
call "%FLUTTER_CMD%" pub get
if errorlevel 1 (
    popd
    echo [ERRO] flutter pub get falhou.
    pause
    exit /b 20
)

echo [4/7] Compilando Flutter Windows Release atual...
call "%FLUTTER_CMD%" build windows --release
if errorlevel 1 (
    popd
    echo [ERRO] flutter build windows --release falhou.
    pause
    exit /b 21
)
popd

if not exist "%FLUTTER_EXE%" (
    echo [ERRO] Release Flutter nao encontrado depois do build: %FLUTTER_EXE%
    pause
    exit /b 22
)

echo [5/7] Sincronizando Broker/Probe exatos com o Release Flutter...
copy /Y "%BROKER_BIN%" "%RELEASE_DIR%\CloudOS.SystemBroker.exe" >nul
if errorlevel 1 (
    echo [ERRO] Nao foi possivel copiar CloudOS.SystemBroker.exe para o Release.
    pause
    exit /b 23
)
copy /Y "%PROBE_BIN%" "%RELEASE_DIR%\CloudOS.BrokerProbe.exe" >nul
if errorlevel 1 (
    echo [ERRO] Nao foi possivel copiar CloudOS.BrokerProbe.exe para o Release.
    pause
    exit /b 24
)

echo [6/7] Garantindo uma instancia do System Broker...
tasklist /FI "IMAGENAME eq CloudOS.SystemBroker.exe" 2>nul | find /I "CloudOS.SystemBroker.exe" >nul
if errorlevel 1 (
    start "CloudOS System Broker" /B "%RELEASE_DIR%\CloudOS.SystemBroker.exe"
    timeout /t 1 /nobreak >nul
) else (
    echo System Broker ja esta em execucao; o harness vai monitorar a instancia existente.
)

echo [7/7] Iniciando CloudOS + monitor de estabilidade por 300 minutos...
echo.
echo Pode usar Files, Terminal, Browser, Notepad, Projects, Drive, Settings,
echo Alt+Tab, workspaces e WSL normalmente durante o teste.
echo O console registra apenas telemetria estrutural; nao imprime conteudo dos seus arquivos.
echo Fechar o CloudOS manualmente antes das 5h sera registrado como falha do soak.
echo.

pwsh -NoProfile -ExecutionPolicy Bypass -File "%SOAK%" -DurationMinutes 300 -SampleIntervalSeconds 60 -ExecutablePath "%FLUTTER_EXE%"
set "SOAK_EXIT=%ERRORLEVEL%"

echo.
if "%SOAK_EXIT%"=="0" (
    echo [PASS] A sessao de 5 horas terminou sem gatilho de estabilidade.
) else if "%SOAK_EXIT%"=="2" (
    echo [INCOMPLETO] O soak terminou antes de completar as 5 horas.
) else (
    echo [FAIL] O harness detectou uma falha de estabilidade. Veja TestResults\v23-flutter-soak.
)
echo Evidencias: %REPO_ROOT%\TestResults\v23-flutter-soak
pause
exit /b %SOAK_EXIT%
