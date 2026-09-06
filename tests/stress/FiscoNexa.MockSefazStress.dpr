program FiscoNexa.MockSefazStress;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Diagnostics,
  System.Math,
  System.StrUtils,
  System.SysUtils,
  System.Types,
  Winapi.PsAPI,
  Winapi.Windows;

type
  TMockSefazWorker = class(TThread)
  private
    FDeadline: TDateTime;
    FLatencyMilliseconds: Integer;
    FCompletedRequests: Int64;
  protected
    procedure Execute; override;
  public
    constructor Create(const ADeadline: TDateTime;
      const ALatencyMilliseconds: Integer);
    property CompletedRequests: Int64 read FCompletedRequests;
  end;

function ArgumentValue(const AName: string; const ADefault: Integer): Integer;
var
  Index: Integer;
  Prefix: string;
begin
  Result := ADefault;
  Prefix := '--' + AName + '=';
  for Index := 1 to ParamCount do
  begin
    if StartsText(Prefix, ParamStr(Index)) then
      Exit(StrToIntDef(Copy(ParamStr(Index), Length(Prefix) + 1, MaxInt), ADefault));
  end;
end;

function CurrentPrivateBytes: UInt64;
var
  Counters: PROCESS_MEMORY_COUNTERS_EX;
begin
  FillChar(Counters, SizeOf(Counters), 0);
  Counters.cb := SizeOf(Counters);
  if not GetProcessMemoryInfo(GetCurrentProcess, @Counters, SizeOf(Counters)) then
    RaiseLastOSError;
  Result := Counters.PrivateUsage;
end;

constructor TMockSefazWorker.Create(const ADeadline: TDateTime;
  const ALatencyMilliseconds: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FDeadline := ADeadline;
  FLatencyMilliseconds := ALatencyMilliseconds;
end;

procedure TMockSefazWorker.Execute;
begin
  while Now < FDeadline do
  begin
    Sleep(FLatencyMilliseconds);
    Inc(FCompletedRequests);
  end;
end;

procedure Require(const ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise EInvalidOpException.Create(AMessage);
end;

var
  Workers: TArray<TMockSefazWorker>;
  WorkerCount: Integer;
  DurationSeconds: Integer;
  LatencyMilliseconds: Integer;
  Deadline: TDateTime;
  Stopwatch: TStopwatch;
  CompletedRequests: Int64;
  MaximumRequests: Int64;
  Index: Integer;
begin
  WorkerCount := ArgumentValue('workers', 1);
  DurationSeconds := ArgumentValue('seconds', 15);
  LatencyMilliseconds := ArgumentValue('latency-ms', 100);
  if WorkerCount <= 0 then
    raise EArgumentOutOfRangeException.Create('workers deve ser positivo.');
  if DurationSeconds <= 0 then
    raise EArgumentOutOfRangeException.Create('seconds deve ser positivo.');
  if LatencyMilliseconds <= 0 then
    raise EArgumentOutOfRangeException.Create('latency-ms deve ser positivo.');

  SetLength(Workers, WorkerCount);
  Deadline := Now + (DurationSeconds / SecsPerDay);
  Stopwatch := TStopwatch.StartNew;
  try
    for Index := 0 to High(Workers) do
    begin
      Workers[Index] := TMockSefazWorker.Create(Deadline, LatencyMilliseconds);
      Workers[Index].Start;
    end;
    CompletedRequests := 0;
    for Index := 0 to High(Workers) do
    begin
      Workers[Index].WaitFor;
      Inc(CompletedRequests, Workers[Index].CompletedRequests);
      Require(Workers[Index].CompletedRequests > 0,
        'Worker terminou sem progresso.');
    end;
    Stopwatch.Stop;
    MaximumRequests := Int64(WorkerCount) *
      (Ceil((Stopwatch.Elapsed.TotalMilliseconds / LatencyMilliseconds)) + 1);
    Require(CompletedRequests <= MaximumRequests,
      'Contador de requisicoes excedeu o limite do relogio simulado.');
    Writeln(Format('workers=%d;seconds=%.3f;latency_ms=%d;requests=%d;requests_per_second=%.3f;private_mb=%.3f',
      [WorkerCount, Stopwatch.Elapsed.TotalSeconds, LatencyMilliseconds,
      CompletedRequests, CompletedRequests / Stopwatch.Elapsed.TotalSeconds,
      CurrentPrivateBytes / 1024 / 1024]));
  finally
    for Index := 0 to High(Workers) do
      Workers[Index].Free;
  end;
end.
