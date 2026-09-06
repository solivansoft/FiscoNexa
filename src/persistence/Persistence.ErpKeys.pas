unit Persistence.ErpKeys;

interface

uses
  Application.ErpKeys,
  Uni;

type
  TPostgresErpKeyReader = class(TInterfacedObject, IErpKeyReader)
  private
    FConnection: TUniConnection;
  public
    constructor Create(const AConnection: TUniConnection);
    function FindActiveByHash(const AKeyHash: string;
      out APrincipal: TErpKeyPrincipal): Boolean;
  end;

implementation

uses
  Data.DB;

constructor TPostgresErpKeyReader.Create(const AConnection: TUniConnection);
begin
  inherited Create;
  FConnection := AConnection;
end;

function TPostgresErpKeyReader.FindActiveByHash(const AKeyHash: string;
  out APrincipal: TErpKeyPrincipal): Boolean;
var
  Query: TUniQuery;
begin
  APrincipal := Default(TErpKeyPrincipal);
  Query := TUniQuery.Create(nil);
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
