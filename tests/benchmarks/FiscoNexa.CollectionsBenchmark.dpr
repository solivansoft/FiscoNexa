program FiscoNexa.CollectionsBenchmark;

{$APPTYPE CONSOLE}

uses
  System.Diagnostics,
  System.Generics.Collections,
  System.SysUtils;

const
  ListItemCount = 1000000;
  QueueItemCount = 1000000;
  DeleteFirstItemCount = 50000;

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

function ElapsedMilliseconds(const AStopwatch: TStopwatch): Int64;
begin
  Result := AStopwatch.ElapsedMilliseconds;
end;

procedure BenchmarkListAppendAndIterate;
var
  Items: TList<TWorkItem>;
  Stopwatch: TStopwatch;
  Index: Integer;
  Checksum: Int64;
begin
  Items := TList<TWorkItem>.Create;
  try
    Items.Capacity := ListItemCount;
    Stopwatch := TStopwatch.StartNew;
    for Index := 0 to ListItemCount - 1 do
      Items.Add(CreateWorkItem(Index));
    Stopwatch.Stop;
    Writeln(Format('TList append %d: %d ms', [ListItemCount,
      ElapsedMilliseconds(Stopwatch)]));

    Checksum := 0;
    Stopwatch := TStopwatch.StartNew;
    for Index := 0 to Items.Count - 1 do
      Inc(Checksum, Items[Index].Amount);
    Stopwatch.Stop;
    Writeln(Format('TList iterate %d: %d ms, checksum=%d', [ListItemCount,
      ElapsedMilliseconds(Stopwatch), Checksum]));
  finally
    Items.Free;
  end;
end;

procedure BenchmarkAllocationAndFill;
var
  ListItems: TList<TWorkItem>;
  ArrayItems: TArray<TWorkItem>;
  Stopwatch: TStopwatch;
  Index: Integer;
begin
  Stopwatch := TStopwatch.StartNew;
  ListItems := TList<TWorkItem>.Create;
  try
    ListItems.Capacity := ListItemCount;
    for Index := 0 to ListItemCount - 1 do
      ListItems.Add(CreateWorkItem(Index));
  finally
    ListItems.Free;
  end;
  Stopwatch.Stop;
  Writeln(Format('TList allocate + fill %d: %d ms', [ListItemCount,
    ElapsedMilliseconds(Stopwatch)]));

  Stopwatch := TStopwatch.StartNew;
  SetLength(ArrayItems, ListItemCount);
  for Index := 0 to High(ArrayItems) do
    ArrayItems[Index] := CreateWorkItem(Index);
  ArrayItems := nil;
  Stopwatch.Stop;
  Writeln(Format('TArray allocate + fill %d: %d ms', [ListItemCount,
    ElapsedMilliseconds(Stopwatch)]));

  Stopwatch := TStopwatch.StartNew;
  ListItems := TList<TWorkItem>.Create;
  try
    for Index := 0 to ListItemCount - 1 do
      ListItems.Add(CreateWorkItem(Index));
  finally
    ListItems.Free;
  end;
  Stopwatch.Stop;
  Writeln(Format('TList grow + fill %d: %d ms', [ListItemCount,
    ElapsedMilliseconds(Stopwatch)]));
end;

procedure BenchmarkArrayAppendAndIterate;
var
  Items: TArray<TWorkItem>;
  Stopwatch: TStopwatch;
  Index: Integer;
  Checksum: Int64;
begin
  SetLength(Items, ListItemCount);
  Stopwatch := TStopwatch.StartNew;
  for Index := 0 to High(Items) do
    Items[Index] := CreateWorkItem(Index);
  Stopwatch.Stop;
  Writeln(Format('TArray fill %d: %d ms', [ListItemCount,
    ElapsedMilliseconds(Stopwatch)]));

  Checksum := 0;
  Stopwatch := TStopwatch.StartNew;
  for Index := 0 to High(Items) do
    Inc(Checksum, Items[Index].Amount);
  Stopwatch.Stop;
  Writeln(Format('TArray iterate %d: %d ms, checksum=%d', [ListItemCount,
    ElapsedMilliseconds(Stopwatch), Checksum]));
end;

procedure BenchmarkQueueDequeue;
var
  Items: TQueue<TWorkItem>;
  Stopwatch: TStopwatch;
  Index: Integer;
  Checksum: Int64;
begin
  Items := TQueue<TWorkItem>.Create;
  try
    for Index := 0 to QueueItemCount - 1 do
      Items.Enqueue(CreateWorkItem(Index));

    Checksum := 0;
    Stopwatch := TStopwatch.StartNew;
    while Items.Count > 0 do
      Inc(Checksum, Items.Dequeue.Amount);
    Stopwatch.Stop;
    Writeln(Format('TQueue dequeue %d: %d ms, checksum=%d', [QueueItemCount,
      ElapsedMilliseconds(Stopwatch), Checksum]));
  finally
    Items.Free;
  end;
end;

procedure BenchmarkArrayHeadDequeue;
var
  Items: TArray<TWorkItem>;
  Stopwatch: TStopwatch;
  Index: Integer;
  Head: Integer;
  Checksum: Int64;
begin
  SetLength(Items, QueueItemCount);
  for Index := 0 to High(Items) do
    Items[Index] := CreateWorkItem(Index);

  Head := 0;
  Checksum := 0;
  Stopwatch := TStopwatch.StartNew;
  while Head < Length(Items) do
  begin
    Inc(Checksum, Items[Head].Amount);
    Inc(Head);
  end;
  Stopwatch.Stop;
  Writeln(Format('TArray head dequeue %d: %d ms, checksum=%d', [QueueItemCount,
    ElapsedMilliseconds(Stopwatch), Checksum]));
end;

procedure BenchmarkListDeleteFirst;
var
  Items: TList<TWorkItem>;
  Stopwatch: TStopwatch;
  Index: Integer;
  Checksum: Int64;
begin
  Items := TList<TWorkItem>.Create;
  try
    Items.Capacity := DeleteFirstItemCount;
    for Index := 0 to DeleteFirstItemCount - 1 do
      Items.Add(CreateWorkItem(Index));

    Checksum := 0;
    Stopwatch := TStopwatch.StartNew;
    while Items.Count > 0 do
    begin
      Inc(Checksum, Items[0].Amount);
      Items.Delete(0);
    end;
    Stopwatch.Stop;
    Writeln(Format('TList Delete(0) %d: %d ms, checksum=%d', [DeleteFirstItemCount,
      ElapsedMilliseconds(Stopwatch), Checksum]));
  finally
    Items.Free;
  end;
end;

begin
  Writeln('FiscoNexa collections benchmark (Release)');
  BenchmarkAllocationAndFill;
  BenchmarkListAppendAndIterate;
  BenchmarkArrayAppendAndIterate;
  BenchmarkQueueDequeue;
  BenchmarkArrayHeadDequeue;
  BenchmarkListDeleteFirst;
end.
