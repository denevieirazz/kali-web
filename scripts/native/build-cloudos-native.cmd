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

echo [CloudOS] BUILD_OK=%OUT%\CloudOS.exe
exit /b 0
