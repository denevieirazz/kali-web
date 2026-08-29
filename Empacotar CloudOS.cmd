@echo off
setlocal
call "%~dp0scripts\native\package-cloudos-native.cmd"
exit /b %ERRORLEVEL%
