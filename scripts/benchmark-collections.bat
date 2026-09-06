@echo off
setlocal EnableExtensions

set "ROOT=%~dp0.."
if not exist "%ROOT%\bin\benchmarks\win64" mkdir "%ROOT%\bin\benchmarks\win64"
if not exist "%ROOT%\build\benchmarks\win64\dcu" mkdir "%ROOT%\build\benchmarks\win64\dcu"

call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
if errorlevel 1 exit /b 1

dcc64 -B -DRELEASE -$D- -$L- -$Y- -O+ -E"%ROOT%\bin\benchmarks\win64" -N0"%ROOT%\build\benchmarks\win64\dcu" -NS"System;Xml;Data;Datasnap;Web;Soap;Winapi;Vcl" "%ROOT%\tests\benchmarks\FiscoNexa.CollectionsBenchmark.dpr"
if errorlevel 1 exit /b 1

"%ROOT%\bin\benchmarks\win64\FiscoNexa.CollectionsBenchmark.exe"
if errorlevel 1 exit /b 1

dcc64 -B -DRELEASE -$D- -$L- -$Y- -O+ -E"%ROOT%\bin\benchmarks\win64" -N0"%ROOT%\build\benchmarks\win64\dcu" -NS"System;Xml;Data;Datasnap;Web;Soap;Winapi;Vcl" "%ROOT%\tests\benchmarks\FiscoNexa.CollectionsMemoryBenchmark.dpr"
if errorlevel 1 exit /b 1

echo.
echo Memoria Windows com 10.000.000 records:
"%ROOT%\bin\benchmarks\win64\FiscoNexa.CollectionsMemoryBenchmark.exe" array
if errorlevel 1 exit /b 1
"%ROOT%\bin\benchmarks\win64\FiscoNexa.CollectionsMemoryBenchmark.exe" list
if errorlevel 1 exit /b 1
"%ROOT%\bin\benchmarks\win64\FiscoNexa.CollectionsMemoryBenchmark.exe" list-grow
