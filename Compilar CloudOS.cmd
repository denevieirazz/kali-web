@echo off
setlocal
call "%~dp0scripts\native\build-cloudos-native.cmd" %*
exit /b %ERRORLEVEL%
