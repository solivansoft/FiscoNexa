param([switch]$AllowAwareness, [switch]$SkipOnboarding,
  [hashtable]$CertificatePasswords = @{}, [switch]$OnlySelectedCertificates,
  [string]$SingleCompanyId)
$ErrorActionPreference = 'Stop'
if (-not $AllowAwareness) { throw 'Autorizacao fiscal obrigatoria.' }
$root = Split-Path -Parent $PSScriptRoot
Get-Content (Join-Path $root '.env') | ForEach-Object {
  if ($_ -match '^([^#=]+)=(.*)$') { Set-Item ('Env:'+$matches[1].Trim()) $matches[2].Trim().Trim('"').Trim("'") }
}
$env:FISCONEXA_DB_HOST='127.0.0.1'
$env:FISCONEXA_DB_PORT=$env:POSTGRES_PORT
$env:FISCONEXA_DB_NAME=$env:POSTGRES_DB
$env:FISCONEXA_DB_USER=$env:POSTGRES_USER
$env:FISCONEXA_DB_PASSWORD=$env:POSTGRES_PASSWORD
$env:FISCONEXA_SEFAZ_MODE='acbr'
$env:FISCONEXA_AUTO_AWARENESS='true'
$env:FISCONEXA_WORKER_BATCH_SIZE='1'
$env:FISCONEXA_WORKER_LEASE_SECONDS='7200'
$env:FISCONEXA_WORKER_ID='piloto-lote-'+[guid]::NewGuid().ToString('N')
$env:Path=(Join-Path $root 'bin\win64')+';'+(Join-Path $root 'vendor\postgres-client\pgsql\bin')+';'+$env:Path
$sessions=@()
$sessionPath=Join-Path $root 'build\pilot-batch-session.clixml'
foreach($file in 'pilot-session.clixml','pilot-session-segundo.clixml','pilot-batch-session.clixml') {
  $path=Join-Path $root ('build\'+$file)
  if(Test-Path $path) { $sessions += @(Import-Clixml $path) }
}
foreach($session in $sessions) { if($session.Database -ne $env:POSTGRES_DB){throw 'Banco da sessao diverge.'} }
if($SingleCompanyId) {
  $SingleCompanyId=([guid]$SingleCompanyId).ToString()
  if(-not $SkipOnboarding){throw 'Tenant unico exige reutilizar onboarding.'}
  if(-not ($sessions|Where-Object CompanyId -eq $SingleCompanyId)){throw 'Tenant fora das sessoes autorizadas.'}
}
$erp=@{Authorization='Bearer '+$sessions[0].Erp.GetNetworkCredential().Password}
function Sql([string]$Query) {
  $result=& docker exec fisconexa-postgres psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB -v ON_ERROR_STOP=1 -Atc $Query
  if($LASTEXITCODE -ne 0){throw 'Verificacao PostgreSQL falhou.'}
  return $result
}
function Http([string]$Method,[string]$Path,$Headers,$Body=$null) {
  $args=@{Method=$Method;Uri=('http://127.0.0.1:9000'+$Path);Headers=$Headers;TimeoutSec=120}
  if($null -ne $Body){$args.ContentType='application/json';$args.Body=$Body|ConvertTo-Json -Compress}
  Invoke-RestMethod @args
}
$api=$null
try {
  if(Get-NetTCPConnection -LocalPort 9000 -State Listen -ErrorAction SilentlyContinue){throw 'Porta 9000 ocupada.'}
  $api=Start-Process (Join-Path $root 'bin\win64\FiscoNexa.Api.exe') -PassThru -WindowStyle Hidden
  $ready=$false
  for($i=0;$i -lt 50;$i++) {
    try { if((Http GET '/health' @{}).situacao -eq 'disponivel'){$ready=$true;break} } catch {Start-Sleep -Milliseconds 200}
  }
  if(-not $ready){throw 'API indisponivel.'}
  if($SingleCompanyId) {
    foreach($session in $sessions|Sort-Object CompanyId -Unique) {
      $moduleStatus='suspenso'
      if($session.CompanyId -eq $SingleCompanyId){$moduleStatus='ativo'}
      Http PUT ('/v1/empresas/'+$session.CompanyId+'/modulos/monitoramento') $erp @{situacao=$moduleStatus}|Out-Null
    }
    if((Sql "select count(*) from empresas_modulos where code='monitoring' and status='active' and company_id<>'$SingleCompanyId'") -ne '0'){throw 'Outro tenant ainda ativo; nao executar.'}
    Write-Output 'Somente o tenant selecionado permanece com monitoramento ativo.'
  }
  $report=@()
  if ($OnlySelectedCertificates) {
    $reportPath=Join-Path $root 'build\pilot-batch-onboarding.json'
    if(Test-Path $reportPath){$report=@(Get-Content $reportPath -Raw|ConvertFrom-Json)}
  }
  if(-not $SkipOnboarding) {
    $seen=@{}
    foreach($file in Get-ChildItem -LiteralPath 'I:\Meu Drive\Suporte\Fiscal\Certificados' -Filter '*.pfx' -File) {
      if($OnlySelectedCertificates -and -not $CertificatePasswords.ContainsKey($file.Name)){continue}
      $report=@($report|Where-Object { $_.file -ne $file.Name })
      $certificatePassword=$env:FISCONEXA_TEST_PFX_PASSWORD
      if($CertificatePasswords.ContainsKey($file.Name)){$certificatePassword=$CertificatePasswords[$file.Name]}
      $fingerprint=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
      $cert=$null
      try {
        $cert=[Security.Cryptography.X509Certificates.X509Certificate2]::new($file.FullName,$certificatePassword,[Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
      } catch {Write-Output 'Certificado nao abriu com a senha fornecida; ignorado.'; $report+=@{file=$file.Name;status='senha_ou_formato_invalido'};continue}
      try {
        if($cert.NotAfter -lt [datetime]::Now -or $cert.NotBefore -gt [datetime]::Now){$report+=@{file=$file.Name;status='fora_da_validade'};Write-Output 'Certificado fora da validade; ignorado.';continue}
        $cnpj=[regex]::Match($cert.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false),':(\d{14})(?:$|\D)').Groups[1].Value
        if(-not $cnpj){$report+=@{file=$file.Name;status='identidade_nao_identificada'};continue}
        if($seen.ContainsKey($cnpj)){$report+=@{file=$file.Name;status='cnpj_repetido'};continue}
        $seen[$cnpj]=$true
      } finally {$cert.Dispose()}
      $known=@($sessions|Where-Object Fingerprint -eq $fingerprint|Select-Object -First 1)
      $body=@{certificado_a1_base64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName));senha_certificado_base64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($certificatePassword))}
      if($known.Count -gt 0){
        $knownId=([guid]$known[0].CompanyId).ToString()
        $body.uf=Sql "select state from empresas where id='$knownId';"
      }
      $headers=@{Authorization=$erp.Authorization;'Idempotency-Key'=('piloto-'+$fingerprint)}
      try {
        $result=Http POST '/v1/empresas' $headers $body
        if($result.token_integracao) {
          $sessions += [pscustomobject]@{Fingerprint=$fingerprint;Database=$env:POSTGRES_DB;CompanyId=$result.id_empresa;Tenant=[pscredential]::new('tenant',(ConvertTo-SecureString $result.token_integracao -AsPlainText -Force));Erp=$sessions[0].Erp}
          $sessions|Export-Clixml $sessionPath
        } elseif(-not ($sessions|Where-Object CompanyId -eq $result.id_empresa)) {throw 'Tenant existente sem credencial local; nao executar fiscal.'}
        $report+=@{file=$file.Name;status='cadastrado';company_id=$result.id_empresa;uf=$result.uf;cadastro_disponivel=$result.cadastro_disponivel}
        Write-Output ('Cadastro HTTP confirmado; UF='+$result.uf+'; ReceitaWS='+$result.cadastro_disponivel)
      } catch {
        $code='falha_http'
        if($_.ErrorDetails.Message){try {$code=($_.ErrorDetails.Message|ConvertFrom-Json).erro.codigo}catch{}}
        $report+=@{file=$file.Name;status=$code}
        Write-Output ('Cadastro pendente: '+$code)
      } finally {$body=$null;$certificatePassword=$null}
      $report|ConvertTo-Json -Depth 5|Set-Content (Join-Path $root 'build\pilot-batch-onboarding.json') -Encoding UTF8
      Start-Sleep -Seconds 21
    }
    $report|ConvertTo-Json -Depth 5|Set-Content (Join-Path $root 'build\pilot-batch-onboarding.json') -Encoding UTF8
  }
  $ids=($sessions|ForEach-Object{ "'"+([guid]$_.CompanyId).ToString()+"'" }|Select-Object -Unique)-join ','
  if((Sql "select count(*) from status_monitoramento where status='active' and company_id not in ($ids)") -ne '0'){throw 'CNPJ ativo fora das sessoes autorizadas.'}
  # Orquestracao limitada: o executavel decide elegibilidade e preserva cada prazo.
  for($cycle=0;$cycle -lt 20;$cycle++) {
    $due=Sql "select count(*) from status_monitoramento where status='active' and (next_check_at is null or next_check_at<=now()) and (lease_until is null or lease_until<=now());"
    if([int]$due -eq 0 -and -not $SingleCompanyId){break}
    & (Join-Path $root 'bin\win64\FiscoNexa.Worker.exe')
    if($LASTEXITCODE -ne 0){throw 'Worker falhou.'}
    $stats=Sql "select json_build_object('cstat',last_cstat,'empresas',count(*),'proxima_utc',min(next_check_at) at time zone 'UTC') from status_monitoramento group by last_cstat;"
    $stats|Write-Output
    if($SingleCompanyId){break}
  }
  foreach($session in $sessions|Sort-Object CompanyId -Unique) {
    $headers=@{Authorization='Bearer '+$session.Tenant.GetNetworkCredential().Password}
    $page=Http GET '/v1/documentos?nsu=0&limite=500' $headers
    $doc=$page.itens|Where-Object xml_disponivel|Select-Object -First 1
    if($doc) {
      $id=([guid]$doc.id_documento).ToString();$companyId=([guid]$session.CompanyId).ToString()
      $hash=Sql "select xml_sha256 from documentos where id='$id' and company_id='$companyId';"
      for($i=0;$i -lt 2;$i++) {
        $response=Invoke-WebRequest -Uri "http://127.0.0.1:9000/v1/documentos/$id/xml" -Headers $headers -UseBasicParsing
        $sha=[Security.Cryptography.SHA256]::Create()
        try {$actual=([BitConverter]::ToString($sha.ComputeHash($response.RawContentStream.ToArray()))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
        if($actual -ne $hash){throw 'Hash XML divergente.'}
      }
      Write-Output 'XML real validado: duas leituras pelo token ERP com hash confirmado.'
    }
  }
  $state=Sql "select json_build_object('company_id',s.company_id,'cstat',last_cstat,'nsu',last_nsu,'falhas',failure_count,'proxima_utc',next_check_at at time zone 'UTC','documentos',(select count(*) from documentos d where d.company_id=s.company_id),'xmls',(select count(*) from documentos d where d.company_id=s.company_id and xml_sha256 is not null)) from status_monitoramento s;"
  $state|Set-Content (Join-Path $root 'build\pilot-batch-last-state.jsonl') -Encoding UTF8
  Write-Output 'Lote encerrado; resultados locais preservados. Nenhum prazo foi antecipado.'
} finally {if($api -and -not $api.HasExited){Stop-Process -Id $api.Id}}
