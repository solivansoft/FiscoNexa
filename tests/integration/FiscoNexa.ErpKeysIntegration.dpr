program FiscoNexa.ErpKeysIntegration;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Uni,
  Application.ErpKeys in '..\..\src\application\Application.ErpKeys.pas',
  Application.Authorization in '..\..\src\application\Application.Authorization.pas',
  Database.Connection in '..\..\src\db\Database.Connection.pas',
  Persistence.ErpKeys in '..\..\src\persistence\Persistence.ErpKeys.pas';

procedure Fail(const AMessage: string);
begin
  raise EInvalidOpException.Create(AMessage);
end;

procedure InsertFixture(const AConnection: TUniConnection; const AToken: string;
  out AOrganizationId: string);
var
  Query: TUniQuery;
begin
  Query := TUniQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text :=
      'with organization as (insert into organizacoes (legal_name, organization_type) ' +
      'values (:legal_name, ''erp'') returning id) ' +
      'insert into chaves_erp (organization_id, label, key_hash, scopes) ' +
      'select id, ''Smoke ERP'', :key_hash, ''["companies:onboard"]''::jsonb ' +
      'from organization returning organization_id::text as organization_id';
    Query.ParamByName('legal_name').AsString := 'Smoke ERP ' + TGUID.NewGuid.ToString;
    Query.ParamByName('key_hash').AsString := HashErpKey(AToken);
    Query.Open;
    AOrganizationId := Query.FieldByName('organization_id').AsString;
  finally
    Query.Free;
  end;
end;

procedure RevokeFixture(const AConnection: TUniConnection; const AToken: string);
var
  Query: TUniQuery;
begin
  Query := TUniQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text := 'update chaves_erp set revoked_at = now() where key_hash = :key_hash';
    Query.ParamByName('key_hash').AsString := HashErpKey(AToken);
    Query.Execute;
  finally
    Query.Free;
  end;
end;

procedure InsertTenantToken(const AConnection: TUniConnection; const AToken: string;
  out ACompanyId: string);
var
  Query: TUniQuery;
  Cnpj: string;
begin
  Cnpj := '99' + FormatDateTime('yymmddhhnnss', Now);
  Query := TUniQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text :=
      'with company as (insert into empresas (cnpj, legal_name) ' +
      'values (:cnpj, ''Empresa Token Tenant'') returning id) ' +
      'insert into integracoes (company_id, display_name, api_token_hash) ' +
      'select id, ''Tenant Smoke'', :token_hash from company ' +
      'returning company_id::text as company_id';
    Query.ParamByName('cnpj').AsString := Cnpj;
    Query.ParamByName('token_hash').AsString := HashErpKey(AToken);
    Query.Open;
    ACompanyId := Query.FieldByName('company_id').AsString;
  finally
    Query.Free;
  end;
end;

procedure DeleteFixture(const AConnection: TUniConnection;
  const AOrganizationId: string);
var
  Query: TUniQuery;
begin
  Query := TUniQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text := 'delete from organizacoes where id::text = :organization_id';
    Query.ParamByName('organization_id').AsString := AOrganizationId;
    Query.Execute;
  finally
    Query.Free;
  end;
end;

procedure DeleteTenantFixture(const AConnection: TUniConnection;
  const ACompanyId: string);
var
  Query: TUniQuery;
begin
  Query := TUniQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text := 'delete from empresas where id::text = :company_id';
    Query.ParamByName('company_id').AsString := ACompanyId;
    Query.Execute;
  finally
    Query.Free;
  end;
end;

procedure VerifyRevokedKeyIsRejected(const AReader: IErpKeyReader;
  const AToken: string);
begin
  try
    AuthenticateErpKey('Bearer ' + AToken, AReader);
    Fail('Chave revogada foi aceita.');
  except
    on E: EErpKeyUnauthorized do
      Exit;
  end;
end;

procedure VerifyTenantTokenIsRejected(const AReader: IErpKeyReader;
  const AToken: string);
begin
  try
    AuthenticateErpKey('Bearer ' + AToken, AReader);
    Fail('Token de tenant foi aceito como chave de ERP.');
  except
    on E: EErpKeyUnauthorized do
      Exit;
  end;
end;

var
  Connection: TUniConnection;
  Reader: IErpKeyReader;
  Principal: TErpKeyPrincipal;
  OrganizationId: string;
  CompanyId: string;
  Token: string;
  TenantToken: string;
begin
  Connection := TDatabaseConnection.OpenFromEnvironment;
  OrganizationId := '';
  CompanyId := '';
  Token := 'fnx-smoke-' + TGUID.NewGuid.ToString;
  TenantToken := 'fnx-tenant-' + TGUID.NewGuid.ToString;
  try
    InsertFixture(Connection, Token, OrganizationId);
    InsertTenantToken(Connection, TenantToken, CompanyId);
    Reader := TPostgresErpKeyReader.Create(Connection);
    Principal := AuthenticateErpKey('Bearer ' + Token, Reader);
    if Principal.OrganizationId <> OrganizationId then
      Fail('A chave retornou a organizacao errada.');
    RequireErpScope(Principal, 'companies:onboard');
    VerifyTenantTokenIsRejected(Reader, TenantToken);
    RevokeFixture(Connection, Token);
    VerifyRevokedKeyIsRejected(Reader, Token);
    Writeln('Smoke ERP key aprovado: chave valida autenticada e chave revogada recusada.');
  finally
    if CompanyId <> '' then
      DeleteTenantFixture(Connection, CompanyId);
    if OrganizationId <> '' then
      DeleteFixture(Connection, OrganizationId);
    Connection.Free;
  end;
end.
