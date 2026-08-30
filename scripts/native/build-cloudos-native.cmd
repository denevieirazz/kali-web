@echo off
setlocal EnableExtensions

set "ROOT=%~dp0..\.."
for %%I in ("%ROOT%") do set "ROOT=%%~fI"
set "CONFIG=Release"
set "PLATFORM=x64"
if /I "%~1"=="Debug" set "CONFIG=Debug"

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
  echo [CloudOS] Visual Studio Installer/vswhere nao encontrado.
  echo [CloudOS] Instale Visual Studio 2022 Build Tools com Desktop development with C++ e Windows SDK.
  exit /b 2
)

set "VSROOT="
for /f "usebackq tokens=*" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.Component.MSBuild -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%I"
if not defined VSROOT (
  echo [CloudOS] Toolchain MSVC x64 nao encontrado.
  exit /b 3
)

set "MSBUILD=%VSROOT%\MSBuild\Current\Bin\MSBuild.exe"
if not exist "%MSBUILD%" (
  echo [CloudOS] MSBuild nao encontrado: "%MSBUILD%"
  exit /b 4
)

rem O frontend React antigo e somente referencia visual. O Shell compilado e C++/Win32.
rem WebView2 continua sendo restaurado exclusivamente para o Navegador nativo in-process.
echo [CloudOS] Validando contratos do shell nativo...
pwsh.exe -NoLogo -NoProfile -File "%ROOT%\scripts\native\test-cloudos-native-shell-contracts.ps1"
if errorlevel 1 exit /b %ERRORLEVEL%
pwsh.exe -NoLogo -NoProfile -File "%ROOT%\scripts\native\test-native-web-ui-contract.ps1"
if errorlevel 1 exit /b %ERRORLEVEL%
pwsh.exe -NoLogo -NoProfile -File "%ROOT%\scripts\native\test-taskbar-productivity-contract.ps1"
if errorlevel 1 exit /b %ERRORLEVEL%
pwsh.exe -NoLogo -NoProfile -File "%ROOT%\scripts\native\test-native-release-pipeline-contract.ps1"
if errorlevel 1 exit /b %ERRORLEVEL%

set "WEBVIEW_TARGET=%ROOT%\desktop\CloudOS.NativeShell\packages\Microsoft.Web.WebView2.1.0.4078.44\build\native\Microsoft.Web.WebView2.targets"
if exist "%WEBVIEW_TARGET%" (
  echo [CloudOS] SDK Microsoft.Web.WebView2 ja restaurado; reutilizando cache local.
) else (
  echo [CloudOS] Restaurando SDK Microsoft.Web.WebView2 somente para o Navegador...
  "%MSBUILD%" "%ROOT%\desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj" /t:Restore /nologo /v:minimal /p:RestorePackagesConfig=true /p:RestoreProjectStyle=PackagesConfig /p:RestoreRepositoryPath="%ROOT%\desktop\CloudOS.NativeShell\packages"
  if errorlevel 1 exit /b %ERRORLEVEL%
)

echo [CloudOS] Compilando runtime C++ %CONFIG% x64...
"%MSBUILD%" "%ROOT%\desktop\CloudOS.NativeRuntime\CloudOS.NativeRuntime.vcxproj" /m /nologo /v:minimal /p:Configuration=%CONFIG% /p:Platform=%PLATFORM%
if errorlevel 1 exit /b %ERRORLEVEL%

echo [CloudOS] Compilando shell C++/Win32 %CONFIG% x64...
"%MSBUILD%" "%ROOT%\desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj" /m /nologo /v:minimal /p:Configuration=%CONFIG% /p:Platform=%PLATFORM%
if errorlevel 1 exit /b %ERRORLEVEL%

set "OUT=%ROOT%\desktop\CloudOS.NativeShell\bin\%CONFIG%"
set "MANIFEST=%OUT%\cloudos-native-manifest.json"
set "FINGERPRINT_STAMP=%OUT%\.cloudos-build-fingerprint"
if not exist "%OUT%\CloudOS.exe" (
  echo [CloudOS] ERRO: CloudOS.exe nao foi produzido.
  exit /b 5
)
if not exist "%OUT%\CloudOS.NativeRuntime.dll" (
  echo [CloudOS] ERRO: CloudOS.NativeRuntime.dll nao foi copiado para a saida.
  exit /b 6
)

for %%F in ("%OUT%\CloudOS.exe") do set "EXE_SIZE=%%~zF"
for %%F in ("%OUT%\CloudOS.NativeRuntime.dll") do set "RUNTIME_SIZE=%%~zF"
if "%EXE_SIZE%"=="0" (
  echo [CloudOS] ERRO: CloudOS.exe vazio.
  exit /b 11
)
if "%RUNTIME_SIZE%"=="0" (
  echo [CloudOS] ERRO: CloudOS.NativeRuntime.dll vazio.
  exit /b 12
)

rem Releases antigos podiam deixar bin\Release\ui com o desktop React. Como o shell
rem atual e nativo, remova essa sobra para ela nao parecer um fallback valido.
if exist "%OUT%\ui" (
  echo [CloudOS] Removendo assets obsoletos do antigo desktop web da saida nativa...
  rmdir /s /q "%OUT%\ui" >nul 2>&1
)

rem Gera proveniencia reproduzivel: commit quando disponivel, fingerprint deterministico
rem das fontes e SHA256/tamanho dos dois binarios autoritativos.
echo [CloudOS] Gerando manifesto de proveniencia e integridade...
pwsh.exe -NoLogo -NoProfile -File "%ROOT%\scripts\native\write-native-build-manifest.ps1" -Root "%ROOT%" -Configuration "%CONFIG%"
if errorlevel 1 exit /b %ERRORLEVEL%

if not exist "%MANIFEST%" (
  echo [CloudOS] ERRO: manifesto nativo nao foi produzido.
  exit /b 13
)
if not exist "%FINGERPRINT_STAMP%" (
  echo [CloudOS] ERRO: fingerprint da fonte nao foi produzido.
  exit /b 14
)

echo [CloudOS] Verificando hashes e proveniencia do build...
pwsh.exe -NoLogo -NoProfile -File "%ROOT%\scripts\native\verify-native-build-manifest.ps1" -Root "%ROOT%" -Configuration "%CONFIG%" -CheckSourceFingerprint
if errorlevel 1 exit /b %ERRORLEVEL%

set "SOURCE_FINGERPRINT="
set /p SOURCE_FINGERPRINT=<"%FINGERPRINT_STAMP%"
set "BUILD_HEAD="
if exist "%OUT%\.cloudos-build-head" set /p BUILD_HEAD=<"%OUT%\.cloudos-build-head"

echo.
echo [CloudOS] BUILD_OK=%OUT%\CloudOS.exe
echo [CloudOS] RUNTIME=%OUT%\CloudOS.NativeRuntime.dll
echo [CloudOS] MANIFEST=%MANIFEST%
if defined SOURCE_FINGERPRINT echo [CloudOS] SOURCE_FINGERPRINT=%SOURCE_FINGERPRINT%
if defined BUILD_HEAD echo [CloudOS] BUILD_HEAD=%BUILD_HEAD%
echo [CloudOS] SHELL_UI=C++/Win32 nativo
echo [CloudOS] WEBVIEW2=usado somente pelo Navegador CloudOS
echo [CloudOS] FRONTEND_REACT=referencia visual; nao participa deste build
exit /b 0
