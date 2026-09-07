unit Persistence.ErpKeys;

interface

uses
  Application.ErpKeys,
  FireDAC.Stan.Param, FireDAC.Comp.Client;

type
  TPostgresErpKeyReader = class(TInterfacedObject, IErpKeyReader)
  private
    FConnection: TFDConnection;
  public
    constructor Create(const AConnection: TFDConnection);
    function FindActiveByHash(const AKeyHash: string;
      out APrincipal: TErpKeyPrincipal): Boolean;
  end;

implementation

uses
  Data.DB;

constructor TPostgresErpKeyReader.Create(const AConnection: TFDConnection);
begin
  inherited Create;
  FConnection := AConnection;
end;

function TPostgresErpKeyReader.FindActiveByHash(const AKeyHash: string;
  out APrincipal: TErpKeyPrincipal): Boolean;
var
  Query: TFDQuery;
begin
  APrincipal := Default(TErpKeyPrincipal);
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'select id::text as id, organization_id::text as organization_id, ' +
      'scopes::text as scopes from chaves_erp ' +
      'where key_hash = :key_hash and revoked_at is null ' +
      'and (expires_at is null or expires_at > now())';
    Query.ParamByName('key_hash').AsString := AKeyHash;
    Query.Open;
    Result := not Query.IsEmpty;
    if Result then
    begin
      APrincipal.KeyId := Query.FieldByName('id').AsString;
      APrincipal.OrganizationId := Query.FieldByName('organization_id').AsString;
      APrincipal.ScopesJson := Query.FieldByName('scopes').AsString;
    end;
  finally
    Query.Free;
  end;
end;

end.
