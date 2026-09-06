@echo off
setlocal
set "QA_VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq tokens=*" %%I in (`"%QA_VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "QA_VSROOT=%%I"
if not defined QA_VSROOT exit /b 2
call "%QA_VSROOT%\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 2
set "QA_OUT=%~dp0..\..\.cloudos-runtime\qa-managed-win32"
if not exist "%QA_OUT%" mkdir "%QA_OUT%"
pushd "%QA_OUT%"
cl /nologo /EHsc /W4 /WX /std:c++17 /DUNICODE /D_UNICODE /Zi "%~dp0managed-win32-containment-v22-tests.cpp" /Fe:containment-tests.exe /link user32.lib
if errorlevel 1 (popd & exit /b 1)
containment-tests.exe %*
set "QA_RESULT=%ERRORLEVEL%"
popd
exit /b %QA_RESULT%
