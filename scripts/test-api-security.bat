@echo off
setlocal EnableExtensions
python "%~dp0..\tests\test_api_contract.py"
if errorlevel 1 exit /b 1
call "%~dp0build-api.bat" win64
if errorlevel 1 exit /b 1
python "%~dp0..\tests\test_api_security_local.py"
exit /b %errorlevel%
