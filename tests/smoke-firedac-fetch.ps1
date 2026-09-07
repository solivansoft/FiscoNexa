$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

Get-Content -LiteralPath (Join-Path $root '.env') | ForEach-Object {
  if ($_ -match '^([^#=]+)=(.*)$') {
    Set-Item -Path ('Env:' + $matches[1].Trim()) -Value $matches[2]
  }
}
$env:FISCONEXA_DB_HOST = '127.0.0.1'
$env:FISCONEXA_DB_PORT = $env:POSTGRES_PORT
$env:FISCONEXA_DB_NAME = $env:POSTGRES_DB
$env:FISCONEXA_DB_USER = $env:POSTGRES_USER
$env:FISCONEXA_DB_PASSWORD = $env:POSTGRES_PASSWORD
$env:Path = (Join-Path $root 'vendor\postgres-client\pgsql\bin') + ';' + $env:Path

& cmd /c (Join-Path $root 'scripts\test-firedac-fetch.bat')
if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar smoke FireDAC.' }

& (Join-Path $root 'bin\tests\win64\FiscoNexa.FireDacFetchIntegration.exe')
if ($LASTEXITCODE -ne 0) { throw 'Smoke FireDAC falhou.' }
