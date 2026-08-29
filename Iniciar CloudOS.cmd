@echo off
setlocal
call "%~dp0scripts\native\build-and-run-cloudos-native.cmd" %*
exit /b %ERRORLEVEL%
