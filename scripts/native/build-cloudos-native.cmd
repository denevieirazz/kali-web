@echo off
setlocal EnableExtensions

set "ROOT=%~dp0..\.."
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

echo [CloudOS] Restaurando SDK Microsoft.Web.WebView2 somente para o Navegador...
"%MSBUILD%" "%ROOT%\desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj" /t:Restore /nologo /v:minimal /p:RestorePackagesConfig=true /p:RestoreProjectStyle=PackagesConfig /p:RestoreRepositoryPath="%ROOT%\desktop\CloudOS.NativeShell\packages"
if errorlevel 1 exit /b %ERRORLEVEL%

echo [CloudOS] Compilando runtime C++ %CONFIG% x64...
"%MSBUILD%" "%ROOT%\desktop\CloudOS.NativeRuntime\CloudOS.NativeRuntime.vcxproj" /m /nologo /v:minimal /p:Configuration=%CONFIG% /p:Platform=%PLATFORM%
if errorlevel 1 exit /b %ERRORLEVEL%

echo [CloudOS] Compilando shell C++/Win32 %CONFIG% x64...
"%MSBUILD%" "%ROOT%\desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj" /m /nologo /v:minimal /p:Configuration=%CONFIG% /p:Platform=%PLATFORM%
if errorlevel 1 exit /b %ERRORLEVEL%

set "OUT=%ROOT%\desktop\CloudOS.NativeShell\bin\%CONFIG%"
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

echo.
echo [CloudOS] BUILD_OK=%OUT%\CloudOS.exe
echo [CloudOS] RUNTIME=%OUT%\CloudOS.NativeRuntime.dll
echo [CloudOS] SHELL_UI=C++/Win32 nativo
echo [CloudOS] WEBVIEW2=usado somente pelo Navegador CloudOS
echo [CloudOS] FRONTEND_REACT=referencia visual; nao participa deste build
exit /b 0
