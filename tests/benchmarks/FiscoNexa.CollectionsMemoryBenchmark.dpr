program FiscoNexa.CollectionsMemoryBenchmark;

{$APPTYPE CONSOLE}

uses
  System.Generics.Collections,
  System.SysUtils,
  Winapi.PsAPI,
  Winapi.Windows;

const
  ItemCount = 10000000;

type
  TWorkItem = record
    Id: Integer;
    Amount: Int64;
  end;

function CreateWorkItem(const AId: Integer): TWorkItem;
begin
  Result.Id := AId;
  Result.Amount := AId;
end;

function MemoryCounters: TProcessMemoryCountersEx;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.cb := SizeOf(Result);
  if not GetProcessMemoryInfo(GetCurrentProcess, @Result, SizeOf(Result)) then
    RaiseLastOSError;
end;

function Megabytes(const ABytes: UInt64): Double;
begin
  Result := ABytes / 1024 / 1024;
end;

procedure WriteMemory(const AName: string;
  const ABefore, AAfter: TProcessMemoryCountersEx);
begin
  Writeln(Format('%s: working_set %.1f -> %.1f MB (delta %.1f MB); private %.1f -> %.1f MB (delta %.1f MB)',
    [AName, Megabytes(ABefore.WorkingSetSize), Megabytes(AAfter.WorkingSetSize),
    Megabytes(AAfter.WorkingSetSize - ABefore.WorkingSetSize),
    Megabytes(ABefore.PrivateUsage), Megabytes(AAfter.PrivateUsage),
    Megabytes(AAfter.PrivateUsage - ABefore.PrivateUsage)]));
end;

procedure BenchmarkArray;
var
  Items: TArray<TWorkItem>;
  BeforeMemory: TProcessMemoryCountersEx;
  AfterMemory: TProcessMemoryCountersEx;
  Index: Integer;
begin
  BeforeMemory := MemoryCounters;
  SetLength(Items, ItemCount);
  for Index := 0 to High(Items) do
    Items[Index] := CreateWorkItem(Index);
  AfterMemory := MemoryCounters;
  WriteMemory('TArray', BeforeMemory, AfterMemory);
  if Items[ItemCount - 1].Amount <> ItemCount - 1 then
    raise EInvalidOpException.Create('Array nao foi preenchido.');
end;

procedure BenchmarkList;
var
  Items: TList<TWorkItem>;
  BeforeMemory: TProcessMemoryCountersEx;
  AfterMemory: TProcessMemoryCountersEx;
  Index: Integer;
begin
  BeforeMemory := MemoryCounters;
  Items := TList<TWorkItem>.Create;
  try
    Items.Capacity := ItemCount;
    for Index := 0 to ItemCount - 1 do
      Items.Add(CreateWorkItem(Index));
    AfterMemory := MemoryCounters;
    WriteMemory('TList preallocated', BeforeMemory, AfterMemory);
    if Items[ItemCount - 1].Amount <> ItemCount - 1 then
      raise EInvalidOpException.Create('Lista nao foi preenchida.');
  finally
    Items.Free;
  end;
end;

procedure BenchmarkGrowingList;
var
  Items: TList<TWorkItem>;
  BeforeMemory: TProcessMemoryCountersEx;
  AfterMemory: TProcessMemoryCountersEx;
  Index: Integer;
begin
  BeforeMemory := MemoryCounters;
  Items := TList<TWorkItem>.Create;
  try
    for Index := 0 to ItemCount - 1 do
      Items.Add(CreateWorkItem(Index));
    AfterMemory := MemoryCounters;
    WriteMemory('TList growing', BeforeMemory, AfterMemory);
    Writeln(Format('TList final capacity: %d items', [Items.Capacity]));
    if Items[ItemCount - 1].Amount <> ItemCount - 1 then
      raise EInvalidOpException.Create('Lista nao foi preenchida.');
  finally
    Items.Free;
  end;
end;

begin
  if SameText(ParamStr(1), 'array') then
    BenchmarkArray
  else if SameText(ParamStr(1), 'list') then
    BenchmarkList
  else if SameText(ParamStr(1), 'list-grow') then
    BenchmarkGrowingList
  else
    raise EArgumentException.Create('Uso: FiscoNexa.CollectionsMemoryBenchmark.exe array|list|list-grow');
end.
