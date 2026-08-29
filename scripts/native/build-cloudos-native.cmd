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

where node.exe >nul 2>nul
if errorlevel 1 (
  echo [CloudOS] Node.js nao encontrado. Ele e necessario apenas para COMPILAR os assets da interface web.
  exit /b 7
)
where npm.cmd >nul 2>nul
if errorlevel 1 (
  echo [CloudOS] npm nao encontrado. Ele e necessario apenas para COMPILAR os assets da interface web.
  exit /b 8
)

if not exist "%ROOT%\frontend\node_modules\.bin\vite.cmd" (
  echo [CloudOS] Restaurando dependencias declaradas de build da interface...
  call npm.cmd install --prefix "%ROOT%\frontend" --no-audit --no-fund
  if errorlevel 1 exit /b %ERRORLEVEL%
)

echo [CloudOS] Compilando interface React/TypeScript em assets estaticos...
call npm.cmd run build --prefix "%ROOT%\frontend"
if errorlevel 1 exit /b %ERRORLEVEL%
if not exist "%ROOT%\frontend\dist\index.html" (
  echo [CloudOS] ERRO: frontend\dist\index.html nao foi produzido.
  exit /b 9
)

echo [CloudOS] Restaurando SDK nativo Microsoft.Web.WebView2...
"%MSBUILD%" "%ROOT%\desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj" /t:Restore /nologo /v:minimal /p:RestorePackagesConfig=true /p:RestoreProjectStyle=PackagesConfig /p:RestoreRepositoryPath="%ROOT%\desktop\CloudOS.NativeShell\packages"
if errorlevel 1 exit /b %ERRORLEVEL%

echo [CloudOS] Compilando runtime C++ %CONFIG% x64...
"%MSBUILD%" "%ROOT%\desktop\CloudOS.NativeRuntime\CloudOS.NativeRuntime.vcxproj" /m /nologo /v:minimal /p:Configuration=%CONFIG% /p:Platform=%PLATFORM%
if errorlevel 1 exit /b %ERRORLEVEL%

echo [CloudOS] Compilando shell C++ %CONFIG% x64...
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
if not exist "%OUT%\ui\index.html" (
  echo [CloudOS] ERRO: assets da interface nao foram copiados para "%OUT%\ui".
  exit /b 10
)

echo [CloudOS] BUILD_OK=%OUT%\CloudOS.exe
echo [CloudOS] WEB_UI=%OUT%\ui\index.html
echo [CloudOS] WEB_RUNTIME=WebView2 somente para apresentacao; autoridade=C++/Win32
exit /b 0
