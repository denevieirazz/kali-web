@echo off
setlocal EnableExtensions
cd /d "%~dp0"
where pwsh.exe >nul 2>&1 || (
  echo ERRO: PowerShell 7 ^(pwsh.exe^) e obrigatorio.
  exit /b 1
)
if not exist "%~dp0scripts\productization\validate-distribution-unified.ps1" (
  echo ERRO: validador de distribuicao nao encontrado.
  exit /b 2
)
echo CloudOS Productization Batch 2.5 - gate fisico interativo
echo Este comando nao publica, promove ou altera a branch.
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\productization\validate-distribution-unified.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" echo Validacao fisica encerrada com erro ^(%EXIT_CODE%^). Consulte validation.json na pasta aberta pelo validador.
exit /b %EXIT_CODE%
