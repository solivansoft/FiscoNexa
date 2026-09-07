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
  $ready = $false
  do {
    try {
      $response = Invoke-RestMethod -Uri 'http://127.0.0.1:9000/health' -TimeoutSec 1
      if ($response.situacao -eq 'disponivel') {
        $ready = $true
        break
      }
    } catch {
      Start-Sleep -Milliseconds 200
    }
  } while ((Get-Date) -lt $deadline)

  if (-not $ready) {
    throw 'GET /health nao respondeu situacao=disponivel dentro de 10 segundos.'
  }

  $legacyStatus = 0
  try {
    Invoke-WebRequest -Uri 'http://127.0.0.1:9000/saude' -UseBasicParsing -TimeoutSec 1 | Out-Null
    $legacyStatus = 200
  } catch {
    if ($_.Exception.Response) {
      $legacyStatus = [int]$_.Exception.Response.StatusCode
    } else {
      throw
    }
  }
  if ($legacyStatus -ne 404) {
    throw "Rota legada GET /saude deveria responder 404, mas respondeu $legacyStatus."
  }

  Write-Output 'Smoke test aprovado: GET /health respondeu situacao=disponivel e GET /saude respondeu 404.'
} finally {
  if (-not $process.HasExited) {
    Stop-Process -Id $process.Id -Force
  }
}
