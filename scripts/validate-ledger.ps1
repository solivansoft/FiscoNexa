param(
  [string]$LedgerPath = (Join-Path $PSScriptRoot '..\docs\LEDGER.md')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $LedgerPath)) {
  throw "Ledger nao encontrado: $LedgerPath"
}

$allowedStates = @('PENDENTE', 'EM_CURSO', 'OK', 'BLOQUEADO', 'N/A')
$items = @()

Get-Content -LiteralPath $LedgerPath | ForEach-Object {
  if ($_ -match '^\|\s*([A-Z][A-Z0-9-]*-\d+)\s*\|\s*([A-Z_\/]+)\s*\|') {
    $items += [PSCustomObject]@{
      Id = $matches[1]
      State = $matches[2]
    }
  }
}

if ($items.Count -eq 0) {
  throw 'Nenhum item de ledger foi encontrado.'
}

$invalidState = @($items | Where-Object { $_.State -notin $allowedStates })
if ($invalidState) {
  throw ('Estado invalido: ' + (($invalidState | ForEach-Object { "$($_.Id)=$($_.State)" }) -join ', '))
}

$duplicates = @($items | Group-Object Id | Where-Object { $_.Count -gt 1 })
if ($duplicates) {
  throw ('IDs duplicados: ' + (($duplicates | ForEach-Object Name) -join ', '))
}

$inProgress = @($items | Where-Object { $_.State -eq 'EM_CURSO' })
if ($inProgress.Count -gt 1) {
  throw ('Mais de um item EM_CURSO: ' + (($inProgress | ForEach-Object Id) -join ', '))
}

Write-Output "Ledger valido: $($items.Count) itens, $($inProgress.Count) em curso."
