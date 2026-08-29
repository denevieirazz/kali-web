@echo off
setlocal EnableExtensions
call "%~dp0scripts\native\start-cloudos-native.cmd"
exit /b %ERRORLEVEL%
