@echo off
setlocal EnableExtensions
cd /d "%~dp0"
where git.exe >nul 2>&1 || (echo [CloudOS] git.exe nao encontrado.& exit /b 30)
git fetch origin rewrite/cloudos-native-win32
if errorlevel 1 exit /b %ERRORLEVEL%
git merge --ff-only origin/rewrite/cloudos-native-win32
if errorlevel 1 exit /b %ERRORLEVEL%
call "%~dp0Compilar CloudOS.cmd"
exit /b %ERRORLEVEL%
