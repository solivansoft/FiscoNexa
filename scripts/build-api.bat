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

dcc64 -B -DRELEASE -$D- -$L- -$Y- -O+ -E"%ROOT%\bin\win64" -N0"%ROOT%\build\win64\dcu" -NS"System;Xml;Data;Datasnap;Web;Soap;Winapi;Vcl" -U"%ROOT%\src\api";"%ROOT%\src\application";"%ROOT%\src\db";"%ROOT%\src\integrations";"%ROOT%\src\operations";"%ROOT%\src\persistence";"%ROOT%\src\persistence\schema";"%ROOT%\vendor\horse\src" "%ROOT%\apps\api\FiscoNexa.Api.dpr"
if errorlevel 1 exit /b 1

rem FireDAC PostgreSQL requer libpq e suas dependencias nativas.
copy /Y "%ROOT%\vendor\postgres-client\pgsql\bin\*.dll" "%ROOT%\bin\win64\" >nul
if errorlevel 1 exit /b 1
copy /Y "%ROOT%\vendor\postgres-client\pgsql\bin\libcrypto-3-x64.dll" "%ROOT%\bin\win64\" >nul
if errorlevel 1 exit /b 1
exit /b 0

:linux64
set "ROOT=%~dp0.."
if not exist "%ROOT%\vendor\horse\src\Horse.pas" (
  echo ERRO: dependencias ausentes. Execute scripts\dependencies.bat linux64.
  exit /b 1
)
set "RAD_ROOT=%FISCONEXA_RAD_ROOT%"
if "%RAD_ROOT%"=="" set "RAD_ROOT=C:\Program Files (x86)\Embarcadero\Studio\23.0"
if not exist "%RAD_ROOT%\bin\dcclinux64.exe" (
  echo ERRO: compilador Delphi Linux64 ausente em "%RAD_ROOT%\bin".
  exit /b 1
)
set "MSBUILD=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe"
if not exist "%MSBUILD%" (
  echo ERRO: MSBuild .NET Framework x64 nao encontrado.
  exit /b 1
)
if not exist "%ROOT%\bin\linux64" mkdir "%ROOT%\bin\linux64"
if not exist "%ROOT%\build\linux64\dcu" mkdir "%ROOT%\build\linux64\dcu"
if not exist "%ROOT%\build\linux64\obj" mkdir "%ROOT%\build\linux64\obj"
if not exist "%ROOT%\build\linux64\lib" mkdir "%ROOT%\build\linux64\lib"

rem O SDK importado preserva libcrypto.so.3, mas nao o symlink libcrypto.so.
rem Um linker script local resolve o SONAME sem copiar a biblioteca do SDK.
>"%ROOT%\build\linux64\lib\libcrypto.so" echo INPUT ^( libcrypto.so.3 ^)

call "%RAD_ROOT%\bin\rsvars.bat"
if errorlevel 1 exit /b 1

set "DCC_UnitSearchPath=%ROOT%\src\api;%ROOT%\src\application;%ROOT%\src\db;%ROOT%\src\integrations;%ROOT%\src\operations;%ROOT%\src\persistence;%ROOT%\src\persistence\schema;%ROOT%\vendor\horse\src;%ROOT%\build\linux64\lib"
set "DCC_DcuOutput=%ROOT%\build\linux64\dcu"
set "DCC_ObjOutput=%ROOT%\build\linux64\obj"
set "DCC_ExeOutput=%ROOT%\bin\linux64"

"%MSBUILD%" "%ROOT%\apps\api\FiscoNexa.Api.dproj" /t:Build /p:Config=Release /p:Platform=Linux64 /v:minimal
exit /b %errorlevel%
