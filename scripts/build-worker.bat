@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "PLATFORM=%~1"
if "%PLATFORM%"=="" set "PLATFORM=win64"

if /I "%PLATFORM%"=="win64" goto win64
if /I "%PLATFORM%"=="linux64" goto linux64

echo Uso: build-worker.bat ^<win64^|linux64^>
exit /b 2

:win64
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

dcc64 -B -DRELEASE -$D- -$L- -$Y- -O+ -E"%ROOT%\bin\win64" -N0"%ROOT%\build\win64\dcu" -NS"System;System.Win;Xml;Data;Datasnap;Web;Soap;Winapi;Vcl" -U"%ROOT%\src\application";"%ROOT%\src\db";"%ROOT%\src\persistence";"%ROOT%\src\worker";"%ROOT%\src\integrations";"%ROOT%\src\operations" @"%ACBR_RESPONSE%" "%ROOT%\apps\worker\FiscoNexa.Worker.dpr"
if errorlevel 1 exit /b 1

robocopy "%SCHEMAS_SOURCE%" "%ROOT%\bin\win64\Schemas" /E /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 (
  echo ERRO: nao foi possivel empacotar os schemas ACBr.
  exit /b 1
)
rem FireDAC PostgreSQL requer libpq e suas dependencias nativas.
copy /Y "%ROOT%\vendor\postgres-client\pgsql\bin\*.dll" "%ROOT%\bin\win64\" >nul
if errorlevel 1 exit /b 1
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

:linux64
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
if not exist "%ROOT%\build\linux64\worker-dcu" mkdir "%ROOT%\build\linux64\worker-dcu"
if not exist "%ROOT%\build\linux64\worker-obj" mkdir "%ROOT%\build\linux64\worker-obj"
if not exist "%ROOT%\build\linux64\lib" mkdir "%ROOT%\build\linux64\lib"

>"%ROOT%\build\linux64\lib\libcrypto.so" echo INPUT ^( libcrypto.so.3 ^)

call "%RAD_ROOT%\bin\rsvars.bat"
if errorlevel 1 exit /b 1

set "ACBR_UNIT_PATHS=%FISCONEXA_ACBR_ROOT%\Fontes;%FISCONEXA_ACBR_ROOT%\Fontes\ACBrComum;%FISCONEXA_ACBR_ROOT%\Fontes\ACBrTCP;%FISCONEXA_ACBR_ROOT%\Fontes\ACBrDiversos;%FISCONEXA_ACBR_ROOT%\Fontes\ACBrIntegrador;%FISCONEXA_ACBR_ROOT%\Fontes\ACBrIntegrador\pcnVFPe;%FISCONEXA_ACBR_ROOT%\Fontes\ACBrLibXML2;%FISCONEXA_ACBR_ROOT%\Fontes\PCNComum;%FISCONEXA_ACBR_ROOT%\Fontes\ACBrDFe;%FISCONEXA_ACBR_ROOT%\Fontes\ACBrDFe\Comum;%FISCONEXA_ACBR_ROOT%\Fontes\ACBrDFe\ACBrNFe;%FISCONEXA_ACBR_ROOT%\Fontes\ACBrDFe\ACBrNFe\Base;%FISCONEXA_ACBR_ROOT%\Fontes\ACBrDFe\ACBrNFe\Base\Servicos;%FISCONEXA_ACBR_ROOT%\Fontes\ACBrDFe\ACBrNFe\PCNNFe;%FISCONEXA_ACBR_ROOT%\Fontes\ACBrDFe\ACBrNFe\DANFE;%FISCONEXA_ACBR_ROOT%\Fontes\ACBrOpenSSL;%FISCONEXA_ACBR_ROOT%\Fontes\Terceiros\LibXmlSec;%FISCONEXA_ACBR_ROOT%\Fontes\Terceiros\synalist;%FISCONEXA_ACBR_ROOT%\Fontes\Terceiros\FastStringReplace;%FISCONEXA_ACBR_ROOT%\Fontes\Terceiros\GZIPUtils;%FISCONEXA_ACBR_ROOT%\Fontes\Terceiros\JsonDataObjects\Source"
set "DCC_IncludePath=%FISCONEXA_ACBR_ROOT%\Fontes\ACBrComum"
set "DCC_UnitSearchPath=%ROOT%\src\application;%ROOT%\src\db;%ROOT%\src\persistence;%ROOT%\src\worker;%ROOT%\src\integrations;%ROOT%\src\operations;%ROOT%\build\linux64\lib;!ACBR_UNIT_PATHS!"
set "DCC_DcuOutput=%ROOT%\build\linux64\worker-dcu"
set "DCC_ObjOutput=%ROOT%\build\linux64\worker-obj"
set "DCC_ExeOutput=%ROOT%\bin\linux64"

"%MSBUILD%" "%ROOT%\apps\worker\FiscoNexa.Worker.dproj" /t:Build /p:Config=Release /p:Platform=Linux64 /v:minimal
if errorlevel 1 exit /b 1

robocopy "%SCHEMAS_SOURCE%" "%ROOT%\bin\linux64\Schemas" /E /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 (
  echo ERRO: nao foi possivel empacotar os schemas ACBr.
  exit /b 1
)
exit /b 0
