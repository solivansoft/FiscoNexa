# Continuacao unica do smoke ja autorizado; a elegibilidade continua no PostgreSQL.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$session = Import-Clixml -LiteralPath (Join-Path $root 'build\pilot-session.clixml')
$cfg = @{}
Get-Content -LiteralPath (Join-Path $root '.env') | ForEach-Object {
  if ($_ -match '^([^#=]+)=(.*)$') { $cfg[$matches[1].Trim()]=$matches[2].Trim().Trim('"').Trim("'") }
}
if ($session.Database -ne $cfg['POSTGRES_DB']) { throw 'Banco do piloto mudou; continuacao recusada.' }
$id = ([guid]$session.CompanyId).ToString()
$deadline = [datetime]::UtcNow.AddHours(3)
while ($true) {
  if ([datetime]::UtcNow -ge $deadline) { throw 'Prazo da continuacao esgotado; nenhuma consulta forcada.' }
  $seconds = & docker exec fisconexa-postgres psql -U $cfg['POSTGRES_USER'] -d $cfg['POSTGRES_DB'] -v ON_ERROR_STOP=1 -Atc "select greatest(0,ceil(extract(epoch from next_check_at-now()))) from status_monitoramento where company_id='$id';"
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($seconds)) { throw 'Estado fiscal indisponivel; nao consultar.' }
  if ([int]$seconds -le 0) { break }
  Start-Sleep -Seconds ([Math]::Min(30,[int]$seconds))
}
Write-Output ('Janela persistida vencida em UTC: ' + [datetime]::UtcNow.ToString('o'))
& (Join-Path $root 'tests\smoke-real-fiscal.ps1') -AllowAwareness
if ($LASTEXITCODE -ne 0) { throw 'Continuacao do smoke terminou com erro.' }
Write-Output 'Continuacao unica encerrada. Conferir pilot-last-state.json; nao foi instalado monitor permanente.'
