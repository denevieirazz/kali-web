@echo off
setlocal EnableExtensions
set "ROOT=%~dp0..\.."
for %%I in ("%ROOT%") do set "ROOT=%%~fI"

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq tokens=*" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.Component.MSBuild -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%I"

if not defined VSROOT (
  echo VSROOT not found
  exit /b 1
)

call "%VSROOT%\VC\Auxiliary\Build\vcvars64.bat"
if errorlevel 1 exit /b 1

cd /d "%~dp0"
cl.exe /std:c++17 /EHsc /O2 /W3 test_notepad_physical_containment.cpp /Fe:test_notepad_physical_containment.exe /link user32.lib kernel32.lib
if errorlevel 1 exit /b 1

echo [RUNNING PHYSICAL TEST]
test_notepad_physical_containment.exe
exit /b %ERRORLEVEL%
