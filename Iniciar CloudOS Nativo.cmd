@echo off
setlocal
call "%~dp0scripts\native\start-cloudos-native.cmd"
exit /b %ERRORLEVEL%
