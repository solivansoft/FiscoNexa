$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

Get-Content -LiteralPath (Join-Path $root '.env') | ForEach-Object {
  if ($_ -match '^([^#=]+)=(.*)$') {
    Set-Item -Path ('Env:' + $matches[1].Trim()) -Value $matches[2]
  }
}
if (-not $env:AWS_ACCESS_KEY_ID) {
  $env:AWS_ACCESS_KEY_ID = $env:S3_ACCESS_KEY
}
if (-not $env:AWS_SECRET_ACCESS_KEY) {
  $env:AWS_SECRET_ACCESS_KEY = $env:S3_SECRECT_KEY
}
if (-not $env:AWS_REGION) {
  $env:AWS_REGION = 'sa-east-1'
}

& cmd /c (Join-Path $root 'scripts\test-kms.bat')
if ($LASTEXITCODE -ne 0) {
  throw 'Falha ao compilar o smoke KMS.'
}

& (Join-Path $root 'bin\tests\win64\FiscoNexa.KmsIntegration.exe')
if ($LASTEXITCODE -ne 0) {
  throw 'Smoke KMS falhou.'
}
