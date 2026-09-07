unit Application.CommercialAccess;

interface

uses System.SysUtils;

type
  ELicenseUnauthorized = class(Exception);
  ELicenseValidation = class(Exception);
  ELicenseCompanyNotFound = class(Exception);
  ECommercialAccessRestricted = class(Exception);

  TCommercialAccessUpdate = record
    CompanyId: string;
    Status: string;
    AccessGrantedUntil: string;
    MonitoringProtectedUntil: string;
    Reference: string;
    SourceVersion: Int64;
  end;

  TCommercialAccessResult = record
    Replayed: Boolean;
    Status: string;
    AccessGrantedUntil: string;
    MonitoringProtectedUntil: string;
    SourceVersion: Int64;
  end;

procedure AuthenticateLicenseSystem(const AAuthorization: string);
procedure ValidateCommercialAccessUpdate(const AUpdate: TCommercialAccessUpdate);

implementation

uses
  Application.Authorization,
  System.Hash,
  System.DateUtils;

procedure AuthenticateLicenseSystem(const AAuthorization: string);
var
  Token, ExpectedHash: string;
begin
  Token := ParseBearerToken(AAuthorization);
  ExpectedHash := LowerCase(Trim(GetEnvironmentVariable(
    'FISCONEXA_LICENSE_TOKEN_SHA256')));
  if (Token = '') or (ExpectedHash = '') or
    not SameText(THashSHA2.GetHashString(Token), ExpectedHash) then
    raise ELicenseUnauthorized.Create('Sistema de licencas nao autorizado.');
end;

procedure ValidateOptionalTimestamp(const AValue, AFieldName: string);
begin
  if AValue = '' then
    Exit;
  if (Length(AValue) < 20) or ((AValue[Length(AValue)] <> 'Z') and
    ((Length(AValue) < 25) or not CharInSet(AValue[Length(AValue)-5], ['+', '-']))) then
    raise ELicenseValidation.Create(AFieldName + ' exige fuso horario.');
  try
    ISO8601ToDate(AValue, False);
  except
    on E: EConvertError do
      raise ELicenseValidation.Create(AFieldName + ' invalido.');
  end;
end;

procedure ValidateCommercialAccessUpdate(const AUpdate: TCommercialAccessUpdate);
var Id: TGUID;
begin
  try
    Id := StringToGUID('{' + AUpdate.CompanyId + '}');
  except
    on E: EConvertError do raise ELicenseValidation.Create('Empresa invalida.');
  end;
  if (AUpdate.Status <> 'liberado') and (AUpdate.Status <> 'restrito') then
    raise ELicenseValidation.Create('Situacao comercial invalida.');
  if Trim(AUpdate.Reference) = '' then
    raise ELicenseValidation.Create('Referencia obrigatoria.');
  if AUpdate.SourceVersion < 0 then
    raise ELicenseValidation.Create('Versao da origem invalida.');
  ValidateOptionalTimestamp(AUpdate.AccessGrantedUntil,
    'acesso_liberado_ate');
  ValidateOptionalTimestamp(AUpdate.MonitoringProtectedUntil,
    'proteger_monitoramento_ate');
end;

end.
