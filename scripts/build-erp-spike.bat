@echo off
setlocal
set "ROOT=%~dp0.."
call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
if errorlevel 1 exit /b 1
if not exist "%ROOT%\bin\examples\win64" mkdir "%ROOT%\bin\examples\win64"
if not exist "%ROOT%\build\examples\win64\dcu" mkdir "%ROOT%\build\examples\win64\dcu"
dcc64 -B -DRELEASE -$D- -$L- -$Y- -O+ ^
  -E"%ROOT%\bin\examples\win64" ^
  -N0"%ROOT%\build\examples\win64\dcu" ^
  -NS"System;System.Net;Xml;Data;Datasnap;Web;Soap;Winapi;Vcl" ^
  "%ROOT%\examples\erp-delphi\FiscoNexa.ErpSpike.dpr"
exit /b %errorlevel%
