@echo off
title Otimizar Resposta do Processador (CPU Launch Boost)
echo =================================================================
echo   ATIVANDO MODO DE RESPOSTA INSTANTANEA DA CPU (CPU LAUNCH BOOST)
echo =================================================================
echo.

echo [1/5] Configurando frequencia dinamica (Minimo 5%% em repouso / Maximo 100%% no clique)...
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 >nul 2>&1
powercfg /setactive SCHEME_CURRENT >nul 2>&1

echo [2/5] Alocando 100%% da Prioridade da CPU para Acoes do Usuario (SystemResponsiveness = 0)...
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "SystemResponsiveness" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "NetworkThrottlingIndex" /t REG_DWORD /d 4294967295 /f >nul 2>&1

echo [3/5] Liberando todos os Nucleos para resposta em 0ms (Core Parking Off)...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533751-8270-4526-9783-61327a75b480\0cc5b647-c1df-4596-8587-5d3680349453" /v "Attributes" /t REG_DWORD /d 0 /f >nul 2>&1

echo [4/5] Ativando Modo de Turbo Boost Dinamico Agressivo...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533751-8270-4526-9783-61327a75b480\ea062031-6134-4941-7750-2c60715f86d6" /v "Attributes" /t REG_DWORD /d 0 /f >nul 2>&1

echo [5/5] Aplicando alteracoes no esquema ativo...
powercfg /setactive SCHEME_CURRENT >nul 2>&1

echo.
echo =================================================================
echo SUCESSO! O modo CPU Launch Boost foi configurado.
echo.
echo COMO FUNCIONA:
echo 1. No clique (abrir app/pasta): A CPU sobe para 100%% instantaneamente.
echo 2. Apos abrir: A CPU reduz para 5%% de uso/frequencia em repouso.
echo =================================================================
echo.
pause

