@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT=%~dp0..\.."
call "%~dp0build-cloudos-native.cmd" Release
if errorlevel 1 exit /b %ERRORLEVEL%

set "OUT=%ROOT%\desktop\CloudOS.NativeShell\bin\Release"
if not exist "%OUT%\CloudOS.exe" exit /b 10
if not exist "%OUT%\CloudOS.NativeRuntime.dll" exit /b 11

for %%E in (.js .jsx .ts .tsx .mjs .cjs .html .css .cs .csproj .xaml) do (
  for /r "%ROOT%" %%F in (*%%E) do (
    echo [CloudOS] ERRO: fonte proibida na arvore nativa: %%F
    exit /b 12
  )
)

for %%D in (frontend backend) do (
  if exist "%ROOT%\%%D" (
    echo [CloudOS] ERRO: diretorio legado proibido: %%D
    exit /b 13
  )
)

findstr /i /c:"node " /c:"npm " /c:"vite" /c:"webview2" /c:"start-cloudos.ps1" "%ROOT%\Iniciar CloudOS.cmd" "%~dp0build-and-run-cloudos-native.cmd" >nul 2>&1
if not errorlevel 1 (
  echo [CloudOS] ERRO: launcher contem dependencia de runtime legado.
  exit /b 14
)

echo [CloudOS] VALIDATION_OK
echo [CloudOS] EXE=%OUT%\CloudOS.exe
echo [CloudOS] DLL=%OUT%\CloudOS.NativeRuntime.dll
exit /b 0
