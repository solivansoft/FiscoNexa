@echo off
setlocal EnableExtensions

set "ROOT=%~dp0.."
if not exist "%ROOT%\bin\tests\win64" mkdir "%ROOT%\bin\tests\win64"
if not exist "%ROOT%\build\tests\win64\dcu" mkdir "%ROOT%\build\tests\win64\dcu"

call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
if errorlevel 1 exit /b 1

dcc64 -B -E"%ROOT%\bin\tests\win64" -N0"%ROOT%\build\tests\win64\dcu" -NS"System;Xml;Data;Datasnap;Web;Soap;Winapi;Vcl" -U"%ROOT%\src\application";"%ROOT%\src\db";"%ROOT%\src\persistence";"%ROOT%\src\worker";"%ROOT%\src\integrations";"C:\Program Files (x86)\Devart\UniDAC for RAD Studio 12\Lib\Win64" "%ROOT%\tests\integration\FiscoNexa.MonitorLeasesIntegration.dpr"
exit /b %errorlevel%
