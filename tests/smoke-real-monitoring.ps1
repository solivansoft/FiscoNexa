param(
  [string]$ApiExecutable = "$(Join-Path $PSScriptRoot '..\bin\win64\FiscoNexa.Api.exe')",
  [string]$WorkerExecutable = "$(Join-Path $PSScriptRoot '..\bin\win64\FiscoNexa.Worker.exe')"
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$apiProcess = $null
$adminToken = ''
$bootstrapKey = ''
$erpId = ''
$erpKeyId = ''
$companyId = ''

function Import-DotEnv {
  $envFile = Join-Path $root '.env'
  if (-not (Test-Path -LiteralPath $envFile)) { throw 'Arquivo .env ausente.' }
  Get-Content -LiteralPath $envFile | ForEach-Object {
    if ($_ -match '^([^#=]+)=(.*)$') {
      $value = $matches[2].Trim()
      if (($value.Length -ge 2) -and
        (($value.StartsWith('"') -and $value.EndsWith('"')) -or
         ($value.StartsWith("'") -and $value.EndsWith("'")))) {
        $value = $value.Substring(1, $value.Length - 2)
      }
      Set-Item -Path ('Env:' + $matches[1].Trim()) -Value $value
    }
  }
}

function Require-EnvironmentValue([string]$Name) {
  $value = (Get-Item "Env:$Name" -ErrorAction SilentlyContinue).Value
  if ([string]::IsNullOrWhiteSpace($value)) { throw "Variavel obrigatoria ausente: $Name" }
  return $value
}

function Invoke-ApiJson([string]$Method, [string]$Path, [hashtable]$Headers, $Body = $null) {
  $parameters = @{ Method = $Method; Uri = ($env:FISCONEXA_API_URL + $Path); Headers = $Headers }
  if ($null -ne $Body) {
    $parameters.ContentType = 'application/json'
    $parameters.Body = ($Body | ConvertTo-Json -Compress)
  }
  return Invoke-RestMethod @parameters
}

function Suspend-Monitoring {
  if ([string]::IsNullOrWhiteSpace($companyId) -or [string]::IsNullOrWhiteSpace($bootstrapKey)) { return }
  try {
    Invoke-ApiJson 'PUT' "/v1/empresas/$companyId/modulos/monitoramento" @{ Authorization = $bootstrapKey } @{ situacao = 'suspenso' } | Out-Null
  } catch {
    Write-Warning 'Nao foi possivel suspender o modulo criado pelo smoke.'
  }
}

function Revoke-SmokeKey {
  if ([string]::IsNullOrWhiteSpace($erpId) -or [string]::IsNullOrWhiteSpace($erpKeyId) -or [string]::IsNullOrWhiteSpace($adminToken)) { return }
  try {
    Invoke-ApiJson 'DELETE' "/administracao/erps/$erpId/chaves/$erpKeyId" @{ Authorization = "Bearer $adminToken" } | Out-Null
  } catch {
    Write-Warning 'Nao foi possivel revogar a chave ERP criada pelo smoke.'
  }
}

Import-DotEnv
foreach ($name in 'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_REGION',
  'FISCONEXA_KMS_KEY_ID', 'S3_XML_BUCKET', 'FISCONEXA_TEST_PFX_PATH',
  'FISCONEXA_TEST_PFX_PASSWORD', 'FISCONEXA_TEST_SEFAZ_UF',
  'FISCONEXA_SEFAZ_REAL_CONFIRMATION', 'FISCONEXA_ADMIN_EMAIL',
  'FISCONEXA_ADMIN_PASSWORD') {
  Require-EnvironmentValue $name | Out-Null
}
if ($env:FISCONEXA_SEFAZ_REAL_CONFIRMATION -ne 'YES') {
  throw 'Confirme explicitamente com FISCONEXA_SEFAZ_REAL_CONFIRMATION=YES.'
}
if (-not (Test-Path -LiteralPath $env:FISCONEXA_TEST_PFX_PATH)) {
  throw 'Arquivo PFX do smoke nao encontrado.'
}

$env:FISCONEXA_DB_HOST = '127.0.0.1'
$env:FISCONEXA_DB_PORT = $env:POSTGRES_PORT
$env:FISCONEXA_DB_NAME = $env:POSTGRES_DB
$env:FISCONEXA_DB_USER = $env:POSTGRES_USER
$env:FISCONEXA_DB_PASSWORD = $env:POSTGRES_PASSWORD
$env:FISCONEXA_API_URL = 'http://127.0.0.1:9000'
$env:FISCONEXA_SEFAZ_MODE = 'acbr'
$env:FISCONEXA_AUTO_AWARENESS = 'false'
$env:FISCONEXA_WORKER_ID = 'smoke-real-' + [guid]::NewGuid().ToString('N')
$env:FISCONEXA_WORKER_BATCH_SIZE = '1'
$env:FISCONEXA_WORKER_LEASE_SECONDS = '300'
$env:Path = (Join-Path $root 'vendor\postgres-client\pgsql\bin') + ';' + $env:Path

try {
  & cmd /c (Join-Path $root 'scripts\build-api.bat') win64
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar a API.' }
  & cmd /c (Join-Path $root 'scripts\build-worker.bat') win64
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar o worker.' }

  $apiProcess = Start-Process -FilePath $ApiExecutable -PassThru -WindowStyle Hidden
  $deadline = (Get-Date).AddSeconds(15)
  do {
    try {
      if ((Invoke-RestMethod -Uri "$env:FISCONEXA_API_URL/saude" -TimeoutSec 1).situacao -eq 'disponivel') { break }
    } catch { Start-Sleep -Milliseconds 200 }
  } while ((Get-Date) -lt $deadline)
  if ($null -eq $apiProcess -or $apiProcess.HasExited) { throw 'API encerrou antes do smoke.' }

  $login = Invoke-ApiJson 'POST' '/autenticacao/entrar' @{} @{
    email = $env:FISCONEXA_ADMIN_EMAIL
    senha = $env:FISCONEXA_ADMIN_PASSWORD
  }
  $adminToken = $login.token_acesso
  if ([string]::IsNullOrWhiteSpace($adminToken)) { throw 'Login nao retornou access token.' }

  $erp = Invoke-ApiJson 'POST' '/administracao/erps' @{ Authorization = "Bearer $adminToken" } @{
    razao_social = 'Smoke monitoramento real ' + (Get-Date -Format 'yyyyMMddHHmmss')
    rotulo_chave = 'Uso unico'
  }
  $erpId = $erp.id_erp
  $erpKeyId = $erp.id_chave
  $bootstrapKey = $erp.chave_erp
  if ([string]::IsNullOrWhiteSpace($bootstrapKey)) { throw 'API nao retornou chave ERP.' }

  $onboarding = Invoke-ApiJson 'POST' '/v1/empresas' @{ Authorization = $bootstrapKey; 'Idempotency-Key' = ('smoke-real-' + [guid]::NewGuid().ToString('N')) } @{
    uf = $env:FISCONEXA_TEST_SEFAZ_UF
    certificado_a1_base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($env:FISCONEXA_TEST_PFX_PATH))
    senha_certificado_base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($env:FISCONEXA_TEST_PFX_PASSWORD))
  }
  $companyId = $onboarding.id_empresa
  $tenantToken = $onboarding.token_integracao
  if ([string]::IsNullOrWhiteSpace($companyId) -or [string]::IsNullOrWhiteSpace($tenantToken)) {
    throw 'Onboarding nao retornou empresa e token do tenant.'
  }

  & $WorkerExecutable
  if ($LASTEXITCODE -ne 0) { throw 'Worker encerrou com erro.' }

  $monitoring = Invoke-ApiJson 'GET' '/v1/monitoramento' @{ Authorization = "Bearer $tenantToken" }
  if ($monitoring.ultimo_cstat -eq 656) { throw 'SEFAZ recusou o smoke por consumo indevido.' }
  if ($monitoring.ultimo_cstat -notin 137, 138) { throw "cStat inesperado no monitoramento: $($monitoring.ultimo_cstat)" }
  if ([string]::IsNullOrWhiteSpace($monitoring.consultado_em) -or [string]::IsNullOrWhiteSpace($monitoring.proxima_consulta_em)) {
    throw 'Worker nao persistiu a janela de monitoramento.'
  }
  Suspend-Monitoring
  Write-Output "Smoke vertical real aprovado: cStat=$($monitoring.ultimo_cstat); company_id=$companyId; modulo suspenso."
} finally {
  Suspend-Monitoring
  Revoke-SmokeKey
  if (($null -ne $apiProcess) -and (-not $apiProcess.HasExited)) { Stop-Process -Id $apiProcess.Id -Force }
}
