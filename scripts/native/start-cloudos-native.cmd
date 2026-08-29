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

echo [CloudOS Native] Iniciando shell C++/Win32 real.
echo [CloudOS Native] WEB_RUNTIME=OFF
echo [CloudOS Native] EXE=%EXE%
echo [CloudOS Native] AVISO: o modo Full legado usa CloudOS.Host/WebView2 e nao e este shell nativo.

pushd "%OUT%" >nul
start "CloudOS Native" /D "%OUT%" "%EXE%"
set "RC=%ERRORLEVEL%"
popd >nul
exit /b %RC%
