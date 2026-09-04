@echo off
setlocal
where pwsh.exe >nul 2>&1 || (echo ERRO: PowerShell 7 ^(pwsh.exe^) e obrigatorio.& pause & exit /b 1)
cd /d "%~dp0"
echo.
echo ========================================
echo   CloudOS - preparar e testar hoje
echo ========================================
echo.
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\productization\ready-to-test.ps1"
set "EXITCODE=%ERRORLEVEL%"
echo.
if not "%EXITCODE%"=="0" (
  echo ERRO: o preparo do CloudOS falhou com codigo %EXITCODE%.
  echo Revise a mensagem acima antes de tentar novamente.
  pause
)
exit /b %EXITCODE%
