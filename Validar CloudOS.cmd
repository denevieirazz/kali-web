@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
set "PWSH="

for /f "usebackq delims=" %%P in (`powershell.exe -NoLogo -NoProfile -Command "$c=Get-Command pwsh.exe -ErrorAction SilentlyContinue; if($c -and $c.Source){$c.Source}"`) do (
  if not defined PWSH set "PWSH=%%P"
)

if defined PWSH if exist "%PWSH%" goto :run

set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if exist "%PWSH%" goto :run

set "PWSH="
if defined LOCALAPPDATA if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe" (
  set "PWSH=%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"
  goto :run
)

for /f "usebackq delims=" %%P in (`powershell.exe -NoLogo -NoProfile -Command "$paths=@(); if($env:ProgramFiles){$paths += Get-ChildItem -LiteralPath (Join-Path $env:ProgramFiles 'PowerShell') -Directory -ErrorAction SilentlyContinue ^| ForEach-Object { Join-Path $_.FullName 'pwsh.exe' }}; try {$paths += Get-AppxPackage -Name Microsoft.PowerShell -ErrorAction SilentlyContinue ^| ForEach-Object { if($_.InstallLocation){Join-Path $_.InstallLocation 'pwsh.exe'} }} catch {}; $paths ^| Where-Object { $_ -and (Test-Path -LiteralPath $_) } ^| Select-Object -First 1"`) do (
  if not defined PWSH set "PWSH=%%P"
)

if not defined PWSH goto :missing
if not exist "%PWSH%" goto :missing

:run
echo [CloudOS] PowerShell 7: "%PWSH%"
"%PWSH%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\validate\run-stabilization-batch1.ps1" %*
exit /b %ERRORLEVEL%

:missing
echo [CloudOS] PowerShell 7 nao encontrado.
echo [CloudOS] Verificado nesta ordem:
echo [CloudOS] 1. Get-Command pwsh.exe / PATH
echo [CloudOS] 2. "%ProgramFiles%\PowerShell\7\pwsh.exe"
echo [CloudOS] 3. WindowsApps, outras instalacoes em Program Files\PowerShell e pacote MSIX Microsoft.PowerShell
echo [CloudOS] Instale/registre o PowerShell 7 e tente novamente.
exit /b 1
