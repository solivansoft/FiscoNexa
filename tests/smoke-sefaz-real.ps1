$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root '.env'
if (-not (Test-Path -LiteralPath $envFile)) {
  throw 'Arquivo .env ausente.'
}
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

foreach ($name in 'FISCONEXA_TEST_PFX_PATH', 'FISCONEXA_TEST_PFX_PASSWORD',
  'FISCONEXA_TEST_SEFAZ_UF', 'FISCONEXA_SEFAZ_REAL_CONFIRMATION') {
  if ([string]::IsNullOrWhiteSpace((Get-Item "Env:$name" -ErrorAction SilentlyContinue).Value)) {
    throw "Variavel obrigatoria ausente: $name"
  }
}
if ($env:FISCONEXA_SEFAZ_REAL_CONFIRMATION -ne 'YES') {
  throw 'Confirme explicitamente com FISCONEXA_SEFAZ_REAL_CONFIRMATION=YES.'
}
$opensslRuntime = $env:FISCONEXA_OPENSSL_RUNTIME_DIR
if (-not [string]::IsNullOrWhiteSpace($opensslRuntime)) {
  $runtimeCrypto = Join-Path $opensslRuntime 'bin\libcrypto-3-x64.dll'
  $runtimeSsl = Join-Path $opensslRuntime 'bin\libssl-3-x64.dll'
  $runtimeModules = Join-Path $opensslRuntime 'lib\ossl-modules'
  if (-not (Test-Path -LiteralPath $runtimeCrypto)) {
    throw "libcrypto-3-x64.dll ausente em FISCONEXA_OPENSSL_RUNTIME_DIR: $opensslRuntime"
  }
  if (-not (Test-Path -LiteralPath $runtimeSsl)) {
    throw "libssl-3-x64.dll ausente em FISCONEXA_OPENSSL_RUNTIME_DIR: $opensslRuntime"
  }
  if (-not (Test-Path -LiteralPath (Join-Path $runtimeModules 'legacy.dll'))) {
    throw "legacy.dll ausente em FISCONEXA_OPENSSL_RUNTIME_DIR: $opensslRuntime"
  }
  $env:OPENSSL_MODULES = $runtimeModules
}

& cmd /c (Join-Path $root 'scripts\test-sefaz-real.bat') win64
if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar o teste real da SEFAZ.' }

if (-not [string]::IsNullOrWhiteSpace($opensslRuntime)) {
  Copy-Item -LiteralPath (Join-Path $opensslRuntime 'bin\libcrypto-3-x64.dll') `
    -Destination (Join-Path $root 'bin\tests\win64\libcrypto-3-x64.dll') -Force
  Copy-Item -LiteralPath (Join-Path $opensslRuntime 'bin\libssl-3-x64.dll') `
    -Destination (Join-Path $root 'bin\tests\win64\libssl-3-x64.dll') -Force
  $moduleDestination = Join-Path $root 'bin\tests\win64\ossl-modules'
  New-Item -ItemType Directory -Path $moduleDestination -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $runtimeModules 'legacy.dll') `
    -Destination (Join-Path $moduleDestination 'legacy.dll') -Force
  $env:Path = (Join-Path $opensslRuntime 'bin') + ';' + $env:Path
}
$env:Path = (Join-Path $root 'vendor\postgres-client\pgsql\bin') + ';' + $env:Path
& (Join-Path $root 'bin\tests\win64\FiscoNexa.SefazRealIntegration.exe')
if ($LASTEXITCODE -ne 0) { throw 'Teste real da SEFAZ falhou.' }
