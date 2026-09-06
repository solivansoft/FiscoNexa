$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$env:Path = (Join-Path $root 'vendor\postgres-client\pgsql\bin') + ';' + $env:Path
$tempPath = Join-Path ([IO.Path]::GetTempPath()) ('fisconexa-certificate-' + [guid]::NewGuid().ToString('N') + '.pfx')
$password = 'FiscoNexa-Test-Only-2026!'
$cnpj = '12345678000190'

try {
  $subject = New-Object Security.Cryptography.X509Certificates.X500DistinguishedName("CN=FiscoNexa Test,OID.2.16.76.1.3.3=$cnpj")
  $rsa = [Security.Cryptography.RSA]::Create(2048)
  try {
    $request = New-Object Security.Cryptography.X509Certificates.CertificateRequest($subject, $rsa, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $certificate = $request.CreateSelfSigned([datetimeoffset]::Now.AddDays(-1), [datetimeoffset]::Now.AddDays(30))
    try {
      [IO.File]::WriteAllBytes($tempPath, $certificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $password))
    } finally {
      $certificate.Dispose()
    }
  } finally {
    $rsa.Dispose()
  }

  $env:FISCONEXA_TEST_PFX_PATH = $tempPath
  $env:FISCONEXA_TEST_PFX_PASSWORD = $password
  $env:FISCONEXA_TEST_CNPJ = $cnpj
  & cmd /c (Join-Path $root 'scripts\test-certificate.bat')
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar o smoke de certificado.' }
  & (Join-Path $root 'bin\tests\win64\FiscoNexa.CertificateIntegration.exe')
  if ($LASTEXITCODE -ne 0) { throw 'Smoke de certificado falhou.' }
} finally {
  if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
}
