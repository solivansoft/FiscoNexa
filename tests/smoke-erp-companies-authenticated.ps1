param(
  [string]$Executable = "$(Join-Path $PSScriptRoot '..\bin\win64\FiscoNexa.Api.exe')"
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root '.env'
$tempPfx = Join-Path ([IO.Path]::GetTempPath()) ('fisconexa-onboarding-' + [guid]::NewGuid().ToString('N') + '.pfx')
$certificatePassword = 'FiscoNexa-Onboarding-Test-Only-2026!'
$cnpj = '97' + (Get-Date -Format 'yyMMddHHmmss')
$erpToken = 'fnx-onboarding-' + [guid]::NewGuid().ToString('N')
$organizationId = ''
$companyId = ''
$process = $null

Get-Content -LiteralPath $envFile | ForEach-Object {
  if ($_ -match '^([^#=]+)=(.*)$') {
    Set-Item -Path ('Env:' + $matches[1].Trim()) -Value $matches[2]
  }
}

foreach ($name in 'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_REGION', 'FISCONEXA_KMS_KEY_ID') {
  if ([string]::IsNullOrWhiteSpace((Get-Item "Env:$name" -ErrorAction SilentlyContinue).Value)) {
    throw "Variavel obrigatoria ausente para smoke autenticado: $name"
  }
}

$env:FISCONEXA_DB_HOST = '127.0.0.1'
$env:FISCONEXA_DB_PORT = $env:POSTGRES_PORT
$env:FISCONEXA_DB_NAME = $env:POSTGRES_DB
$env:FISCONEXA_DB_USER = $env:POSTGRES_USER
$env:FISCONEXA_DB_PASSWORD = $env:POSTGRES_PASSWORD
$postgresBin = Join-Path $root 'vendor\postgres-client\pgsql\bin'
$psql = Join-Path $postgresBin 'psql.exe'
if (-not (Test-Path -LiteralPath $psql)) { throw 'psql.exe ausente.' }
$env:PGPASSWORD = $env:FISCONEXA_DB_PASSWORD
$env:Path = $postgresBin + ';' + $env:Path

function Invoke-Sql([string]$sql) {
  $result = & $psql -q -h $env:FISCONEXA_DB_HOST -p $env:FISCONEXA_DB_PORT `
    -U $env:FISCONEXA_DB_USER -d $env:FISCONEXA_DB_NAME -At -c $sql
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao executar fixture PostgreSQL.' }
  return $result
}

try {
  $fixture = Invoke-Sql "with organization as (insert into organizacoes (legal_name, organization_type) values ('ERP HTTP smoke', 'erp') returning id) insert into chaves_erp (organization_id, label, key_hash, scopes) select id, 'HTTP smoke', encode(digest('$erpToken', 'sha256'), 'hex'), jsonb_build_array('companies:onboard', 'modules:write') from organization returning organization_id::text"
  $organizationId = [string]$fixture

  $subject = New-Object Security.Cryptography.X509Certificates.X500DistinguishedName("CN=FiscoNexa HTTP Smoke,OID.2.16.76.1.3.3=$cnpj")
  $rsa = [Security.Cryptography.RSA]::Create(2048)
  try {
    $request = New-Object Security.Cryptography.X509Certificates.CertificateRequest($subject, $rsa, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $certificate = $request.CreateSelfSigned([datetimeoffset]::Now.AddDays(-1), [datetimeoffset]::Now.AddDays(30))
    try {
      [IO.File]::WriteAllBytes($tempPfx, $certificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $certificatePassword))
    } finally {
      $certificate.Dispose()
    }
  } finally {
    $rsa.Dispose()
  }

  $payload = @{
    uf = 'PA'
    certificado_a1_base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($tempPfx))
    senha_certificado_base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($certificatePassword))
  } | ConvertTo-Json -Compress

  $process = Start-Process -FilePath $Executable -PassThru -WindowStyle Hidden
  $deadline = (Get-Date).AddSeconds(10)
  do {
    try {
      Invoke-RestMethod -Uri 'http://127.0.0.1:9000/saude' -TimeoutSec 1 | Out-Null
      break
    } catch {
      Start-Sleep -Milliseconds 200
    }
  } while ((Get-Date) -lt $deadline)

  $headers = @{ Authorization = "Bearer $erpToken"; 'Idempotency-Key' = 'http-onboarding-smoke-1' }
  $first = Invoke-RestMethod -Uri 'http://127.0.0.1:9000/v1/empresas' -Method Post -Headers $headers -ContentType 'application/json' -Body $payload
  $companyId = $first.id_empresa
  if ([string]::IsNullOrWhiteSpace($first.token_integracao)) { throw 'Primeiro onboarding nao retornou token do tenant.' }
  if ($first.repetido) { throw 'Primeiro onboarding foi marcado como repetido.' }

  $second = Invoke-RestMethod -Uri 'http://127.0.0.1:9000/v1/empresas' -Method Post -Headers $headers -ContentType 'application/json' -Body $payload
  if (-not $second.repetido) { throw 'Reenvio nao foi marcado como repetido.' }
  if ($second.PSObject.Properties.Name -contains 'token_integracao') { throw 'Reenvio devolveu token persistido.' }

  $counts = Invoke-Sql "select (select count(*) from certificados where company_id = '$companyId') || '|' || (select count(*) from integracoes where company_id = '$companyId') || '|' || (select count(*) from empresas_modulos where company_id = '$companyId') || '|' || (select count(*) from comandos where company_id = '$companyId')"
  if ($counts -ne '1|1|1|1') { throw "Idempotencia falhou; contagens: $counts" }
  Invoke-RestMethod -Uri ("http://127.0.0.1:9000/v1/empresas/" + $companyId + '/modulos/monitoramento') -Method Put -Headers $headers -ContentType 'application/json' -Body '{"situacao":"suspenso"}' -TimeoutSec 2 | Out-Null
  $moduleStatus = Invoke-Sql "select status from empresas_modulos where company_id = '$companyId' and code = 'monitoring'"
  if ($moduleStatus -ne 'suspended') { throw 'Suspensao do modulo pelo ERP falhou.' }
  Write-Output 'Smoke HTTP autenticado aprovado: A1, KMS, onboarding e reenvio idempotente validados.'
} finally {
  if ($null -ne $process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force }
  if ($companyId -ne '') { Invoke-Sql "delete from empresas where id::text = '$companyId'" }
  if ($organizationId -ne '') { Invoke-Sql "delete from organizacoes where id::text = '$organizationId'" }
  if (Test-Path -LiteralPath $tempPfx) { Remove-Item -LiteralPath $tempPfx -Force }
}
