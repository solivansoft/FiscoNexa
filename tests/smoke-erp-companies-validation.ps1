param(
  [string]$Executable = "$(Join-Path $PSScriptRoot '..\bin\win64\FiscoNexa.Api.exe')"
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$organizationId = ''
$process = $null
$erpToken = 'fnx-validation-' + [guid]::NewGuid().ToString('N')

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
$postgresBin = Join-Path $root 'vendor\postgres-client\pgsql\bin'
$psql = Join-Path $postgresBin 'psql.exe'
$env:PGPASSWORD = $env:FISCONEXA_DB_PASSWORD
$env:Path = $postgresBin + ';' + $env:Path

function Invoke-Sql([string]$sql) {
  $result = & $psql -q -h $env:FISCONEXA_DB_HOST -p $env:FISCONEXA_DB_PORT `
    -U $env:FISCONEXA_DB_USER -d $env:FISCONEXA_DB_NAME -At -c $sql
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar fixture PostgreSQL.' }
  return $result
}

try {
  $organizationId = Invoke-Sql "with organization as (insert into organizacoes (legal_name, organization_type) values ('ERP validation smoke', 'erp') returning id) insert into chaves_erp (organization_id, label, key_hash, scopes) select id, 'Validation smoke', encode(digest('$erpToken', 'sha256'), 'hex'), jsonb_build_array('companies:onboard') from organization returning organization_id::text"
  $process = Start-Process -FilePath $Executable -PassThru -WindowStyle Hidden
  $deadline = (Get-Date).AddSeconds(10)
  do {
    try {
      Invoke-RestMethod -Uri 'http://127.0.0.1:9000/health' -TimeoutSec 1 | Out-Null
      break
    } catch {
      Start-Sleep -Milliseconds 200
    }
  } while ((Get-Date) -lt $deadline)

  try {
    Invoke-WebRequest -Uri 'http://127.0.0.1:9000/v1/empresas' -Method Post `
      -Headers @{ Authorization = "Bearer $erpToken"; 'Idempotency-Key' = 'invalid-request' } `
      -ContentType 'application/json' -Body '{"certificado_a1_base64":"","senha_certificado_base64":""}' -UseBasicParsing | Out-Null
    throw 'Onboarding sem A1 foi aceito.'
  } catch [System.Net.WebException] {
    if ($_.Exception.Response.StatusCode.value__ -ne 422) {
      throw "Esperado HTTP 422, recebido HTTP $($_.Exception.Response.StatusCode.value__)."
    }
  }
  Write-Output 'Smoke validacao onboarding aprovado: chave ERP valida e A1 ausente recusado com 422 sem chamar KMS.'
} finally {
  if ($null -ne $process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force }
  if ($organizationId -ne '') { Invoke-Sql "delete from organizacoes where id::text = '$organizationId'" }
}
