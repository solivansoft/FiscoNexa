program FiscoNexa.FireDacFetchIntegration;

{$APPTYPE CONSOLE}

uses
  Data.DB,
  FireDAC.Stan.Option,
  System.SysUtils,
  FireDAC.Stan.Param, FireDAC.Comp.Client,
  Database.Connection in '..\..\src\db\Database.Connection.pas';

procedure Require(const ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise EInvalidOpException.Create(AMessage);
end;

procedure ExecuteSql(const AConnection: TFDConnection; const ASql: string);
var
  Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text := ASql;
    Query.Execute;
  finally
    Query.Free;
  end;
end;

procedure SeedItems(const AConnection: TFDConnection; const ACount: Integer);
var
  Query: TFDQuery;
  Index: Integer;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text :=
      'insert into firedac_fetch_probe (id, payload) values (:id, :payload)';
    for Index := 1 to ACount do
    begin
      Query.ParamByName('id').AsInteger := Index;
      Query.ParamByName('payload').AsString := 'item-' + IntToStr(Index);
      Query.Execute;
    end;
  finally
    Query.Free;
  end;
end;

procedure AssertSequentialRead(const AConnection: TFDConnection;
  const AFetchAll, ACachedUpdates: Boolean; const AExpectedCount: Integer;
  const AScenario: string);
var
  Query: TFDQuery;
  ExpectedId: Integer;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.FetchOptions.RowsetSize := 25;
    if AFetchAll then Query.FetchOptions.Mode := fmAll
    else Query.FetchOptions.Mode := fmOnDemand;
    Query.CachedUpdates := ACachedUpdates;
    Query.SQL.Text := 'select id, payload from firedac_fetch_probe order by id';
    Query.Open;
    ExpectedId := 1;
    while not Query.Eof do
    begin
      Require(Query.FieldByName('id').AsInteger = ExpectedId,
        AScenario + ': ordem, duplicacao ou item ausente no ID ' + IntToStr(ExpectedId));
      Inc(ExpectedId);
      Query.Next;
    end;
    Require(ExpectedId - 1 = AExpectedCount,
      AScenario + ': quantidade lida diferente de ' + IntToStr(AExpectedCount));
  finally
    Query.Free;
  end;
end;

procedure AssertSqlPagination(const AConnection: TFDConnection;
  const AFetchAll, ACachedUpdates: Boolean; const AExpectedCount: Integer;
  const AScenario: string);
var
  Query: TFDQuery;
  LastId: Integer;
  ExpectedId: Integer;
  ReadCount: Integer;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.FetchOptions.RowsetSize := 25;
    if AFetchAll then Query.FetchOptions.Mode := fmAll
    else Query.FetchOptions.Mode := fmOnDemand;
    Query.CachedUpdates := ACachedUpdates;
    LastId := 0;
    ExpectedId := 1;
    ReadCount := 0;
    repeat
      Query.Close;
      Query.SQL.Text :=
        'select id, payload from firedac_fetch_probe where id > :last_id ' +
        'order by id limit 7';
      Query.ParamByName('last_id').AsInteger := LastId;
      Query.Open;
      while not Query.Eof do
      begin
        Require(Query.FieldByName('id').AsInteger = ExpectedId,
          AScenario + ': pagina SQL perdeu ou repetiu ID ' + IntToStr(ExpectedId));
        LastId := ExpectedId;
        Inc(ExpectedId);
        Inc(ReadCount);
        Query.Next;
      end;
    until Query.IsEmpty;
    Require(ReadCount = AExpectedCount,
      AScenario + ': paginacao SQL leu quantidade incorreta.');
  finally
    Query.Free;
  end;
end;

procedure AppendAndVerify(const AConnection: TFDConnection;
  const AFetchAll, ACachedUpdates, AInTransaction: Boolean;
  const AInitialCount: Integer; const AScenario: string);
var
  Writer: TFDQuery;
begin
  Writer := TFDQuery.Create(nil);
  try
    Writer.Connection := AConnection;
    Writer.FetchOptions.RowsetSize := 25;
    if AFetchAll then Writer.FetchOptions.Mode := fmAll
    else Writer.FetchOptions.Mode := fmOnDemand;
    Writer.CachedUpdates := ACachedUpdates;
    Writer.SQL.Text := 'select id, payload from firedac_fetch_probe order by id';
    Writer.Open;
    Writer.Append;
    Writer.FieldByName('id').AsInteger := AInitialCount + 1;
    Writer.FieldByName('payload').AsString := 'item-' + IntToStr(AInitialCount + 1);
    Writer.Post;
    if ACachedUpdates then
      Require(Writer.ApplyUpdates(0) = 0, AScenario + ': erro aplicando cache');
    if AInTransaction then
      AConnection.Commit;
    AssertSequentialRead(AConnection, AFetchAll, ACachedUpdates,
      AInitialCount + 1, AScenario);
  finally
    Writer.Free;
  end;
end;

procedure RunScenario(const AConnection: TFDConnection; const AFetchAll,
  ACachedUpdates, AInTransaction: Boolean; const AItemCount: Integer);
var
  Scenario: string;
begin
  Scenario := Format('items=%d fetch_all=%s cache=%s transaction=%s', [
    AItemCount,
    BoolToStr(AFetchAll, True), BoolToStr(ACachedUpdates, True),
    BoolToStr(AInTransaction, True)]);
  ExecuteSql(AConnection, 'drop table if exists pg_temp.firedac_fetch_probe');
  ExecuteSql(AConnection,
    'create temporary table firedac_fetch_probe (id integer primary key, payload varchar(40) not null)');
  try
    if AInTransaction then
      AConnection.StartTransaction;
    SeedItems(AConnection, AItemCount);
    AssertSequentialRead(AConnection, AFetchAll, ACachedUpdates, AItemCount, Scenario);
    AssertSqlPagination(AConnection, AFetchAll, ACachedUpdates, AItemCount, Scenario);
    AppendAndVerify(AConnection, AFetchAll, ACachedUpdates, AInTransaction,
      AItemCount, Scenario);
    Writeln('OK ', Scenario);
  except
    if AConnection.InTransaction then
      AConnection.Rollback;
    raise;
  end;
  ExecuteSql(AConnection, 'drop table pg_temp.firedac_fetch_probe');
end;

var
  Connection: TFDConnection;
  FetchAll: Boolean;
  CachedUpdates: Boolean;
  InTransaction: Boolean;
begin
  Connection := TDatabaseConnection.OpenFromEnvironment;
  try
    for FetchAll in [False, True] do
      for CachedUpdates in [False, True] do
        for InTransaction in [False, True] do
        begin
          RunScenario(Connection, FetchAll, CachedUpdates, InTransaction, 30);
          RunScenario(Connection, FetchAll, CachedUpdates, InTransaction, 101);
          RunScenario(Connection, FetchAll, CachedUpdates, InTransaction, 251);
        end;
    Writeln('Smoke FireDAC aprovado: 24 cenarios leram 30, 101 e 251 itens e confirmaram escrita.');
  finally
    Connection.Free;
  end;
end.
