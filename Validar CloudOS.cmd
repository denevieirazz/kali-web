@echo off
setlocal
call "%~dp0scripts\native\validate-cloudos-native.cmd"
exit /b %ERRORLEVEL%
