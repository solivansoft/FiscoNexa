@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT=%~dp0.."
call "%ROOT%\third_party.lock.cmd"

where git >nul 2>nul
if errorlevel 1 (
  echo ERRO: git nao foi encontrado no PATH.
  exit /b 1
)

if not exist "%ROOT%\vendor" mkdir "%ROOT%\vendor"

if not exist "%ROOT%\vendor\horse\.git" (
  echo Baixando Horse !HORSE_REF!...
  git clone --depth 1 --branch "!HORSE_REF!" "!HORSE_REPOSITORY!" "%ROOT%\vendor\horse"
  if errorlevel 1 exit /b 1
 ) else (
  git -C "%ROOT%\vendor\horse" diff --quiet
  if errorlevel 1 (
    echo ERRO: vendor\horse possui alteracoes locais. Reverte-as ou use outra pasta antes de sincronizar.
    exit /b 1
  )

  echo Sincronizando Horse com !HORSE_REF!...
  git -C "%ROOT%\vendor\horse" fetch --depth 1 origin "refs/tags/!HORSE_REF!:refs/tags/!HORSE_REF!"
  if errorlevel 1 exit /b 1
  git -C "%ROOT%\vendor\horse" checkout --detach "!HORSE_COMMIT!"
  if errorlevel 1 exit /b 1
)

for /f %%H in ('git -C "%ROOT%\vendor\horse" rev-parse HEAD') do set "ACTUAL_COMMIT=%%H"
if /I not "!ACTUAL_COMMIT!"=="!HORSE_COMMIT!" (
  echo ERRO: Horse local esta em !ACTUAL_COMMIT!, esperado !HORSE_COMMIT!.
  echo Apague somente a pasta vendor\horse e execute este script novamente.
  exit /b 1
)

echo Horse pronto em %ROOT%\vendor\horse (!ACTUAL_COMMIT!).
