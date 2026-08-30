@echo off
setlocal EnableExtensions

set "ROOT=%~dp0..\.."
for %%I in ("%ROOT%") do set "ROOT=%%~fI"
set "OUT=%ROOT%\desktop\CloudOS.NativeShell\bin\Release"
set "EXE=%OUT%\CloudOS.exe"
set "DLL=%OUT%\CloudOS.NativeRuntime.dll"
set "STAMP=%OUT%\.cloudos-build-head"
set "REBUILD_REASON="

if not exist "%EXE%" (
  set "REBUILD_REASON=CloudOS.exe ausente"
  goto BUILD
)
if not exist "%DLL%" (
  set "REBUILD_REASON=CloudOS.NativeRuntime.dll ausente"
  goto BUILD
)

rem Nao abra um binario de um commit antigo depois de git pull/reset.
where git.exe >nul 2>nul
if errorlevel 1 goto RUN

set "CURRENT_HEAD="
for /f "usebackq tokens=*" %%H in (`git.exe -C "%ROOT%" rev-parse HEAD 2^>nul`) do set "CURRENT_HEAD=%%H"
if not defined CURRENT_HEAD goto RUN

if not exist "%STAMP%" (
  set "REBUILD_REASON=stamp da revisao compilada ausente"
  goto BUILD
)

set "BUILT_HEAD="
set /p BUILT_HEAD=<"%STAMP%"
if not defined BUILT_HEAD (
  set "REBUILD_REASON=stamp da revisao compilada vazio"
  goto BUILD
)
if /I not "%CURRENT_HEAD%"=="%BUILT_HEAD%" (
  set "REBUILD_REASON=o codigo Git mudou desde o ultimo build"
  goto BUILD
)

rem Alteracoes locais nos arquivos que realmente formam o shell tambem invalidam o build.
set "NATIVE_DIRTY="
for /f "usebackq delims=" %%S in (`git.exe -C "%ROOT%" status --porcelain -- desktop/CloudOS.NativeRuntime desktop/CloudOS.NativeShell scripts/native 2^>nul`) do set "NATIVE_DIRTY=1"
if defined NATIVE_DIRTY (
  set "REBUILD_REASON=existem alteracoes locais no codigo nativo/scripts"
  goto BUILD
)

goto RUN

:BUILD
if defined REBUILD_REASON echo [CloudOS Native] Rebuild necessario: %REBUILD_REASON%.
rem O linker precisa conseguir substituir CloudOS.exe. Mate a instancia antiga antes do build.
taskkill /F /IM CloudOS.exe >nul 2>&1
timeout /t 1 /nobreak >nul 2>&1
echo [CloudOS Native] Validando e compilando Release x64...
call "%ROOT%\scripts\native\build-cloudos-native.cmd" Release
if errorlevel 1 exit /b %ERRORLEVEL%

:RUN
if not exist "%EXE%" (
  echo [CloudOS Native] ERRO: CloudOS.exe nao encontrado em "%EXE%".
  exit /b 5
)
if not exist "%DLL%" (
  echo [CloudOS Native] ERRO: CloudOS.NativeRuntime.dll nao encontrado em "%DLL%".
  exit /b 6
)

taskkill /F /IM CloudOS.exe >nul 2>&1
timeout /t 1 /nobreak >nul 2>&1

echo [CloudOS Native] Iniciando shell C++/Win32 nativo.
echo [CloudOS Native] Tiling inicia DESATIVADO e so muda por acao explicita do usuario.
echo [CloudOS Native] EXE=%EXE%
if exist "%STAMP%" (
  set "BUILT_HEAD="
  set /p BUILT_HEAD=<"%STAMP%"
  if defined BUILT_HEAD echo [CloudOS Native] BUILD_HEAD=%BUILT_HEAD%
)
echo [CloudOS Native] Shell iniciado.

pushd "%OUT%" >nul
start "" /D "%OUT%" "%EXE%"
set "RC=%ERRORLEVEL%"
popd >nul
exit /b %RC%
