@echo off
setlocal EnableExtensions

set "ROOT=%~dp0.."
set "WMLC=G:\solivansoft\wmlc\build\wmlc.exe"

if not exist "%ROOT%\bin\win64-wmlc" mkdir "%ROOT%\bin\win64-wmlc"
if not exist "%ROOT%\bin\linux64-wmlc" mkdir "%ROOT%\bin\linux64-wmlc"

"%WMLC%" -E "%ROOT%\bin\win64-wmlc" --target win64 --mode debug -o Wmlc.Smoke.exe "%ROOT%\tests\wmlc\Wmlc.Smoke.dpr"
if errorlevel 1 exit /b 1

"%WMLC%" -E "%ROOT%\bin\linux64-wmlc" --target linux64 --mode debug -o Wmlc.Smoke "%ROOT%\tests\wmlc\Wmlc.Smoke.dpr"
if errorlevel 1 exit /b 1

"%ROOT%\bin\win64-wmlc\Wmlc.Smoke.exe"
if errorlevel 1 exit /b 1

echo Execute o binario Linux com: wsl -- /mnt/g/GitHub/_sandbox/FiscoNexa/bin/linux64-wmlc/Wmlc.Smoke
