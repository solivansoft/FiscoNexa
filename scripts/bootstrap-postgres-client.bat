@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT=%~dp0.."
call "%ROOT%\third_party.lock.cmd"
set "CLIENT_ROOT=%ROOT%\vendor\postgres-client"
set "CLIENT_BIN=%CLIENT_ROOT%\pgsql\bin"

if exist "%CLIENT_BIN%\libpq.dll" goto verify

echo Baixando cliente PostgreSQL !POSTGRES_CLIENT_VERSION! da distribuicao oficial EDB...
set "ARCHIVE=%TEMP%\fisconexa-postgresql-!POSTGRES_CLIENT_VERSION!-windows-x64.zip"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri '!POSTGRES_CLIENT_URL!' -OutFile '!ARCHIVE!'; Expand-Archive -LiteralPath '!ARCHIVE!' -DestinationPath '!CLIENT_ROOT!' -Force"
if errorlevel 1 exit /b 1

if not exist "%CLIENT_BIN%\libpq.dll" (
  echo ERRO: libpq.dll nao foi encontrada no pacote baixado.
  exit /b 1
)

:verify
for /f %%H in ('powershell -NoProfile -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath '!CLIENT_BIN!\libpq.dll').Hash"') do set "ACTUAL_HASH=%%H"
if /I not "!ACTUAL_HASH!"=="!POSTGRES_CLIENT_LIBPQ_SHA256!" (
  echo ERRO: SHA256 de libpq.dll diverge do lock.
  exit /b 1
)

echo Cliente PostgreSQL pronto em %CLIENT_BIN%.
