@echo off
setlocal EnableExtensions EnableDelayedExpansion

if /I not "%~1"=="win64" (
  echo Uso: build-worker.bat win64
  exit /b 2
)

set "ROOT=%~dp0.."
if "%FISCONEXA_ACBR_ROOT%"=="" (
  set "FISCONEXA_ACBR_ROOT=G:\Sources\Componentes\ACBr\trunk2"
)
if not exist "%FISCONEXA_ACBR_ROOT%\Fontes\ACBrDFe\ACBrDFeSSL.pas" (
  echo ERRO: fontes do ACBr nao encontrados em "%FISCONEXA_ACBR_ROOT%".
  echo Defina FISCONEXA_ACBR_ROOT para a raiz do ACBr instalado.
  exit /b 1
)
set "SCHEMAS_SOURCE=%FISCONEXA_ACBR_ROOT%\Exemplos\ACBrDFe\Schemas\NFe"
if not exist "%SCHEMAS_SOURCE%\distDFeInt_v1.01.xsd" (
  echo ERRO: schemas NFe do ACBr ausentes em "%SCHEMAS_SOURCE%".
  exit /b 1
)
set "OPENSSL_SOURCE=%ROOT%\vendor\postgres-client\pgsql"
if not "%FISCONEXA_OPENSSL_RUNTIME_DIR%"=="" set "OPENSSL_SOURCE=%FISCONEXA_OPENSSL_RUNTIME_DIR%"
if not exist "%OPENSSL_SOURCE%\bin\libcrypto-3-x64.dll" (
  echo ERRO: libcrypto-3-x64.dll ausente em "%OPENSSL_SOURCE%\bin".
  exit /b 1
)
if not exist "%OPENSSL_SOURCE%\bin\libssl-3-x64.dll" (
  echo ERRO: libssl-3-x64.dll ausente em "%OPENSSL_SOURCE%\bin".
  exit /b 1
)
if not exist "%ROOT%\bin\win64" mkdir "%ROOT%\bin\win64"
if not exist "%ROOT%\build\win64\dcu" mkdir "%ROOT%\build\win64\dcu"

call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
if errorlevel 1 exit /b 1

set "ACBR_RESPONSE=%ROOT%\build\win64\acbr-paths.rsp"
>"%ACBR_RESPONSE%" echo -I"%FISCONEXA_ACBR_ROOT%\Fontes\ACBrComum"
>>"%ACBR_RESPONSE%" echo -U"%FISCONEXA_ACBR_ROOT%\Fontes"
for /D /R "%FISCONEXA_ACBR_ROOT%\Fontes" %%D in (*) do >>"%ACBR_RESPONSE%" echo -U"%%~fD"

dcc64 -B -DRELEASE -$D- -$L- -$Y- -O+ -E"%ROOT%\bin\win64" -N0"%ROOT%\build\win64\dcu" -NS"System;System.Win;Xml;Data;Datasnap;Web;Soap;Winapi;Vcl" -U"%ROOT%\src\application";"%ROOT%\src\db";"%ROOT%\src\persistence";"%ROOT%\src\worker";"%ROOT%\src\integrations";"C:\Program Files (x86)\Devart\UniDAC for RAD Studio 12\Lib\Win64" @"%ACBR_RESPONSE%" "%ROOT%\apps\worker\FiscoNexa.Worker.dpr"
if errorlevel 1 exit /b 1

robocopy "%SCHEMAS_SOURCE%" "%ROOT%\bin\win64\Schemas" /E /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 (
  echo ERRO: nao foi possivel empacotar os schemas ACBr.
  exit /b 1
)
copy /Y "%OPENSSL_SOURCE%\bin\libcrypto-3-x64.dll" "%ROOT%\bin\win64\" >nul
if errorlevel 1 exit /b 1
copy /Y "%OPENSSL_SOURCE%\bin\libssl-3-x64.dll" "%ROOT%\bin\win64\" >nul
if errorlevel 1 exit /b 1
if exist "%OPENSSL_SOURCE%\lib\ossl-modules\legacy.dll" (
  if not exist "%ROOT%\bin\win64\ossl-modules" mkdir "%ROOT%\bin\win64\ossl-modules"
  copy /Y "%OPENSSL_SOURCE%\lib\ossl-modules\legacy.dll" "%ROOT%\bin\win64\ossl-modules\" >nul
  if errorlevel 1 exit /b 1
)
exit /b 0
