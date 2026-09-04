@echo off
setlocal DisableDelayedExpansion

set "ROOT=%~dp0.."
if not exist "%ROOT%\.env" (
  echo ERRO: .env ausente.
  exit /b 1
)

for /f "usebackq tokens=1,* delims==" %%A in ("%ROOT%\.env") do (
  if not "%%A"=="" if not "%%A:~0,1"=="#" set "%%A=%%B"
)

endlocal & (
  set POSTGRES_DB=%POSTGRES_DB%
  set POSTGRES_USER=%POSTGRES_USER%
  set POSTGRES_PASSWORD=%POSTGRES_PASSWORD%
  set POSTGRES_PORT=%POSTGRES_PORT%
)
