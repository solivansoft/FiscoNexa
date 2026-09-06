$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Get-Content (Join-Path $root '.env') | ForEach-Object {
  if ($_ -match '^([^#=]+)=(.*)$') { Set-Item ('Env:' + $matches[1].Trim()) $matches[2] }
}
foreach ($name in 'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_REGION', 'S3_XML_BUCKET') {
  if ([string]::IsNullOrWhiteSpace((Get-Item "Env:$name" -ErrorAction SilentlyContinue).Value)) {
    throw "Variavel obrigatoria ausente para smoke S3: $name"
  }
}
& cmd /c (Join-Path $root 'scripts\test-s3.bat')
if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar smoke S3.' }
& (Join-Path $root 'bin\tests\win64\FiscoNexa.S3Integration.exe')
if ($LASTEXITCODE -ne 0) { throw 'Smoke S3 falhou.' }
