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
  set S3_ACCESS_KEY=%S3_ACCESS_KEY%
  set S3_SECRECT_KEY=%S3_SECRECT_KEY%
  set AWS_ACCESS_KEY_ID=%AWS_ACCESS_KEY_ID%
  set AWS_SECRET_ACCESS_KEY=%AWS_SECRET_ACCESS_KEY%
  set AWS_REGION=%AWS_REGION%
  set S3_XML_BUCKET=%S3_XML_BUCKET%
)

rem Compatibilidade temporaria com os nomes iniciais do S3.
if not defined AWS_ACCESS_KEY_ID if defined S3_ACCESS_KEY set "AWS_ACCESS_KEY_ID=%S3_ACCESS_KEY%"
if not defined AWS_SECRET_ACCESS_KEY if defined S3_SECRECT_KEY set "AWS_SECRET_ACCESS_KEY=%S3_SECRECT_KEY%"
if not defined AWS_REGION set "AWS_REGION=sa-east-1"
