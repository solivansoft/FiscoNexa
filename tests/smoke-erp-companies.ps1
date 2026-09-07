param(
  [string]$Executable = "$(Join-Path $PSScriptRoot '..\bin\win64\FiscoNexa.Api.exe')"
)

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

$process = Start-Process -FilePath $Executable -PassThru -WindowStyle Hidden
try {
  $deadline = (Get-Date).AddSeconds(10)
  do {
    try {
      Invoke-RestMethod -Uri 'http://127.0.0.1:9000/health' -TimeoutSec 1 | Out-Null
      break
    } catch {
      Start-Sleep -Milliseconds 200
    }
  } while ((Get-Date) -lt $deadline)

  $body = '{"certificado_a1_base64":"AQ==","senha_certificado_base64":"AQ=="}'
  try {
    Invoke-WebRequest -Uri 'http://127.0.0.1:9000/v1/empresas' -Method Post `
      -Headers @{ 'Idempotency-Key' = 'smoke-no-auth' } -ContentType 'application/json' `
      -Body $body -UseBasicParsing | Out-Null
    throw 'Onboarding sem chave ERP foi aceito.'
  } catch [System.Net.WebException] {
    $response = $_.Exception.Response
    if ($response.StatusCode.value__ -ne 401) {
      throw "Esperado HTTP 401, recebido HTTP $($response.StatusCode.value__)."
    }
  }

  Write-Output 'Smoke HTTP onboarding aprovado: rota registrada e chave ERP ausente recusada.'
} finally {
  if (-not $process.HasExited) {
    Stop-Process -Id $process.Id -Force
  }
}
