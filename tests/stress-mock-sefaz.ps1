param(
  [string]$Workers = '1,2,4,8,16,32',
  [int]$Seconds = 10,
  [int]$LatencyMilliseconds = 100
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script = Join-Path $root 'scripts\stress-mock-sefaz.bat'
$executable = Join-Path $root 'bin\stress\win64\FiscoNexa.MockSefazStress.exe'

& cmd /c $script '--workers=1' '--seconds=1' "--latency-ms=$LatencyMilliseconds"
if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar stress mock.' }

foreach ($workerCount in ($Workers.Split(',') | ForEach-Object { [int]$_.Trim() })) {
  $outputPath = Join-Path ([IO.Path]::GetTempPath()) ("fisconexa-stress-" + [guid]::NewGuid().ToString() + '.txt')
  $stopwatch = [Diagnostics.Stopwatch]::StartNew()
  $process = Start-Process -FilePath $executable -ArgumentList "--workers=$workerCount", "--seconds=$Seconds", "--latency-ms=$LatencyMilliseconds" -PassThru -Wait -NoNewWindow -RedirectStandardOutput $outputPath
  $stopwatch.Stop()
  $output = Get-Content -LiteralPath $outputPath
  Remove-Item -LiteralPath $outputPath
  if ($process.ExitCode -ne 0) { throw "Stress mock falhou para $workerCount workers." }
  $line = $output | Where-Object { $_ -like 'workers=*' } | Select-Object -Last 1
  if ([string]::IsNullOrWhiteSpace($line)) { throw "Resultado ausente para $workerCount workers." }
  $parts = @{}
  $line.Split(';') | ForEach-Object {
    $pair = $_.Split('=', 2)
    $parts[$pair[0]] = $pair[1]
  }
  $process = Get-Process -Id $PID
  [PSCustomObject]@{
    Workers = [int]$parts.workers
    Requests = [int64]$parts.requests
    RequestsPerSecond = [double]::Parse($parts.requests_per_second, [Globalization.CultureInfo]::GetCultureInfo('pt-BR'))
    ProcessPrivateMB = [double]::Parse($parts.private_mb, [Globalization.CultureInfo]::GetCultureInfo('pt-BR'))
    HostLogicalProcessors = [Environment]::ProcessorCount
    MockLatencyMS = [int]$parts.latency_ms
    ProcessCpuPercent = [math]::Round((100 * $process.TotalProcessorTime.TotalSeconds / $stopwatch.Elapsed.TotalSeconds / [Environment]::ProcessorCount), 2)
  }
}
