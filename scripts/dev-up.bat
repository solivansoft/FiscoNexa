@echo off
setlocal EnableExtensions

set "ROOT=%~dp0.."
if not exist "%ROOT%\.env" (
  copy "%ROOT%\.env.example" "%ROOT%\.env" >nul
  echo Criado .env local. Troque POSTGRES_PASSWORD antes de usar fora do desenvolvimento.
)

docker compose --project-directory "%ROOT%" up -d --wait postgres
if errorlevel 1 exit /b 1

docker compose --project-directory "%ROOT%" ps
