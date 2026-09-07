unit Application.ErpIntegration;

interface

uses
  System.SysUtils;

type
  EErpIntegrationUnauthorized = class(Exception);
  EErpIntegrationForbidden = class(Exception);

  TErpIntegrationPrincipal = record
    IntegrationId: string;
    CompanyId: string;
  end;

function AuthenticateErpToken(const AAuthorization: string): TErpIntegrationPrincipal;
function ParseErpBearerToken(const AAuthorization: string): string;

implementation

uses
  Data.DB,
  System.Hash,
  Application.Authorization,
  Database.Connection,
  FireDAC.Stan.Param, FireDAC.Comp.Client;

function ParseErpBearerToken(const AAuthorization: string): string;
begin
  Result := ParseBearerToken(AAuthorization);
end;

function AuthenticateErpToken(const AAuthorization: string): TErpIntegrationPrincipal;
var
  Connection: TFDConnection;
  Query: TFDQuery;
  Token: string;
  TokenHash: string;
begin
  Token := ParseErpBearerToken(AAuthorization);
  if Token = '' then
    raise EErpIntegrationUnauthorized.Create('Token de integracao ausente ou invalido.');

  TokenHash := THashSHA2.GetHashString(Token).ToLowerInvariant;
  Connection := TDatabaseConnection.OpenFromEnvironment;
  try
    Query := TFDQuery.Create(nil);
    try
      Query.Connection := Connection;
      Query.SQL.Text :=
        'select id::text as id, company_id::text as company_id, ' +
        '(scopes @> ''["documents:read"]''::jsonb) as allowed ' +
        'from integracoes ' +
        'where lower(api_token_hash) = :api_token_hash and revoked_at is null';
      Query.ParamByName('api_token_hash').AsString := TokenHash;
      Query.Open;
      if Query.IsEmpty then
        raise EErpIntegrationUnauthorized.Create('Token de integracao ausente ou invalido.');

      if not Query.FieldByName('allowed').AsBoolean then
        raise EErpIntegrationForbidden.Create('Escopo de leitura ausente.');
      Result.IntegrationId := Query.FieldByName('id').AsString;
      Result.CompanyId := Query.FieldByName('company_id').AsString;
    finally
      Query.Free;
    end;
  finally
    Connection.Free;
  end;
end;

end.
