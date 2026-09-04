@echo off
setlocal EnableExtensions

set "ROOT=%~dp0.."
call "%ROOT%\scripts\load-dev-env.bat"
if errorlevel 1 exit /b 1

call "%ROOT%\scripts\dependencies.bat" win64
if errorlevel 1 exit /b 1

call "%ROOT%\scripts\build-api.bat" win64
if errorlevel 1 exit /b 1

set "FISCONEXA_DB_HOST=127.0.0.1"
set "FISCONEXA_DB_PORT=%POSTGRES_PORT%"
set "FISCONEXA_DB_NAME=%POSTGRES_DB%"
set "FISCONEXA_DB_USER=%POSTGRES_USER%"
set "FISCONEXA_DB_PASSWORD=%POSTGRES_PASSWORD%"
set "PATH=%ROOT%\vendor\postgres-client\pgsql\bin;%PATH%"
"%ROOT%\bin\win64\FiscoNexa.Api.exe"
