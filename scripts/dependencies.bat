@echo off
setlocal EnableExtensions

set "PLATFORM=%~1"
if "%PLATFORM%"=="" set "PLATFORM=win64"

if /I not "%PLATFORM%"=="win64" if /I not "%PLATFORM%"=="linux64" (
  echo ERRO: plataforma invalida: %PLATFORM%
  echo Uso: scripts\dependencies.bat ^<win64^|linux64^>
  exit /b 2
)

set "ROOT=%~dp0.."
call "%ROOT%\scripts\bootstrap-vendors.bat"
if errorlevel 1 exit /b 1

if /I "%PLATFORM%"=="win64" (
  call "%ROOT%\scripts\bootstrap-postgres-client.bat"
  if errorlevel 1 exit /b 1
)

echo Dependencias para %PLATFORM% prontas.
