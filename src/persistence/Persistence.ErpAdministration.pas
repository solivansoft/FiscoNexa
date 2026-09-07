unit Persistence.ErpAdministration;

interface

uses Application.ErpAdministration, FireDAC.Stan.Param, FireDAC.Comp.Client;

type
  TPostgresErpAdministrationStore = class(TInterfacedObject, IErpAdministrationStore)
  private
    FConnection: TFDConnection;
  public
    constructor Create(const AConnection: TFDConnection);
    function CreateErp(const ALegalName: string): string;
    function ErpExists(const AErpId: string): Boolean;
    function CreateKey(const AErpId, ALabel, AKeyHash: string): string;
    procedure RevokeKey(const AErpId, AKeyId: string);
  end;

implementation

uses
  Data.DB,
  System.SysUtils;

constructor TPostgresErpAdministrationStore.Create(const AConnection: TFDConnection);
begin
  inherited Create;
  if AConnection = nil then
    raise EArgumentNilException.Create('Conexao PostgreSQL nao informada.');
  FConnection := AConnection;
end;

function TPostgresErpAdministrationStore.CreateErp(const ALegalName: string): string;
var Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text := 'insert into organizacoes (legal_name, organization_type) ' +
      'values (:legal_name, ''erp'') returning id::text as id';
    Query.ParamByName('legal_name').AsString := ALegalName;
    Query.Open;
    Result := Query.FieldByName('id').AsString;
  finally Query.Free; end;
end;

function TPostgresErpAdministrationStore.ErpExists(const AErpId: string): Boolean;
var Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text := 'select 1 from organizacoes where id = cast(:id as uuid) and organization_type = ''erp''';
    Query.ParamByName('id').AsString := AErpId;
    Query.Open;
    Result := not Query.IsEmpty;
  finally Query.Free; end;
end;

function TPostgresErpAdministrationStore.CreateKey(const AErpId, ALabel, AKeyHash: string): string;
var Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text := 'insert into chaves_erp (organization_id, label, key_hash) values ' +
      '(cast(:erp_id as uuid), :label, :key_hash) returning id::text as id';
    Query.ParamByName('erp_id').AsString := AErpId;
    Query.ParamByName('label').AsString := ALabel;
    Query.ParamByName('key_hash').AsString := AKeyHash;
    Query.Open;
    Result := Query.FieldByName('id').AsString;
  finally Query.Free; end;
end;

procedure TPostgresErpAdministrationStore.RevokeKey(const AErpId, AKeyId: string);
var Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text := 'update chaves_erp set revoked_at = now() where id = cast(:key_id as uuid) ' +
      'and organization_id = cast(:erp_id as uuid) and revoked_at is null';
    Query.ParamByName('key_id').AsString := AKeyId;
    Query.ParamByName('erp_id').AsString := AErpId;
    Query.ExecSQL;
    if Query.RowsAffected <> 1 then
      raise EErpNotFound.Create('Chave ERP nao encontrada.');
  finally Query.Free; end;
end;

end.
