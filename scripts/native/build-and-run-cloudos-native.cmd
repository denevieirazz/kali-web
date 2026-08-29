@echo off
setlocal EnableExtensions

set "ROOT=%~dp0..\.."
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
set "CONFIG=Release"
set "PLATFORM=x64"

if /I "%~1"=="Debug" set "CONFIG=Debug"

if not exist "%VSWHERE%" (
  echo [CloudOS Native] Visual Studio Installer/vswhere nao encontrado.
  echo Instale Visual Studio 2022 Build Tools com Desktop development with C++ e Windows SDK.
  exit /b 2
)

set "VSROOT="
for /f "usebackq tokens=*" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.Component.MSBuild -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%I"

if not defined VSROOT (
  echo [CloudOS Native] Toolchain C++ x64 do Visual Studio nao encontrado.
  exit /b 3
)

set "MSBUILD=%VSROOT%\MSBuild\Current\Bin\MSBuild.exe"
if not exist "%MSBUILD%" (
  echo [CloudOS Native] MSBuild nao encontrado em "%MSBUILD%".
  exit /b 4
)

echo [CloudOS Native] Building C++ runtime...
"%MSBUILD%" "%ROOT%\desktop\CloudOS.NativeRuntime\CloudOS.NativeRuntime.vcxproj" /m /nologo /v:minimal /p:Configuration=%CONFIG% /p:Platform=%PLATFORM%
if errorlevel 1 exit /b %errorlevel%

echo [CloudOS Native] Building native shell...
"%MSBUILD%" "%ROOT%\desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj" /m /nologo /v:minimal /p:Configuration=%CONFIG% /p:Platform=%PLATFORM%
if errorlevel 1 exit /b %errorlevel%

set "SHELL=%ROOT%\desktop\CloudOS.NativeShell\bin\%CONFIG%\CloudOS.NativeShell.exe"
if not exist "%SHELL%" (
  echo [CloudOS Native] Build terminou sem produzir "%SHELL%".
  exit /b 5
)

echo [CloudOS Native] WEB_RUNTIME=OFF
start "CloudOS Native" "%SHELL%"
exit /b 0
