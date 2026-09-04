param(
  [string]$Executable = "$(Join-Path $PSScriptRoot '..\bin\win64\FiscoNexa.Api.exe')"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Executable)) {
  throw "Executavel nao encontrado: $Executable"
}

$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root '.env'
if (-not (Test-Path -LiteralPath $envFile)) {
  throw 'Arquivo .env ausente. Execute scripts\\dev-up.bat primeiro.'
}

Get-Content -LiteralPath $envFile | ForEach-Object {
  if ($_ -match '^([^#=]+)=(.*)$') {
    Set-Item -Path ("Env:" + $matches[1].Trim()) -Value $matches[2]
  }
}

$env:FISCONEXA_DB_HOST = '127.0.0.1'
$env:FISCONEXA_DB_PORT = $env:POSTGRES_PORT
$env:FISCONEXA_DB_NAME = $env:POSTGRES_DB
$env:FISCONEXA_DB_USER = $env:POSTGRES_USER
$env:FISCONEXA_DB_PASSWORD = $env:POSTGRES_PASSWORD
$postgresClientBin = Join-Path $root 'vendor\\postgres-client\\pgsql\\bin'
if (-not (Test-Path -LiteralPath (Join-Path $postgresClientBin 'libpq.dll'))) {
  throw 'Cliente PostgreSQL ausente. Execute scripts\\bootstrap-postgres-client.bat.'
}
$env:Path = $postgresClientBin + ';' + $env:Path

$process = Start-Process -FilePath $Executable -PassThru -WindowStyle Hidden
try {
  $deadline = (Get-Date).AddSeconds(10)
  do {
    try {
      $response = Invoke-RestMethod -Uri 'http://127.0.0.1:9000/health' -TimeoutSec 1
      if ($response.status -eq 'ok') {
        Write-Output 'Smoke test aprovado: GET /health respondeu status=ok.'
        exit 0
      }
    } catch {
      Start-Sleep -Milliseconds 200
    }
  } while ((Get-Date) -lt $deadline)

  throw 'GET /health nao respondeu status=ok dentro de 10 segundos.'
} finally {
  if (-not $process.HasExited) {
    Stop-Process -Id $process.Id -Force
  }
}
