param(
  [string]$ApiExecutable = "$(Join-Path $PSScriptRoot '..\bin\win64\FiscoNexa.Api.exe')"
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pfxPath = Join-Path ([IO.Path]::GetTempPath()) ('fisconexa-e2e-' + [guid]::NewGuid().ToString('N') + '.pfx')
$pfxPassword = 'FiscoNexa-E2E-Test-Only-2026!'
$process = $null
$database = 'fisconexa_e2e_' + [guid]::NewGuid().ToString('N')

Get-Content -LiteralPath (Join-Path $root '.env') | ForEach-Object {
  if ($_ -match '^([^#=]+)=(.*)$') { Set-Item -Path ('Env:' + $matches[1].Trim()) -Value $matches[2] }
}
foreach ($name in 'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_REGION', 'FISCONEXA_KMS_KEY_ID', 'S3_XML_BUCKET') {
  if ([string]::IsNullOrWhiteSpace((Get-Item "Env:$name" -ErrorAction SilentlyContinue).Value)) {
    throw "Variavel obrigatoria ausente para E2E ERP: $name"
  }
}
$env:FISCONEXA_DB_HOST = '127.0.0.1'
$env:FISCONEXA_DB_PORT = $env:POSTGRES_PORT
$env:FISCONEXA_DB_NAME = $database
$env:FISCONEXA_DB_USER = $env:POSTGRES_USER
$env:FISCONEXA_DB_PASSWORD = $env:POSTGRES_PASSWORD
$env:FISCONEXA_API_URL = 'http://127.0.0.1:9000'
$env:FISCONEXA_TEST_PFX_PATH = $pfxPath
$env:FISCONEXA_TEST_PFX_PASSWORD = $pfxPassword
$env:Path = (Join-Path $root 'vendor\postgres-client\pgsql\bin') + ';' + $env:Path

$cnpj = '97' + (Get-Date -Format 'yyMMddHHmmss')
$subject = New-Object Security.Cryptography.X509Certificates.X500DistinguishedName("CN=FiscoNexa E2E,OID.2.16.76.1.3.3=$cnpj")
$rsa = [Security.Cryptography.RSA]::Create(2048)
try {
  $request = New-Object Security.Cryptography.X509Certificates.CertificateRequest($subject, $rsa, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
  $certificate = $request.CreateSelfSigned([datetimeoffset]::Now.AddDays(-1), [datetimeoffset]::Now.AddDays(30))
  try { [IO.File]::WriteAllBytes($pfxPath, $certificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $pfxPassword)) }
  finally { $certificate.Dispose() }
} finally { $rsa.Dispose() }

try {
  & docker exec fisconexa-postgres createdb -U $env:POSTGRES_USER $database
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar banco isolado E2E.' }
  & cmd /c (Join-Path $root 'scripts\build-api.bat') win64
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar API.' }
  & cmd /c (Join-Path $root 'scripts\test-erp-end-to-end.bat')
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar E2E ERP.' }
  $process = Start-Process -FilePath $ApiExecutable -PassThru -WindowStyle Hidden
  $deadline = (Get-Date).AddSeconds(10)
  do {
    try { if ((Invoke-RestMethod -Uri "$env:FISCONEXA_API_URL/health" -TimeoutSec 1).situacao -eq 'disponivel') { break } }
    catch { Start-Sleep -Milliseconds 200 }
  } while ((Get-Date) -lt $deadline)
  if ($null -eq $process -or $process.HasExited) { throw 'API encerrou antes do E2E.' }
  & (Join-Path $root 'bin\tests\win64\FiscoNexa.ErpEndToEndIntegration.exe')
  if ($LASTEXITCODE -ne 0) { throw 'E2E ERP falhou.' }
} finally {
  if (($null -ne $process) -and (-not $process.HasExited)) { Stop-Process -Id $process.Id -Force }
  if (Test-Path -LiteralPath $pfxPath) { Remove-Item -LiteralPath $pfxPath -Force }
  & docker exec fisconexa-postgres dropdb --if-exists -U $env:POSTGRES_USER $database
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao remover banco isolado E2E.' }
}
