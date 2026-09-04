@echo off
setlocal EnableExtensions

set "PLATFORM=%~1"
if "%PLATFORM%"=="" set "PLATFORM=win64"

if /I "%PLATFORM%"=="win64" goto win64
if /I "%PLATFORM%"=="linux64" goto linux64

echo ERRO: plataforma invalida: %PLATFORM%
echo Uso: scripts\build-api.bat ^<win64^|linux64^>
exit /b 2

:win64
set "ROOT=%~dp0.."
if not exist "%ROOT%\vendor\horse\src\Horse.pas" (
  echo ERRO: dependencias ausentes. Execute scripts\dependencies.bat win64.
  exit /b 1
)
if not exist "%ROOT%\bin\win64" mkdir "%ROOT%\bin\win64"
if not exist "%ROOT%\build\win64\dcu" mkdir "%ROOT%\build\win64\dcu"

call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
if errorlevel 1 exit /b 1

dcc64 -B -DRELEASE -$D- -$L- -$Y- -O+ -E"%ROOT%\bin\win64" -N0"%ROOT%\build\win64\dcu" -NS"System;Xml;Data;Datasnap;Web;Soap;Winapi;Vcl" -U"%ROOT%\src\api";"%ROOT%\src\db";"%ROOT%\vendor\horse\src" "%ROOT%\apps\api\FiscoNexa.Api.dpr"
exit /b %errorlevel%

:linux64
set "ROOT=%~dp0.."
if not exist "%ROOT%\vendor\horse\src\Horse.pas" (
  echo ERRO: dependencias ausentes. Execute scripts\dependencies.bat linux64.
  exit /b 1
)
if not exist "G:\solivansoft\wmlc\build\wmlc.exe" (
  echo ERRO: WMLC nao encontrado em G:\solivansoft\wmlc\build\wmlc.exe.
  exit /b 1
)
if not exist "%ROOT%\bin\linux64" mkdir "%ROOT%\bin\linux64"
if not exist "%ROOT%\build\linux64" mkdir "%ROOT%\build\linux64"

"G:\solivansoft\wmlc\build\wmlc.exe" -E "%ROOT%\bin\linux64" --target linux64 --mode release -o FiscoNexa.Api "%ROOT%\apps\api\FiscoNexa.Api.dpr"
exit /b %errorlevel%
