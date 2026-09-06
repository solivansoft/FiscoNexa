unit Operations.ErpModules;

interface

procedure ChangeErpMonitoringModule(const AAuthorization, ACompanyId, AStatus: string);

implementation

uses
  Application.ErpKeys,
  Database.Connection,
  Persistence.ErpKeys,
  System.SysUtils,
  Uni;

procedure ChangeErpMonitoringModule(const AAuthorization, ACompanyId, AStatus: string);
var
  Connection: TUniConnection;
  Reader: IErpKeyReader;
  Principal: TErpKeyPrincipal;
  Query: TUniQuery;
begin
  if not ((AStatus = 'active') or (AStatus = 'suspended') or
    (AStatus = 'cancelled')) then
    raise EArgumentException.Create('Status do modulo invalido.');
  Connection := TDatabaseConnection.OpenFromEnvironment;
  try
    Reader := TPostgresErpKeyReader.Create(Connection);
    Principal := AuthenticateErpKey(AAuthorization, Reader);
    RequireErpScope(Principal, 'modules:write');
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := Connection;
      Query.SQL.Text := 'update empresas_modulos set status = :status, updated_at = now() ' +
        'where company_id = cast(:company_id as uuid) and organization_id = cast(:organization_id as uuid) ' +
        'and code = ''monitoring''';
      Query.ParamByName('status').AsString := AStatus;
      Query.ParamByName('company_id').AsString := ACompanyId;
      Query.ParamByName('organization_id').AsString := Principal.OrganizationId;
      Query.Execute;
      if Query.RowsAffected <> 1 then
        raise EArgumentException.Create('Modulo de monitoramento nao encontrado.');
    finally Query.Free; end;
  finally Connection.Free; end;
end;

end.
