param(
  [string]$Executable = "$(Join-Path $PSScriptRoot '..\bin\win64\FiscoNexa.Api.exe')",
  [switch]$UseCurrentEnvironment
)

$ErrorActionPreference = 'Stop'

function Load-DevelopmentEnvironment {
  param([string]$Root)

  $envFile = Join-Path $Root '.env'
  if (-not (Test-Path -LiteralPath $envFile)) {
    throw 'Arquivo .env ausente. Execute scripts\dev-up.bat primeiro.'
  }

  Get-Content -LiteralPath $envFile | ForEach-Object {
    if ($_ -match '^([^#=]+)=(.*)$') {
      Set-Item -Path ('Env:' + $matches[1].Trim()) -Value $matches[2]
    }
  }

  $env:FISCONEXA_DB_HOST = '127.0.0.1'
  $env:FISCONEXA_DB_PORT = $env:POSTGRES_PORT
  $env:FISCONEXA_DB_NAME = $env:POSTGRES_DB
  $env:FISCONEXA_DB_USER = $env:POSTGRES_USER
  $env:FISCONEXA_DB_PASSWORD = $env:POSTGRES_PASSWORD
  $postgresClientBin = Join-Path $Root 'vendor\postgres-client\pgsql\bin'
  $env:Path = $postgresClientBin + ';' + $env:Path
}

function Invoke-PostgresSql {
  param([string]$Sql)

  $output = & docker exec fisconexa-postgres psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB -v ON_ERROR_STOP=1 -Atc $Sql
  if ($LASTEXITCODE -ne 0) {
    throw 'Falha ao preparar ou limpar a fixture PostgreSQL.'
  }
  return $output
}

if (-not (Test-Path -LiteralPath $Executable)) {
  throw "Executavel nao encontrado: $Executable"
}

$root = Split-Path -Parent $PSScriptRoot
if (-not $UseCurrentEnvironment) { Load-DevelopmentEnvironment -Root $root }

$suffix = Get-Date -Format 'yyMMddHHmmss'
$cnpjOne = '99' + $suffix
$cnpjTwo = '98' + $suffix
$token = 'fnx_test_' + [guid]::NewGuid().ToString('N')
$accessKeyOne = '35' + ('1' * 42)
$accessKeyTwo = '35' + ('2' * 42)
$sql = @"
with company_one as (
  insert into empresas (cnpj, state, legal_name)
  values ('$cnpjOne', 'PA', 'Empresa Token') returning id
), company_two as (
  insert into empresas (cnpj, state, legal_name)
  values ('$cnpjTwo', 'PA', 'Empresa Estranha') returning id
), integration as (
  insert into integracoes (company_id, display_name, api_token_hash)
  select id, 'ERP Smoke', encode(digest('$token', 'sha256'), 'hex') from company_one
)
insert into documentos (company_id, access_key, document_type, issuer_cnpj, nome_emitente, tipo_operacao, situacao_fiscal, total_amount, status)
select id, '$accessKeyOne', 'nfe', '12345678000190', 'Emitente Smoke', 'entrada', 'autorizada', 100.00, 'xml_available' from company_one
union all
select id, '$accessKeyTwo', 'nfe', '12345678000190', 'Emitente Estranho', 'saida', 'autorizada', 200.00, 'xml_available' from company_two;
"@

$process = $null
try {
  $process = Start-Process -FilePath $Executable -PassThru -WindowStyle Hidden
  $deadline = (Get-Date).AddSeconds(10)
  do {
    try {
      $response = Invoke-RestMethod -Uri 'http://127.0.0.1:9000/health' -TimeoutSec 1
      if ($response.situacao -eq 'disponivel') { break }
    } catch {
      Start-Sleep -Milliseconds 200
    }
  } while ((Get-Date) -lt $deadline)
  if (($null -eq $process) -or $process.HasExited -or ($response.situacao -ne 'disponivel')) {
    throw 'API nao respondeu saude antes da fixture de integracao.'
  }

  Invoke-PostgresSql -Sql $sql | Out-Null
  Invoke-PostgresSql -Sql "insert into status_monitoramento (company_id, status, interval_minutes, next_check_at, last_cstat) select id, 'active', 60, now() + interval '1 hour', 137 from empresas where cnpj = '$cnpjOne';" | Out-Null
  Invoke-PostgresSql -Sql "insert into certificados (company_id, encryption_key_ref, encrypted_data_key, encrypted_certificate, certificate_nonce, certificate_tag, encrypted_password, password_nonce, password_tag, sha256, valid_until) select id, 'kms-smoke', decode('01','hex'), decode('02','hex'), decode('03','hex'), decode('04','hex'), decode('05','hex'), decode('06','hex'), decode('07','hex'), 'expired-smoke-$cnpjOne', current_date - 1 from empresas where cnpj = '$cnpjOne';" | Out-Null
  $fixtureCount = Invoke-PostgresSql -Sql "select count(*) from documentos d join integracoes i on i.company_id = d.company_id where i.api_token_hash = encode(digest('$token', 'sha256'), 'hex');"
  if ($fixtureCount -ne '1') {
    throw "Fixture ERP invalida: esperava um documento do tenant, recebeu $fixtureCount."
  }
  try {
    Invoke-WebRequest -Uri 'http://127.0.0.1:9000/v1/documentos' -TimeoutSec 2 | Out-Null
    throw 'Integracao sem token foi aceita.'
  } catch {
    if ($_.Exception.Response.StatusCode.value__ -ne 401) {
      throw
    }
  }
  try {
    Invoke-WebRequest -Uri 'http://127.0.0.1:9000/v1/documentos/00000000-0000-0000-0000-000000000000/xml' -TimeoutSec 2 | Out-Null
    throw 'Download XML sem token foi aceito.'
  } catch {
    if ($_.Exception.Response.StatusCode.value__ -ne 401) { throw }
  }

  $headers = @{ Authorization = "Bearer $token" }
  try {
    Invoke-WebRequest -Uri 'http://127.0.0.1:9000/v1/monitoramento' -TimeoutSec 2 | Out-Null
    throw 'Monitoramento sem token foi aceito.'
  } catch {
    if ($_.Exception.Response.StatusCode.value__ -ne 401) {
      throw
    }
  }

  $monitoring = Invoke-RestMethod -Uri 'http://127.0.0.1:9000/v1/monitoramento' -Headers $headers -TimeoutSec 2
  if (($monitoring.situacao -ne 'ativo') -or ($monitoring.intervalo_minutos -ne 60) -or ($monitoring.ultimo_cstat -ne 137) -or ($monitoring.situacao_certificado -ne 'vencido')) {
    throw ('Estado de monitoramento divergente: ' + ($monitoring | ConvertTo-Json -Compress))
  }

  Stop-Process -Id $process.Id -Force
  $process.WaitForExit()
  $process = Start-Process -FilePath $Executable -PassThru -WindowStyle Hidden
  $deadline = (Get-Date).AddSeconds(10)
  do {
    try {
      $response = Invoke-RestMethod -Uri 'http://127.0.0.1:9000/health' -TimeoutSec 1
      if ($response.situacao -eq 'disponivel') {
        break
      }
    } catch {
      Start-Sleep -Milliseconds 200
    }
  } while ((Get-Date) -lt $deadline)
  if ($response.situacao -ne 'disponivel') {
    throw 'API nao respondeu saude apos reinicio.'
  }
  $recoveredMonitoring = Invoke-RestMethod -Uri 'http://127.0.0.1:9000/v1/monitoramento' -Headers $headers -TimeoutSec 2
  if (($recoveredMonitoring.situacao -ne 'ativo') -or ($recoveredMonitoring.ultimo_cstat -ne 137) -or ($recoveredMonitoring.situacao_certificado -ne 'vencido')) {
    throw 'Estado de monitoramento nao foi recuperado apos reinicio da API.'
  }

  $documents = Invoke-RestMethod -Uri 'http://127.0.0.1:9000/v1/documentos?nsu=0&limite=100' -Headers $headers -TimeoutSec 2
  $documentItems = @($documents.itens)
  if (($documentItems.Count -ne 1) -or ($documentItems[0].chave_acesso -ne $accessKeyOne) -or ($documentItems[0].nome_emitente -ne 'Emitente Smoke') -or ($documentItems[0].tipo_operacao -ne 'entrada') -or ($documentItems[0].situacao_fiscal -ne 'autorizada') -or ($documentItems[0].nsu -le 0) -or ($documents.ultimo_nsu -ne $documentItems[0].nsu)) {
    throw "Token ERP recebeu pagina invalida: count=$($documentItems.Count), chave=$($documentItems[0].chave_acesso), emitente=$($documentItems[0].nome_emitente), operacao=$($documentItems[0].tipo_operacao), fiscal=$($documentItems[0].situacao_fiscal), xml=$($documentItems[0].xml_disponivel), nsu=$($documentItems[0].nsu), ultimo=$($documents.ultimo_nsu)."
  }
  $resumed = Invoke-RestMethod -Uri ("http://127.0.0.1:9000/v1/documentos?nsu=" + $documents.ultimo_nsu + '&limite=100') -Headers $headers -TimeoutSec 2
  if ((@($resumed.itens).Count -ne 0) -or ($resumed.ultimo_nsu -ne $documents.ultimo_nsu)) {
    throw 'Cursor de documentos nao retomou de forma idempotente.'
  }
  $xmlUrl = 'http://127.0.0.1:9000/v1/documentos/' + $documentItems[0].id_documento + '/xml'
  $pending = Invoke-WebRequest -Uri $xmlUrl -Headers $headers -UseBasicParsing
  if ($pending.StatusCode -ne 202) { throw 'XML pendente nao retornou 202.' }
  $command = ($pending.Content | ConvertFrom-Json).id_comando
  $replay = Invoke-RestMethod -Uri $xmlUrl -Headers $headers
  if ($replay.id_comando -ne $command) { throw 'Pedido repetido duplicou comando.' }
  $foreignId = Invoke-PostgresSql -Sql "select id from documentos where access_key='$accessKeyTwo' and company_id in (select id from empresas where cnpj='$cnpjTwo');"
  function Assert-HttpStatus([string]$Url, [hashtable]$Headers, [int]$Expected) {
    try { $actual = (Invoke-WebRequest -Uri $Url -Headers $Headers -UseBasicParsing).StatusCode }
    catch { if ($null -eq $_.Exception.Response) { throw }; $actual = $_.Exception.Response.StatusCode.value__ }
    if ($actual -ne $Expected) { throw "HTTP inesperado: $actual, esperado $Expected em $Url" }
  }
  Assert-HttpStatus "http://127.0.0.1:9000/v1/documentos/$foreignId/xml" $headers 404
  Assert-HttpStatus 'http://127.0.0.1:9000/v1/documentos/invalido/xml' $headers 404
  Assert-HttpStatus 'http://127.0.0.1:9000/v1/documentos?limite=501' $headers 400
  Assert-HttpStatus 'http://127.0.0.1:9000/v1/documentos?nsu=abc' $headers 400
  $rejectedAccessKey = '35' + ('3' * 42)
  $rejectedId = @((Invoke-PostgresSql -Sql "insert into documentos (company_id, access_key, document_type, issuer_cnpj, total_amount, status, ciencia_cstat) select id, '$rejectedAccessKey', 'nfe', '12345678000190', 1.00, 'located', 596 from empresas where cnpj = '$cnpjOne' returning id::text;"))[0]
  Assert-HttpStatus "http://127.0.0.1:9000/v1/documentos/$rejectedId/xml" $headers 409
  if ((Invoke-PostgresSql -Sql "select count(*) from comandos where company_id in (select id from empresas where cnpj = '$cnpjOne') and payload->>'access_key' = '$rejectedAccessKey';") -ne '0') {
    throw 'Documento com ciencia final recusada criou consulta pontual.'
  }
  Assert-HttpStatus $xmlUrl @{ Authorization='Bearer invalido' } 401
  Invoke-PostgresSql -Sql "update integracoes set scopes=jsonb_build_array() where api_token_hash=encode(digest('$token','sha256'),'hex');" | Out-Null
  Assert-HttpStatus $xmlUrl $headers 403
  Assert-HttpStatus 'http://127.0.0.1:9000/v1/documentos' $headers 403
  Invoke-PostgresSql -Sql "update integracoes set revoked_at=now() where api_token_hash=encode(digest('$token','sha256'),'hex');" | Out-Null
  Assert-HttpStatus $xmlUrl $headers 401
  Assert-HttpStatus 'http://127.0.0.1:9000/v1/documentos' $headers 401

  Write-Output 'Smoke ERP aprovado: token isolado le documentos e recupera monitoramento apos reinicio.'
} finally {
  if (($null -ne $process) -and (-not $process.HasExited)) {
    Stop-Process -Id $process.Id -Force
  }

  Invoke-PostgresSql -Sql "delete from empresas where cnpj in ('$cnpjOne', '$cnpjTwo');" | Out-Null
}
