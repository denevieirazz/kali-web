@echo off
title Corrigir Desligamento do Windows
echo ==========================================================
echo      APLICANDO CORRECAO DE DESLIGAMENTO DO WINDOWS
echo ==========================================================
echo.
echo [1/2] Desativando Inicializacao Rapida (Fast Startup)...
powercfg /h off
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v "HiberbootEnabled" /t REG_DWORD /d 0 /f >nul 2>&1

echo.
echo [2/2] Desativando Reinicio Automatico em caso de falha...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl" /v "AutoReboot" /t REG_DWORD /d 0 /f >nul 2>&1

echo.
echo ==========================================================
echo SUCEESSO! As configuracoes foram aplicadas com sucesso.
echo O Windows agora vai DESLIGAR normalmente sem reiniciar!
echo ==========================================================
echo.
pause
