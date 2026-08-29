@echo off
setlocal EnableExtensions

set "ROOT=%~dp0..\.."
call "%~dp0build-cloudos-native.cmd" %*
if errorlevel 1 exit /b %ERRORLEVEL%

set "CONFIG=Release"
if /I "%~1"=="Debug" set "CONFIG=Debug"
set "SHELL=%ROOT%\desktop\CloudOS.NativeShell\bin\%CONFIG%\CloudOS.exe"

echo [CloudOS] NATIVE_RUNTIME=ON
echo [CloudOS] WEB_RUNTIME=OFF
start "CloudOS" /D "%ROOT%\desktop\CloudOS.NativeShell\bin\%CONFIG%" "%SHELL%"
exit /b 0
