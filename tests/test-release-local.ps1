$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Get-Content -LiteralPath (Join-Path $root '.env') | ForEach-Object {
  if ($_ -match '^([^#=]+)=(.*)$') {
    Set-Item -Path ('Env:' + $matches[1].Trim()) -Value $matches[2]
  }
}
$database = 'fisconexa_test_' + [guid]::NewGuid().ToString('N')
$env:FISCONEXA_DB_HOST = '127.0.0.1'
$env:FISCONEXA_DB_PORT = $env:POSTGRES_PORT
$env:FISCONEXA_DB_NAME = $database
$env:FISCONEXA_DB_USER = $env:POSTGRES_USER
$env:FISCONEXA_DB_PASSWORD = $env:POSTGRES_PASSWORD
$env:Path = (Join-Path $root 'vendor\postgres-client\pgsql\bin') + ';' + $env:Path
try {
  & (Join-Path $root 'scripts\build-api.bat') win64
  if ($LASTEXITCODE -ne 0) { throw 'Build da API falhou.' }
  & docker exec fisconexa-postgres createdb -U $env:POSTGRES_USER $database
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar banco isolado.' }
  & (Join-Path $root 'scripts\test-schema.bat')
  if ($LASTEXITCODE -ne 0) { throw 'Build do teste de schema falhou.' }
  & (Join-Path $root 'bin\tests\win64\FiscoNexa.SchemaIntegration.exe')
  if ($LASTEXITCODE -ne 0) { throw 'Teste de schema falhou.' }
  & (Join-Path $root 'scripts\test-company-onboarding.bat')
  if ($LASTEXITCODE -ne 0) { throw 'Build de onboarding falhou.' }
  & (Join-Path $root 'bin\tests\win64\FiscoNexa.CompanyOnboardingIntegration.exe')
  if ($LASTEXITCODE -ne 0) { throw 'Persistencia cadastral falhou.' }
  & (Join-Path $root 'scripts\test-monitor-leases.bat')
  if ($LASTEXITCODE -ne 0) { throw 'Build do teste de leases falhou.' }
  & (Join-Path $root 'bin\tests\win64\FiscoNexa.MonitorLeasesIntegration.exe')
  if ($LASTEXITCODE -ne 0) { throw 'Teste de leases falhou.' }
  & (Join-Path $root 'scripts\test-unidac-fetch.bat')
  if ($LASTEXITCODE -ne 0) { throw 'Build do teste UniDAC falhou.' }
  & (Join-Path $root 'bin\tests\win64\FiscoNexa.UniDacFetchIntegration.exe')
  if ($LASTEXITCODE -ne 0) { throw 'Teste UniDAC falhou.' }
  $env:POSTGRES_DB = $database
  & (Join-Path $root 'tests\smoke-erp-documents.ps1') -UseCurrentEnvironment
} finally {
  & docker exec fisconexa-postgres dropdb --if-exists -U $env:POSTGRES_USER $database
  if ($LASTEXITCODE -ne 0) { throw "Falha ao remover banco de teste $database." }
}
