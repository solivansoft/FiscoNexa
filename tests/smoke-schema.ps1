param(
  [string]$Executable = "$(Join-Path $PSScriptRoot '..\bin\win64\FiscoNexa.Api.exe')"
)

$ErrorActionPreference = 'Stop'

function Load-DevelopmentEnvironment {
  param([string]$Root)

  Get-Content -LiteralPath (Join-Path $Root '.env') | ForEach-Object {
    if ($_ -match '^([^#=]+)=(.*)$') {
      Set-Item -Path ('Env:' + $matches[1].Trim()) -Value $matches[2]
    }
  }
  $env:FISCONEXA_DB_HOST = '127.0.0.1'
  $env:FISCONEXA_DB_PORT = $env:POSTGRES_PORT
  $env:FISCONEXA_DB_NAME = $env:POSTGRES_DB
  $env:FISCONEXA_DB_USER = $env:POSTGRES_USER
  $env:FISCONEXA_DB_PASSWORD = $env:POSTGRES_PASSWORD
  $env:Path = (Join-Path $Root 'vendor\postgres-client\pgsql\bin') + ';' + $env:Path
}

function Start-And-VerifyApi {
  param([string]$Path)

  $process = Start-Process -FilePath $Path -PassThru -WindowStyle Hidden
  try {
    $deadline = (Get-Date).AddSeconds(10)
    do {
      try {
        if ((Invoke-RestMethod -Uri 'http://127.0.0.1:9000/saude' -TimeoutSec 1).situacao -eq 'disponivel') {
          return
        }
      } catch {
        Start-Sleep -Milliseconds 200
      }
    } while ((Get-Date) -lt $deadline)
    throw 'API nao respondeu saude apos aplicar o schema.'
  } finally {
    if (-not $process.HasExited) {
      Stop-Process -Id $process.Id -Force
    }
  }
}

$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $Executable)) {
  throw "Executavel nao encontrado: $Executable"
}
Load-DevelopmentEnvironment -Root $root
Start-And-VerifyApi -Path $Executable
Start-And-VerifyApi -Path $Executable

$tables = & docker exec fisconexa-postgres psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB -Atc "select string_agg(table_name, ',' order by table_name) from information_schema.tables where table_schema = 'public';"
if ($LASTEXITCODE -ne 0) {
  throw 'Nao foi possivel consultar o schema final.'
}

$requiredTables = @('usuarios', 'organizacoes', 'organizacoes_usuarios', 'empresas',
  'empresas_usuarios', 'empresas_organizacoes', 'chaves_erp', 'certificados',
  'configuracoes_monitoramento', 'empresas_modulos', 'status_monitoramento', 'comandos',
  'lacunas_monitoramento', 'consultas_pontuais', 'integracoes', 'documentos', 'auditorias',
  'schema_actions')
foreach ($table in $requiredTables) {
  if ($tables -notmatch "(^|,)$table(,|$)") {
    throw "Tabela obrigatoria ausente: $table"
  }
}

$requiredConstraints = @(
  'company_organizations_relationship_check',
  'documents_company_fk',
  'monitor_status_interval_check',
  'monitor_gaps_status_check'
)
foreach ($constraint in $requiredConstraints) {
  $exists = & docker exec fisconexa-postgres psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB -Atc "select exists(select 1 from information_schema.table_constraints where table_schema = 'public' and constraint_name = '$constraint');"
  if ($LASTEXITCODE -ne 0 -or $exists -ne 't') {
    throw "Constraint obrigatoria ausente: $constraint"
  }
}

$requiredIndexes = @('commands_pending_idx', 'documents_company_status_issued_idx',
  'monitor_status_due_idx', 'monitor_gaps_due_idx', 'point_queries_company_requested_idx')
foreach ($index in $requiredIndexes) {
  $exists = & docker exec fisconexa-postgres psql -U $env:POSTGRES_USER -d $env:POSTGRES_DB -Atc "select exists(select 1 from pg_indexes where schemaname = 'public' and indexname = '$index');"
  if ($LASTEXITCODE -ne 0 -or $exists -ne 't') {
    throw "Indice obrigatorio ausente: $index"
  }
}

Write-Output 'Smoke schema aprovado: banco vazio aplicado duas vezes com tabelas, constraints e indices finais.'
