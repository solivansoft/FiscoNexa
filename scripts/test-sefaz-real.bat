@echo off
setlocal EnableExtensions EnableDelayedExpansion

if /I not "%~1"=="win64" (
  echo Uso: test-sefaz-real.bat win64
  exit /b 2
)

set "ROOT=%~dp0.."
if "%FISCONEXA_ACBR_ROOT%"=="" set "FISCONEXA_ACBR_ROOT=G:\Sources\Componentes\ACBr\trunk2"
if not exist "%FISCONEXA_ACBR_ROOT%\Fontes\ACBrDFe\ACBrDFeSSL.pas" (
  echo ERRO: fontes ACBr ausentes. Defina FISCONEXA_ACBR_ROOT.
  exit /b 1
)
set "SCHEMAS_SOURCE=%FISCONEXA_ACBR_ROOT%\Exemplos\ACBrDFe\Schemas\NFe"
if not exist "%SCHEMAS_SOURCE%\distDFeInt_v1.01.xsd" (
  echo ERRO: schemas NFe do ACBr ausentes em "%SCHEMAS_SOURCE%".
  exit /b 1
)
if not exist "%ROOT%\bin\tests\win64" mkdir "%ROOT%\bin\tests\win64"
if not exist "%ROOT%\build\tests\win64\dcu" mkdir "%ROOT%\build\tests\win64\dcu"

call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
if errorlevel 1 exit /b 1

set "ACBR_RESPONSE=%ROOT%\build\tests\win64\acbr-paths.rsp"
>"%ACBR_RESPONSE%" echo -I"%FISCONEXA_ACBR_ROOT%\Fontes\ACBrComum"
>>"%ACBR_RESPONSE%" echo -U"%FISCONEXA_ACBR_ROOT%\Fontes"
for /D /R "%FISCONEXA_ACBR_ROOT%\Fontes" %%D in (*) do >>"%ACBR_RESPONSE%" echo -U"%%~fD"

dcc64 -B -DRELEASE -$D- -$L- -$Y- -O+ -E"%ROOT%\bin\tests\win64" -N0"%ROOT%\build\tests\win64\dcu" -NS"System;System.Win;Xml;Data;Datasnap;Web;Soap;Winapi;Vcl" -U"%ROOT%\src\application";"%ROOT%\src\integrations" @"%ACBR_RESPONSE%" "%ROOT%\tests\integration\FiscoNexa.SefazRealIntegration.dpr"
if errorlevel 1 exit /b 1

copy /Y "%ROOT%\vendor\postgres-client\pgsql\bin\libcrypto-3-x64.dll" "%ROOT%\bin\tests\win64\" >nul
if errorlevel 1 exit /b 1
copy /Y "%ROOT%\vendor\postgres-client\pgsql\bin\libssl-3-x64.dll" "%ROOT%\bin\tests\win64\" >nul
if errorlevel 1 exit /b 1

robocopy "%SCHEMAS_SOURCE%" "%ROOT%\bin\tests\win64\Schemas" /E /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 (
  echo ERRO: nao foi possivel empacotar os schemas ACBr.
  exit /b 1
)
exit /b 0
