# Continuacao unica do lote autorizado, usando exclusivamente a janela persistida.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$cfg=@{}
Get-Content (Join-Path $root '.env')|ForEach-Object {
  if($_ -match '^([^#=]+)=(.*)$'){$cfg[$matches[1].Trim()]=$matches[2].Trim().Trim('"').Trim("'")}
}
$sessions=@(Import-Clixml (Join-Path $root 'build\pilot-batch-session.clixml'))
foreach($session in $sessions){if($session.Database -ne $cfg['POSTGRES_DB']){throw 'Banco do piloto mudou.'}}
$deadline=[datetime]::UtcNow.AddHours(3)
while($true) {
  if([datetime]::UtcNow -ge $deadline){throw 'Prazo de acompanhamento esgotado.'}
  $seconds=& docker exec fisconexa-postgres psql -U $cfg['POSTGRES_USER'] -d $cfg['POSTGRES_DB'] -v ON_ERROR_STOP=1 -Atc "select greatest(0,ceil(extract(epoch from min(next_check_at)-now()))) from status_monitoramento where status='active';"
  if($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($seconds)){throw 'Janela indisponivel; nao consultar.'}
  if([int]$seconds -le 0){break}
  Start-Sleep -Seconds ([Math]::Min(30,[int]$seconds))
}
Write-Output ('Janela elegivel em UTC: '+[datetime]::UtcNow.ToString('o'))
& (Join-Path $root 'tests\smoke-fiscal-batch.ps1') -AllowAwareness -SkipOnboarding
Write-Output 'Continuacao unica encerrada; conferir os resultados do lote.'
