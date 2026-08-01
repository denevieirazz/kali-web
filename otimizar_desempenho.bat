@echo off
title Otimizar Resposta do Processador (CPU Launch Boost)
echo =================================================================
echo   ATIVANDO MODO DE RESPOSTA INSTANTANEA DA CPU (CPU LAUNCH BOOST)
echo =================================================================
echo.

echo [1/4] Ativando Plano de Energia Desempenho Maximo (Ultimate Performance)...
powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 >nul 2>&1
powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61 >nul 2>&1
powercfg /setactive 8c5e7cd5-5ee3-4679-b144-00109f060670 >nul 2>&1

echo [2/4] Alocando 100%% do Processador para Acoes do Usuario (SystemResponsiveness = 0)...
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "SystemResponsiveness" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "NetworkThrottlingIndex" /t REG_DWORD /d 4294967295 /f >nul 2>&1

echo [3/4] Desativando Core Parking (Todos os Nucleos Prontos a 100%%)...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533751-8270-4526-9783-61327a75b480\0cc5b647-c1df-4596-8587-5d3680349453" /v "Attributes" /t REG_DWORD /d 0 /f >nul 2>&1

echo [4/4] Ativando Turbo Boost Agressivo de Frequencia no Clique...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533751-8270-4526-9783-61327a75b480\ea062031-6134-4941-7750-2c60715f86d6" /v "Attributes" /t REG_DWORD /d 0 /f >nul 2>&1

echo.
echo =================================================================
echo SUCESSO! O modo CPU Launch Boost foi configurado.
echo Agora a CPU disparara 100%% da frequencia instantaneamente
echo ao abrir arquivos, pastas ou softwares!
echo =================================================================
echo.
pause
