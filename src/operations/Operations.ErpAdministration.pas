unit Operations.ErpAdministration;

interface

uses Application.ErpAdministration;

function CreateErp(const AAuthorization, ALegalName, AKeyLabel: string): TErpKeyIssue;
function RotateErpKey(const AAuthorization, AErpId, AKeyLabel: string): TErpKeyIssue;
procedure RevokeErpKey(const AAuthorization, AErpId, AKeyId: string);

implementation

uses
  Application.Authentication,
  Database.Connection,
  Operations.Authentication,
  Persistence.ErpAdministration,
  Uni;

function CreateService(out AConnection: TUniConnection): TErpAdministrationService;
var
  Store: IErpAdministrationStore;
begin
  AConnection := TDatabaseConnection.OpenFromEnvironment;
  Store := TPostgresErpAdministrationStore.Create(AConnection);
  Result := TErpAdministrationService.Create(Store);
end;

function CreateErp(const AAuthorization, ALegalName, AKeyLabel: string): TErpKeyIssue;
var
  Connection: TUniConnection;
  Service: TErpAdministrationService;
begin
  RequireSuperadmin(AAuthorization);
  Service := CreateService(Connection);
  try
    Result := Service.CreateErp(ALegalName, AKeyLabel);
  finally
    Service.Free;
    Connection.Free;
  end;
end;

function RotateErpKey(const AAuthorization, AErpId, AKeyLabel: string): TErpKeyIssue;
var
  Connection: TUniConnection;
  Service: TErpAdministrationService;
begin
  RequireSuperadmin(AAuthorization);
  Service := CreateService(Connection);
  try
    Result := Service.RotateKey(AErpId, AKeyLabel);
  finally
    Service.Free;
    Connection.Free;
  end;
end;

procedure RevokeErpKey(const AAuthorization, AErpId, AKeyId: string);
var
  Connection: TUniConnection;
  Service: TErpAdministrationService;
begin
  RequireSuperadmin(AAuthorization);
  Service := CreateService(Connection);
  try
    Service.RevokeKey(AErpId, AKeyId);
  finally
    Service.Free;
    Connection.Free;
  end;
end;

end.
