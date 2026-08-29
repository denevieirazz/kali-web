@echo off
setlocal EnableExtensions

set "ROOT=%~dp0..\.."
for %%I in ("%ROOT%") do set "ROOT=%%~fI"
set "OUT=%ROOT%\desktop\CloudOS.NativeShell\bin\Release"
set "EXE=%OUT%\CloudOS.exe"
set "DLL=%OUT%\CloudOS.NativeRuntime.dll"

if not exist "%EXE%" goto BUILD
if not exist "%DLL%" goto BUILD
goto RUN

:BUILD
echo [CloudOS Native] Binarios Release x64 ausentes. Compilando...
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

echo [CloudOS Native] Iniciando shell C++ Win32 nativo.
echo [CloudOS Native] Tiling inicia DESATIVADO e so muda por acao explicita do usuario.
echo [CloudOS Native] EXE=%EXE%
echo [CloudOS Native] Shell iniciado com sucesso.

pushd "%OUT%" >nul
start "" /D "%OUT%" "%EXE%"
set "RC=%ERRORLEVEL%"
popd >nul
exit /b %RC%
