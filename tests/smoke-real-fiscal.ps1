param(
  [switch]$AllowAwareness,
  [string]$CertificatePath,
  [ValidatePattern('^[A-Z]{2}$')][string]$CompanyState,
  [ValidateSet('principal','segundo')][string]$Pilot = 'principal'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$api = Join-Path $root 'bin\win64\FiscoNexa.Api.exe'
$worker = Join-Path $root 'bin\win64\FiscoNexa.Worker.exe'
$sessionFile = Join-Path $root 'build\pilot-session.clixml'
if ($Pilot -eq 'segundo') { $sessionFile = Join-Path $root 'build\pilot-session-segundo.clixml' }
$adminFile = Join-Path $root 'build\pilot-admin.clixml'
$apiProcess = $null
Get-Content -LiteralPath (Join-Path $root '.env') | ForEach-Object {
  if ($_ -match '^([^#=]+)=(.*)$') {
    $value = $matches[2].Trim().Trim('"').Trim("'")
    Set-Item -Path ('Env:' + $matches[1].Trim()) -Value $value
  }
}
if ($CertificatePath) { $env:FISCONEXA_TEST_PFX_PATH = $CertificatePath }
if ($CompanyState) { $env:FISCONEXA_TEST_SEFAZ_UF = $CompanyState }
if (-not $AllowAwareness) { throw 'Este smoke fiscal exige autorizacao expressa e -AllowAwareness.' }
foreach ($name in 'FISCONEXA_TEST_PFX_PATH','FISCONEXA_TEST_PFX_PASSWORD','FISCONEXA_TEST_SEFAZ_UF',
  'AWS_ACCESS_KEY_ID','AWS_SECRET_ACCESS_KEY','AWS_REGION','FISCONEXA_KMS_KEY_ID','S3_XML_BUCKET') {
  if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
    throw "Variavel obrigatoria ausente: $name"
  }
}
$fingerprint = (Get-FileHash -LiteralPath $env:FISCONEXA_TEST_PFX_PATH -Algorithm SHA256).Hash
$env:FISCONEXA_DB_HOST = '127.0.0.1'
$env:FISCONEXA_DB_PORT = $env:POSTGRES_PORT
$env:FISCONEXA_DB_NAME = $env:POSTGRES_DB
$env:FISCONEXA_DB_USER = $env:POSTGRES_USER
$env:FISCONEXA_DB_PASSWORD = $env:POSTGRES_PASSWORD
$env:FISCONEXA_SEFAZ_MODE = 'acbr'
$env:FISCONEXA_AUTO_AWARENESS = 'true'
$env:FISCONEXA_WORKER_ID = 'piloto-' + [guid]::NewGuid().ToString('N')
$env:FISCONEXA_WORKER_BATCH_SIZE = '1'
$env:FISCONEXA_WORKER_LEASE_SECONDS = '7200'
$env:Path = (Join-Path $root 'bin\win64') + ';' + (Join-Path $root 'vendor\postgres-client\pgsql\bin') + ';' + $env:Path

function Sql([string]$Text) {
  $result = & docker exec fisconexa-postgres psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB -v ON_ERROR_STOP=1 -Atc $Text
  if ($LASTEXITCODE -ne 0) { throw 'Consulta de verificacao PostgreSQL falhou.' }
  return $result
}
function ApiJson([string]$Method, [string]$Path, [hashtable]$Headers, $Body = $null) {
  $args = @{ Method=$Method; Uri=('http://127.0.0.1:9000'+$Path); Headers=$Headers; TimeoutSec=120 }
  if ($null -ne $Body) { $args.ContentType='application/json'; $args.Body=($Body|ConvertTo-Json -Compress) }
  return Invoke-RestMethod @args
}
try {
  if (Get-NetTCPConnection -LocalPort 9000 -State Listen -ErrorAction SilentlyContinue) {
    throw 'Porta 9000 ja ocupada; nao assumir identidade de outro processo.'
  }
  if (-not (Test-Path -LiteralPath $sessionFile)) {
    if ([string]::IsNullOrWhiteSpace($env:FISCONEXA_ADMIN_EMAIL)) {
      if (Test-Path -LiteralPath $adminFile) { $admin = Import-Clixml -LiteralPath $adminFile }
      else {
        if ((Sql "select count(*) from usuarios where platform_role='superadmin'") -ne '0') {
          throw 'Superadmin existente: informe suas credenciais no ambiente.'
        }
        $password = 'Fnx!' + [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
        $admin = [pscredential]::new('piloto-local@fisconexa.invalid',(ConvertTo-SecureString $password -AsPlainText -Force))
        & $api --user-create $admin.UserName $password
        if ($LASTEXITCODE -ne 0) { throw 'Bootstrap administrativo falhou.' }
        $admin | Export-Clixml -LiteralPath $adminFile
        $password = $null
      }
    } else {
      $admin = [pscredential]::new($env:FISCONEXA_ADMIN_EMAIL,(ConvertTo-SecureString $env:FISCONEXA_ADMIN_PASSWORD -AsPlainText -Force))
    }
  }
  $apiProcess = Start-Process -FilePath $api -PassThru -WindowStyle Hidden
  $ready = $false
  for ($attempt=0; $attempt -lt 50; $attempt++) {
    if ($apiProcess.HasExited) { throw 'API encerrou antes do smoke.' }
    try { $ready = ((ApiJson GET '/health' @{}).situacao -eq 'disponivel'); if ($ready) { break } }
    catch { Start-Sleep -Milliseconds 200 }
  }
  if (-not $ready) { throw 'API indisponivel.' }
  if (Test-Path -LiteralPath $sessionFile) {
    $session = Import-Clixml -LiteralPath $sessionFile
    if ($session.Fingerprint -ne $fingerprint -or $session.Database -ne $env:POSTGRES_DB) {
      throw 'Sessao do piloto pertence a outro certificado ou banco; nao reiniciar cursor.'
    }
  } else {
    if ($Pilot -eq 'segundo') {
      $principal = Import-Clixml -LiteralPath (Join-Path $root 'build\pilot-session.clixml')
      if ($principal.Database -ne $env:POSTGRES_DB) { throw 'Banco do ERP piloto diverge.' }
      $erp = @{erp_key=$principal.Erp.GetNetworkCredential().Password}
    } else {
    $login = ApiJson POST '/auth/login' @{} @{email=$admin.UserName;senha=$admin.GetNetworkCredential().Password}
    $oldKeys = Sql "select json_build_object('erp_id',k.organization_id,'key_id',k.id)::text from chaves_erp k join organizacoes o on o.id=k.organization_id where o.legal_name='Piloto fiscal autorizado' and k.revoked_at is null;"
    foreach ($entry in @($oldKeys)) {
      if ($entry) { $oldKey=$entry|ConvertFrom-Json; ApiJson DELETE "/admin/erps/$($oldKey.erp_id)/chaves/$($oldKey.key_id)" @{Authorization="Bearer $($login.token_acesso)"} | Out-Null }
    }
    $erp = ApiJson POST '/admin/erps' @{Authorization="Bearer $($login.token_acesso)"} @{razao_social='Piloto fiscal autorizado';rotulo_chave='Piloto'}
    }
    $body = @{
      uf=$env:FISCONEXA_TEST_SEFAZ_UF
      certificado_a1_base64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($env:FISCONEXA_TEST_PFX_PATH))
      senha_certificado_base64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($env:FISCONEXA_TEST_PFX_PASSWORD))
    }
    $company = ApiJson POST '/v1/empresas' @{Authorization="Bearer $($erp.chave_erp)";'Idempotency-Key'=('piloto-'+$fingerprint)} $body
    $body = $null
    if (-not $company.token_integracao) { throw 'Onboarding nao retornou token para o piloto.' }
    $session = [pscustomobject]@{
      Fingerprint=$fingerprint; Database=$env:POSTGRES_DB; CompanyId=$company.id_empresa
      Tenant=[pscredential]::new('tenant',(ConvertTo-SecureString $company.token_integracao -AsPlainText -Force))
      Erp=[pscredential]::new('erp',(ConvertTo-SecureString $erp.chave_erp -AsPlainText -Force))
    }
    $session | Export-Clixml -LiteralPath $sessionFile
  }
  $companyId = ([guid]$session.CompanyId).ToString()
  $tenantHeaders = @{Authorization=('Bearer '+$session.Tenant.GetNetworkCredential().Password)}
  $onboardingOk = Sql "select count(*) from empresas e where e.id='$companyId' and exists(select 1 from certificados c where c.company_id=e.id and c.revoked_at is null and octet_length(c.encrypted_certificate)>0 and octet_length(c.encrypted_password)>0) and exists(select 1 from empresas_modulos m where m.company_id=e.id and m.status='active') and exists(select 1 from empresas_organizacoes o where o.company_id=e.id) and exists(select 1 from status_monitoramento s where s.company_id=e.id) and exists(select 1 from comandos c where c.company_id=e.id);"
  if ($onboardingOk -ne '1') { throw 'Onboarding incompleto; nao executar SEFAZ.' }
  $authorizedIds = @($companyId)
  foreach ($file in 'pilot-session.clixml','pilot-session-segundo.clixml') {
    $path = Join-Path $root ('build\'+$file)
    if (Test-Path -LiteralPath $path) {
      $authorized = Import-Clixml -LiteralPath $path
      if ($authorized.Database -ne $env:POSTGRES_DB) { throw 'Banco de sessao autorizada diverge.' }
      $authorizedIds += ([guid]$authorized.CompanyId).ToString()
    }
  }
  $allowedSql = ($authorizedIds | Select-Object -Unique | ForEach-Object { "'$_'" }) -join ','
  if ((Sql "select count(*) from status_monitoramento where status='active' and company_id not in ($allowedSql)") -ne '0') {
    throw 'Existem CNPJs ativos fora dos dois pilotos autorizados; nao executar worker.'
  }
  Write-Output 'Onboarding cifrado confirmado; executando somente uma tarefa elegivel, com ciencia autorizada.'
  & $worker
  if ($LASTEXITCODE -ne 0) { throw 'Worker encerrou com falha.' }
  $monitor = ApiJson GET '/v1/monitoramento' $tenantHeaders
  $state = Sql "select json_build_object('cstat',last_cstat,'nsu',last_nsu,'falhas',failure_count,'bloqueios',blocked_count,'espera_segundos',ceil(extract(epoch from next_check_at-now())),'documentos',(select count(*) from documentos where company_id='$companyId'),'xmls',(select count(*) from documentos where company_id='$companyId' and xml_sha256 is not null),'comandos_xml',(select count(*) from comandos where company_id='$companyId' and command_type='retrieve_xml'))::text from status_monitoramento where company_id='$companyId';"
  Write-Output $state
  if (($state | ConvertFrom-Json).falhas -gt 0) {
    Write-Output 'Ciclo com falha tecnica persistida; isso nao aprova o smoke fiscal.'
  }
  $stateFile = 'build\pilot-last-state.json'
  if ($Pilot -eq 'segundo') { $stateFile = 'build\pilot-segundo-last-state.json' }
  $state | Set-Content -LiteralPath (Join-Path $root $stateFile) -Encoding UTF8
  $page = ApiJson GET '/v1/documentos?nsu=0&limite=500' $tenantHeaders
  $document = @($page.itens | Where-Object xml_disponivel | Select-Object -First 1)
  if ($document.Count -gt 0) {
    $id = ([guid]$document[0].id_documento).ToString()
    $expectedHash = Sql "select xml_sha256 from documentos where id='$id' and company_id='$companyId';"
    for ($download=0; $download -lt 2; $download++) {
      $response = Invoke-WebRequest -Uri "http://127.0.0.1:9000/v1/documentos/$id/xml" -Headers $tenantHeaders -UseBasicParsing
      $sha = [Security.Cryptography.SHA256]::Create()
      try { $actualHash = ([BitConverter]::ToString($sha.ComputeHash($response.RawContentStream.ToArray()))).Replace('-','').ToLowerInvariant() }
      finally { $sha.Dispose() }
      if ($actualHash -ne $expectedHash) { throw 'Hash do XML lido pelo ERP diverge do banco.' }
    }
    Write-Output 'XML lido duas vezes pela API/S3, com SHA-256 conferido e sem nova consulta SEFAZ.'
  }
  if ((ApiJson GET '/health' @{}).situacao -ne 'disponivel') { throw 'API ficou indisponivel apos o ciclo.' }
  Write-Output 'API disponivel. Estado e arquivos retidos; proxima execucao respeitara a janela do banco.'
} finally {
  if ($null -ne $apiProcess -and -not $apiProcess.HasExited) { Stop-Process -Id $apiProcess.Id }
}
