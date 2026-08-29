@echo off
title Instalacao do Visual Studio Build Tools para CloudOS
echo ================================================================
echo Instalando Visual Studio 2022 Build Tools (C++ Workload + WinSDK)
echo ================================================================
echo Certifique-se de estar executando este arquivo como Administrador!
echo.
winget install --id Microsoft.VisualStudio.2022.BuildTools --override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" --accept-source-agreements --accept-package-agreements
echo.
echo Concluido! Pressione qualquer tecla para sair.
pause
