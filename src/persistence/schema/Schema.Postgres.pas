unit Schema.Postgres;

interface

uses
  Schema.Definition,
  FireDAC.Stan.Param, FireDAC.Comp.Client;

type
  TPostgresSchema = class
  public
    class procedure Apply(const AConnection: TFDConnection; const ATable: TTableSchema); static;
  end;

implementation

uses
  System.SysUtils;

procedure ValidateIdentifier(const AValue: string);
var
  Character: Char;
begin
  if AValue = '' then
    raise EArgumentException.Create('Identificador do schema nao informado.');

  for Character in AValue do
    if not CharInSet(Character, ['a'..'z', 'A'..'Z', '0'..'9', '_']) then
      raise EArgumentException.Create('Identificador do schema invalido: ' + AValue);
end;

function FieldTypeSql(const AField: TSchemaField): string;
begin
  case AField.FieldType of
    sftUuid: Result := 'uuid';
    sftText:
      if AField.Length > 0 then Result := Format('varchar(%d)', [AField.Length]) else Result := 'text';
    sftInteger: Result := 'integer';
    sftBigInteger: Result := 'bigint';
    sftBoolean: Result := 'boolean';
    sftDate: Result := 'date';
    sftTimestamp: Result := 'timestamptz';
    sftDecimal: Result := 'numeric(18,2)';
    sftJson: Result := 'jsonb';
    sftBinary: Result := 'bytea';
  end;
end;

function FieldSql(const AField: TSchemaField): string;
begin
  Result := AField.Name + ' ' + FieldTypeSql(AField);
  if sfaDefaultUuid in AField.Attributes then Result := Result + ' default gen_random_uuid()';
  if sfaDefaultNow in AField.Attributes then Result := Result + ' default now()';
  if AField.DefaultValue <> '' then Result := Result + ' default ' + AField.DefaultValue;
  if sfaPrimaryKey in AField.Attributes then Result := Result + ' primary key';
  if sfaNotNull in AField.Attributes then Result := Result + ' not null';
  if sfaUnique in AField.Attributes then Result := Result + ' unique';
end;

function ColumnExists(const AConnection: TFDConnection; const ATableName, AColumnName: string): Boolean;
var Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text := 'select exists(select 1 from information_schema.columns where table_schema = ''public'' and table_name = :table_name and column_name = :column_name) as exists';
    Query.ParamByName('table_name').AsString := ATableName;
    Query.ParamByName('column_name').AsString := AColumnName;
    Query.Open;
    Result := Query.FieldByName('exists').AsBoolean;
  finally Query.Free; end;
end;

procedure CreateActionTable(const AConnection: TFDConnection);
begin
  AConnection.ExecSQL('create table if not exists schema_actions (table_name text not null, action_id text not null, applied_at timestamptz not null default now(), primary key (table_name, action_id))');
end;

function ActionWasApplied(const AConnection: TFDConnection; const ATableName, AActionId: string): Boolean;
var Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text := 'select exists(select 1 from schema_actions where table_name = :table_name and action_id = :action_id) as applied';
    Query.ParamByName('table_name').AsString := ATableName;
    Query.ParamByName('action_id').AsString := AActionId;
    Query.Open;
    Result := Query.FieldByName('applied').AsBoolean;
  finally Query.Free; end;
end;

procedure RegisterAction(const AConnection: TFDConnection; const ATableName, AActionId: string);
var
  Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text := 'insert into schema_actions (table_name, action_id) values (:table_name, :action_id)';
    Query.ParamByName('table_name').AsString := ATableName;
    Query.ParamByName('action_id').AsString := AActionId;
    Query.Execute;
  finally
    Query.Free;
  end;
end;

procedure ApplyAction(const AConnection: TFDConnection; const ATable: TTableSchema; const AAction: TSchemaAction);
begin
  case AAction.ActionType of
    satRenameField:
      if ColumnExists(AConnection, ATable.Name, AAction.SourceName) and
        not ColumnExists(AConnection, ATable.Name, AAction.TargetName) then
        AConnection.ExecSQL('alter table ' + ATable.Name + ' rename column ' + AAction.SourceName + ' to ' + AAction.TargetName);
    satRemoveField:
      if ColumnExists(AConnection, ATable.Name, AAction.SourceName) then
        raise EInvalidOpException.Create('Remocao automatica de campo recusada: ' + AAction.SourceName);
    satExecuteData:
      if not ActionWasApplied(AConnection, ATable.Name, AAction.Id) then
      begin
        AConnection.ExecSQL(AAction.Sql);
        RegisterAction(AConnection, ATable.Name, AAction.Id);
      end;
  end;
end;

function ConstraintExists(const AConnection: TFDConnection; const ATableName,
  AConstraintName: string): Boolean;
var
  Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text := 'select exists(select 1 from information_schema.table_constraints ' +
      'where table_schema = ''public'' and table_name = :table_name ' +
      'and constraint_name = :constraint_name) as exists';
    Query.ParamByName('table_name').AsString := ATableName;
    Query.ParamByName('constraint_name').AsString := AConstraintName;
    Query.Open;
    Result := Query.FieldByName('exists').AsBoolean;
  finally
    Query.Free;
  end;
end;

function IndexExists(const AConnection: TFDConnection; const AIndexName: string): Boolean;
var
  Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text := 'select exists(select 1 from pg_indexes where schemaname = ''public'' ' +
      'and indexname = :index_name) as exists';
    Query.ParamByName('index_name').AsString := AIndexName;
    Query.Open;
    Result := Query.FieldByName('exists').AsBoolean;
  finally
    Query.Free;
  end;
end;

procedure ApplyForeignKey(const AConnection: TFDConnection; const ATable: TTableSchema;
  const AForeignKey: TSchemaForeignKey);
var
  Sql: string;
begin
  if ConstraintExists(AConnection, ATable.Name, AForeignKey.Name) then
    Exit;

  Sql := 'alter table ' + ATable.Name + ' add constraint ' + AForeignKey.Name +
    ' foreign key (' + AForeignKey.FieldName + ') references ' +
    AForeignKey.TargetTable + '(' + AForeignKey.TargetField + ')';
  if AForeignKey.OnDelete <> '' then
    Sql := Sql + ' on delete ' + AForeignKey.OnDelete;
  AConnection.ExecSQL(Sql);
end;

procedure ApplyCheck(const AConnection: TFDConnection; const ATable: TTableSchema;
  const ACheck: TSchemaCheck);
begin
  if ConstraintExists(AConnection, ATable.Name, ACheck.Name) then
    Exit;

  AConnection.ExecSQL('alter table ' + ATable.Name + ' add constraint ' +
    ACheck.Name + ' check (' + ACheck.Expression + ')');
end;

procedure ApplyIndex(const AConnection: TFDConnection; const ATable: TTableSchema;
  const AIndex: TSchemaIndex);
var
  Sql: string;
begin
  if IndexExists(AConnection, AIndex.Name) then
    Exit;

  Sql := 'create ';
  if AIndex.Unique then
    Sql := Sql + 'unique ';
  Sql := Sql + 'index ' + AIndex.Name + ' on ' + ATable.Name +
    ' (' + AIndex.Fields + ')';
  AConnection.ExecSQL(Sql);
end;

class procedure TPostgresSchema.Apply(const AConnection: TFDConnection; const ATable: TTableSchema);
var
  Field: TSchemaField;
  Action: TSchemaAction;
  Index: TSchemaIndex;
  ForeignKey: TSchemaForeignKey;
  Check: TSchemaCheck;
  FieldsSql: string;
begin
  ValidateIdentifier(ATable.Name);
  CreateActionTable(AConnection);
  FieldsSql := '';
  for Field in ATable.Fields do
  begin
    if FieldsSql <> '' then FieldsSql := FieldsSql + ', ';
    FieldsSql := FieldsSql + FieldSql(Field);
  end;
  AConnection.ExecSQL('create table if not exists ' + ATable.Name + ' (' + FieldsSql + ')');
  for Action in ATable.Actions do
    if Action.ActionType <> satExecuteData then
      ApplyAction(AConnection, ATable, Action);
  for Field in ATable.Fields do
  begin
    ValidateIdentifier(Field.Name);
    if not ColumnExists(AConnection, ATable.Name, Field.Name) then
      AConnection.ExecSQL('alter table ' + ATable.Name + ' add column ' + FieldSql(Field));
  end;
  for ForeignKey in ATable.ForeignKeys do
    ApplyForeignKey(AConnection, ATable, ForeignKey);
  for Check in ATable.Checks do
    ApplyCheck(AConnection, ATable, Check);
  for Index in ATable.Indexes do
    ApplyIndex(AConnection, ATable, Index);
  for Action in ATable.Actions do
    if Action.ActionType = satExecuteData then
      ApplyAction(AConnection, ATable, Action);
end;

end.
