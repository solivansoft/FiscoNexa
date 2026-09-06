@echo off
setlocal EnableExtensions

set "ROOT=%~dp0.."
if not exist "%ROOT%\bin\stress\win64" mkdir "%ROOT%\bin\stress\win64"
if not exist "%ROOT%\build\stress\win64\dcu" mkdir "%ROOT%\build\stress\win64\dcu"

call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
if errorlevel 1 exit /b 1

dcc64 -B -E"%ROOT%\bin\stress\win64" -N0"%ROOT%\build\stress\win64\dcu" -NS"System;Xml;Data;Datasnap;Web;Soap;Winapi;Vcl" "%ROOT%\tests\stress\FiscoNexa.MockSefazStress.dpr"
if errorlevel 1 exit /b 1

"%ROOT%\bin\stress\win64\FiscoNexa.MockSefazStress.exe" %*
exit /b %errorlevel%
