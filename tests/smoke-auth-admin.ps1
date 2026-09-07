param(
  [string]$Executable = "$(Join-Path $PSScriptRoot '..\bin\win64\FiscoNexa.Api.exe')"
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root '.env'
$database = 'fisconexa_auth_' + [guid]::NewGuid().ToString('N').Substring(0, 12)
$email = 'admin-' + [guid]::NewGuid().ToString('N') + '@example.test'
$password = 'Smoke-Only-Admin-2026!'
$process = $null

Get-Content -LiteralPath $envFile | ForEach-Object {
  if ($_ -match '^([^#=]+)=(.*)$') { Set-Item -Path ('Env:' + $matches[1].Trim()) -Value $matches[2] }
}
$env:FISCONEXA_DB_HOST = '127.0.0.1'
$env:FISCONEXA_DB_PORT = $env:POSTGRES_PORT
$env:FISCONEXA_DB_NAME = $database
$env:FISCONEXA_DB_USER = $env:POSTGRES_USER
$env:FISCONEXA_DB_PASSWORD = $env:POSTGRES_PASSWORD
$postgresBin = Join-Path $root 'vendor\postgres-client\pgsql\bin'
$createdb = Join-Path $postgresBin 'createdb.exe'
$dropdb = Join-Path $postgresBin 'dropdb.exe'
$psql = Join-Path $postgresBin 'psql.exe'
if (-not (Test-Path -LiteralPath $createdb)) { throw 'createdb.exe ausente.' }
$env:PGPASSWORD = $env:FISCONEXA_DB_PASSWORD
$env:Path = $postgresBin + ';' + $env:Path

try {
  & $createdb -h $env:FISCONEXA_DB_HOST -p $env:FISCONEXA_DB_PORT -U $env:FISCONEXA_DB_USER $database
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar banco temporario.' }
  & $Executable --user-create $email $password
  if ($LASTEXITCODE -ne 0) { throw 'Bootstrap do superadmin falhou.' }
  $process = Start-Process -FilePath $Executable -PassThru -WindowStyle Hidden
  $deadline = (Get-Date).AddSeconds(10)
  do {
    try { Invoke-RestMethod -Uri 'http://127.0.0.1:9000/health' -TimeoutSec 1 | Out-Null; break } catch { Start-Sleep -Milliseconds 200 }
  } while ((Get-Date) -lt $deadline)

  try { Invoke-WebRequest -Uri 'http://127.0.0.1:9000/administracao/erps' -Method Post -ContentType 'application/json' -Body '{}' -UseBasicParsing | Out-Null; throw 'Admin sem Bearer foi aceito.' } catch { if ($_.Exception.Response.StatusCode.value__ -ne 401) { throw } }
  $login = Invoke-RestMethod -Uri 'http://127.0.0.1:9000/autenticacao/entrar' -Method Post -ContentType 'application/json' -Body (@{email=$email;senha=$password}|ConvertTo-Json -Compress)
  if ([string]::IsNullOrWhiteSpace($login.token_acesso) -or [string]::IsNullOrWhiteSpace($login.token_renovacao)) { throw 'Login nao retornou par de tokens.' }
  $headers = @{ Authorization = "Bearer $($login.token_acesso)" }
  $erp = Invoke-RestMethod -Uri 'http://127.0.0.1:9000/administracao/erps' -Method Post -Headers $headers -ContentType 'application/json' -Body (@{razao_social='ERP Smoke';rotulo_chave='smoke'}|ConvertTo-Json -Compress)
  if ([string]::IsNullOrWhiteSpace($erp.chave_erp)) { throw 'Cadastro do ERP nao retornou a chave unica.' }
  try { Invoke-WebRequest -Uri "http://127.0.0.1:9000/administracao/erps/$($erp.id_erp)/chaves" -Method Post -ContentType 'application/json' -Body '{}' -UseBasicParsing | Out-Null; throw 'Rotacao sem Bearer foi aceita.' } catch { if ($_.Exception.Response.StatusCode.value__ -ne 401) { throw } }
  $rotated = Invoke-RestMethod -Uri "http://127.0.0.1:9000/administracao/erps/$($erp.id_erp)/chaves" -Method Post -Headers $headers -ContentType 'application/json' -Body (@{rotulo_chave='rotated'}|ConvertTo-Json -Compress)
  if ([string]::IsNullOrWhiteSpace($rotated.chave_erp)) { throw 'Rotacao nao retornou nova chave.' }
  try { Invoke-WebRequest -Uri "http://127.0.0.1:9000/administracao/erps/$($erp.id_erp)/chaves/$($rotated.id_chave)" -Method Delete -UseBasicParsing | Out-Null; throw 'Revogacao sem Bearer foi aceita.' } catch { if ($_.Exception.Response.StatusCode.value__ -ne 401) { throw } }
  Invoke-WebRequest -Uri "http://127.0.0.1:9000/administracao/erps/$($erp.id_erp)/chaves/$($rotated.id_chave)" -Method Delete -Headers $headers -UseBasicParsing | Out-Null
  $regularEmail = 'user-' + [guid]::NewGuid().ToString('N') + '@example.test'
  & $psql -q -h $env:FISCONEXA_DB_HOST -p $env:FISCONEXA_DB_PORT -U $env:FISCONEXA_DB_USER -d $database -c "insert into usuarios (email, display_name, password_hash, platform_role) select '$regularEmail', 'Regular smoke', password_hash, 'user' from usuarios where email = '$email'"
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar usuario comum de fixture.' }
  $regularLogin = Invoke-RestMethod -Uri 'http://127.0.0.1:9000/autenticacao/entrar' -Method Post -ContentType 'application/json' -Body (@{email=$regularEmail;senha=$password}|ConvertTo-Json -Compress)
  try { Invoke-WebRequest -Uri 'http://127.0.0.1:9000/administracao/erps' -Method Post -Headers @{Authorization="Bearer $($regularLogin.token_acesso)"} -ContentType 'application/json' -Body '{}' -UseBasicParsing | Out-Null; throw 'Usuario comum foi aceito na rota administrativa.' } catch { if ($_.Exception.Response.StatusCode.value__ -ne 403) { throw } }
  $refresh = Invoke-RestMethod -Uri 'http://127.0.0.1:9000/autenticacao/renovar' -Method Post -ContentType 'application/json' -Body (@{token_renovacao=$login.token_renovacao}|ConvertTo-Json -Compress)
  if ($refresh.token_renovacao -eq $login.token_renovacao) { throw 'Token de renovacao nao foi rotacionado.' }
  try { Invoke-WebRequest -Uri 'http://127.0.0.1:9000/autenticacao/renovar' -Method Post -ContentType 'application/json' -Body (@{token_renovacao=$login.token_renovacao}|ConvertTo-Json -Compress) -UseBasicParsing | Out-Null; throw 'Token de renovacao reutilizado foi aceito.' } catch { if ($_.Exception.Response.StatusCode.value__ -ne 401) { throw } }
  $newPassword = 'Smoke-Only-Changed-2026!'
  $headers = @{ Authorization = "Bearer $($refresh.token_acesso)" }
  Invoke-WebRequest -Uri 'http://127.0.0.1:9000/autenticacao/senha' -Method Put -Headers $headers -ContentType 'application/json' -Body (@{senha_atual=$password;nova_senha=$newPassword}|ConvertTo-Json -Compress) -UseBasicParsing | Out-Null
  try { Invoke-WebRequest -Uri 'http://127.0.0.1:9000/administracao/erps' -Method Post -Headers $headers -ContentType 'application/json' -Body '{}' -UseBasicParsing | Out-Null; throw 'Token de acesso anterior continuou valido apos troca de senha.' } catch { if ($_.Exception.Response.StatusCode.value__ -ne 401) { throw } }
  $changedLogin = Invoke-RestMethod -Uri 'http://127.0.0.1:9000/autenticacao/entrar' -Method Post -ContentType 'application/json' -Body (@{email=$email;senha=$newPassword}|ConvertTo-Json -Compress)
  if ([string]::IsNullOrWhiteSpace($changedLogin.token_acesso)) { throw 'Nova senha nao autenticou.' }
  $changedHeaders = @{ Authorization = "Bearer $($changedLogin.token_acesso)" }
  Invoke-WebRequest -Uri 'http://127.0.0.1:9000/autenticacao/sair' -Method Post -Headers $changedHeaders -UseBasicParsing | Out-Null
  try { Invoke-WebRequest -Uri 'http://127.0.0.1:9000/administracao/erps' -Method Post -Headers $changedHeaders -ContentType 'application/json' -Body '{}' -UseBasicParsing | Out-Null; throw 'Token de acesso permaneceu valido apos logout.' } catch { if ($_.Exception.Response.StatusCode.value__ -ne 401) { throw } }
  Write-Output 'Smoke aprovado: login, Bearer superadmin, cadastro ERP, refresh rotativo, troca de senha e logout.'
} finally {
  if ($null -ne $process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force }
  if (Test-Path -LiteralPath $dropdb) { & $dropdb -h $env:FISCONEXA_DB_HOST -p $env:FISCONEXA_DB_PORT -U $env:FISCONEXA_DB_USER --if-exists $database }
}
