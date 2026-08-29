@echo off
setlocal EnableExtensions

set "ROOT=%~dp0..\.."
call "%~dp0validate-cloudos-native.cmd"
if errorlevel 1 exit /b %ERRORLEVEL%

set "OUT=%ROOT%\desktop\CloudOS.NativeShell\bin\Release"
set "DIST=%ROOT%\dist\CloudOS-Native-x64"
set "ZIP=%ROOT%\dist\CloudOS-Native-x64.zip"

if exist "%DIST%" rmdir /s /q "%DIST%"
if exist "%ZIP%" del /q "%ZIP%"
mkdir "%DIST%" || exit /b 20

copy /y "%OUT%\CloudOS.exe" "%DIST%\CloudOS.exe" >nul || exit /b 21
copy /y "%OUT%\CloudOS.NativeRuntime.dll" "%DIST%\CloudOS.NativeRuntime.dll" >nul || exit /b 22
copy /y "%ROOT%\README.md" "%DIST%\README.md" >nul || exit /b 23
copy /y "%ROOT%\SECURITY.md" "%DIST%\SECURITY.md" >nul || exit /b 24

where tar.exe >nul 2>&1
if not errorlevel 1 (
  pushd "%ROOT%\dist"
  tar.exe -a -c -f "CloudOS-Native-x64.zip" "CloudOS-Native-x64"
  if errorlevel 1 (
    popd
    exit /b 26
  )
  popd
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Compress-Archive -LiteralPath '%DIST%' -DestinationPath '%ZIP%' -Force"
  if errorlevel 1 exit /b %ERRORLEVEL%
)

if not exist "%ZIP%" exit /b 25
echo [CloudOS] PACKAGE_OK=%ZIP%
exit /b 0
