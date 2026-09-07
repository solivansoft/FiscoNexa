unit Operations.CommercialAccess;

interface

uses Application.CommercialAccess;

function UpdateCommercialAccess(const AAuthorization: string;
  const AUpdate: TCommercialAccessUpdate): TCommercialAccessResult;
procedure RequireCommercialDelivery(const ACompanyId: string;
  out AProtectedUntil: string);

implementation

uses
  Database.Connection,
  Persistence.CommercialAccess,
  FireDAC.Comp.Client;

function UpdateCommercialAccess(const AAuthorization: string;
  const AUpdate: TCommercialAccessUpdate): TCommercialAccessResult;
var C: TFDConnection;
begin
  AuthenticateLicenseSystem(AAuthorization);
  C := TDatabaseConnection.OpenFromEnvironment;
  try Result := SalvarLicenca(C, AUpdate); finally C.Free; end;
end;

procedure RequireCommercialDelivery(const ACompanyId: string;
  out AProtectedUntil: string);
var C: TFDConnection;
begin
  C := TDatabaseConnection.OpenFromEnvironment;
  try
    if not EntregaComercialPermitida(C, ACompanyId, AProtectedUntil) then
      raise ECommercialAccessRestricted.Create('Acesso comercial restrito.');
  finally C.Free; end;
end;

end.
