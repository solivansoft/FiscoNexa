param([string]$Executable = "$(Join-Path $PSScriptRoot '..\bin\win64\FiscoNexa.Api.exe')")
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Get-Content (Join-Path $root '.env') | ForEach-Object { if ($_ -match '^([^#=]+)=(.*)$') { Set-Item ('Env:' + $matches[1].Trim()) $matches[2] } }
$env:FISCONEXA_DB_HOST='127.0.0.1'; $env:FISCONEXA_DB_PORT=$env:POSTGRES_PORT; $env:FISCONEXA_DB_NAME=$env:POSTGRES_DB; $env:FISCONEXA_DB_USER=$env:POSTGRES_USER; $env:FISCONEXA_DB_PASSWORD=$env:POSTGRES_PASSWORD
function Sql([string]$value) { $r = & docker exec fisconexa-postgres psql -q -U $env:POSTGRES_USER -d $env:POSTGRES_DB -v ON_ERROR_STOP=1 -Atc $value; if ($LASTEXITCODE -ne 0) { throw 'Falha SQL.' }; $r }
& cmd /c (Join-Path $root 'scripts\test-s3.bat'); if ($LASTEXITCODE -ne 0) { throw 'Falha build S3.' }
$s3 = & (Join-Path $root 'bin\tests\win64\FiscoNexa.S3Integration.exe')
if ($LASTEXITCODE -ne 0 -or $s3 -notmatch 'Smoke S3 aprovado: (\S+) ([0-9a-f]+)') { throw 'Falha no objeto S3 temporario.' }
$objectKey=$matches[1]; $sha=$matches[2]; $suffix=Get-Date -Format 'yyMMddHHmmss'; $cnpj='97'+$suffix; $token='fnx-xml-'+[guid]::NewGuid().ToString('N'); $companyId=''; $process=$null
try {
  $companyId=Sql "insert into empresas (cnpj,state,legal_name) values ('$cnpj','PA','Smoke XML') returning id::text"
  Sql "insert into integracoes (company_id,display_name,api_token_hash) values ('$companyId','Smoke',encode(digest('$token','sha256'),'hex'))" | Out-Null
  $documentId=Sql "insert into documentos (company_id,access_key,document_type,status,xml_object_key,xml_sha256) values ('$companyId','35111111111111111111111111111111111111111111','nfe','xml_available','$objectKey','$sha') returning id::text"
  $process=Start-Process -FilePath $Executable -PassThru -WindowStyle Hidden
  $deadline=(Get-Date).AddSeconds(10); do { try { Invoke-RestMethod 'http://127.0.0.1:9000/health' -TimeoutSec 1 | Out-Null; break } catch { Start-Sleep -Milliseconds 200 } } while((Get-Date)-lt $deadline)
  $xml=Invoke-RestMethod -Uri "http://127.0.0.1:9000/v1/documentos/$documentId/xml" -Headers @{Authorization="Bearer $token"} -TimeoutSec 5
  if ($xml.'fisconexa-smoke' -ne 'xml-assinado') { throw 'Rota ERP nao devolveu XML do S3.' }
  Write-Output 'Smoke ERP XML/S3 aprovado.'
} finally { if($process -and -not $process.HasExited){Stop-Process -Id $process.Id -Force}; if($companyId){Sql "delete from empresas where id='$companyId'" | Out-Null} }
