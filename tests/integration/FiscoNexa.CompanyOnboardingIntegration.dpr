program FiscoNexa.CompanyOnboardingIntegration;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  FireDAC.Stan.Param, FireDAC.Comp.Client,
  Application.CertificateEnvelope in '..\..\src\application\Application.CertificateEnvelope.pas',
  Application.CertificateIdentity in '..\..\src\application\Application.CertificateIdentity.pas',
  Application.CertificateRegistration in '..\..\src\application\Application.CertificateRegistration.pas',
  Application.CompanyOnboarding in '..\..\src\application\Application.CompanyOnboarding.pas',
  Application.ErpKeys in '..\..\src\application\Application.ErpKeys.pas',
  Database.Connection in '..\..\src\db\Database.Connection.pas',
  Persistence.CompanyOnboarding in '..\..\src\persistence\Persistence.CompanyOnboarding.pas';

procedure Require(const ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise EInvalidOpException.Create(AMessage);
end;

procedure CreateFixture(const AConnection: TFDConnection; out AOrganizationId,
  AKeyId: string);
var
  Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text :=
      'with organization as (insert into organizacoes (legal_name, organization_type) ' +
      'values (''ERP onboarding smoke'', ''erp'') returning id) ' +
      'insert into chaves_erp (organization_id, label, key_hash, scopes) ' +
      'select id, ''Smoke'', ''smoke-hash'', ''["companies:onboard"]''::jsonb from organization ' +
      'returning id::text as key_id, organization_id::text as organization_id';
    Query.Open;
    AOrganizationId := Query.FieldByName('organization_id').AsString;
    AKeyId := Query.FieldByName('key_id').AsString;
  finally
    Query.Free;
  end;
end;

function CountRows(const AConnection: TFDConnection; const ASql, ACompanyId: string): Integer;
var
  Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text := ASql;
    Query.ParamByName('company_id').AsString := ACompanyId;
    Query.Open;
    Result := Query.Fields[0].AsInteger;
  finally
    Query.Free;
  end;
end;

procedure DeleteFixture(const AConnection: TFDConnection; const AOrganizationId,
  ACnpj: string);
var
  Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text := 'delete from organizacoes where id::text = :id';
    Query.ParamByName('id').AsString := AOrganizationId;
    Query.Execute;
    Query.SQL.Text := 'delete from empresas where cnpj = :cnpj';
    Query.ParamByName('cnpj').AsString := ACnpj;
    Query.Execute;
  finally
    Query.Free;
  end;
end;

var
  Connection: TFDConnection;
  Writer: ICompanyOnboardingWriter;
  Data: TCompanyOnboardingData;
  FirstResult: TCompanyOnboardingResult;
  SecondResult: TCompanyOnboardingResult;
  OrganizationId: string;
  KeyId: string;
  Cnpj: string;
begin
  OrganizationId := '';
  KeyId := '';
  Cnpj := '98' + FormatDateTime('yymmddhhnnss', Now);
  Connection := TDatabaseConnection.OpenFromEnvironment;
  try
    CreateFixture(Connection, OrganizationId, KeyId);
    Data.ErpKey.OrganizationId := OrganizationId;
    Data.ErpKey.KeyId := KeyId;
    Data.IdempotencyKey := 'onboarding-smoke-1';
    Data.State := 'PA';
    Data.Registry.Available := True;
    Data.Registry.LegalName := 'Empresa Receita teste';
    Data.Registry.TradeName := 'Fantasia teste';
    Data.Registry.Json := '{"nome":"Empresa Receita teste","uf":"PA","logradouro":"Rua teste"}';
    Data.CertificateSha256 := 'smoke-' + Cnpj;
    Data.Certificate.Identity.Cnpj := Cnpj;
    Data.Certificate.Identity.Subject := 'Empresa onboarding smoke';
    Data.Certificate.Identity.ValidUntil := EncodeDate(2030, 1, 1);
    Data.Certificate.Envelope.EncryptionKeyReference := 'kms-smoke';
    Data.Certificate.Envelope.EncryptedDataKey := TBytes.Create(1);
    Data.Certificate.Envelope.EncryptedCertificate.Ciphertext := TBytes.Create(2);
    Data.Certificate.Envelope.EncryptedCertificate.Nonce := TBytes.Create(3);
    Data.Certificate.Envelope.EncryptedCertificate.Tag := TBytes.Create(4);
    Data.Certificate.Envelope.EncryptedPassword.Ciphertext := TBytes.Create(5);
    Data.Certificate.Envelope.EncryptedPassword.Nonce := TBytes.Create(6);
    Data.Certificate.Envelope.EncryptedPassword.Tag := TBytes.Create(7);
    Data.IntegrationTokenHash := 'token-' + Cnpj;
    Writer := TPostgresCompanyOnboardingWriter.Create(Connection);
    FirstResult := Writer.Save(Data);
    Require(FirstResult.LegalName = 'Empresa Receita teste', 'Razao social nao persistida.');
    Require(Pos('logradouro', FirstResult.RegistryJson) > 0, 'Cadastro Receita incompleto.');
    Data.Registry.Available := False;
    Data.Registry.LegalName := '';
    Data.Registry.TradeName := '';
    Data.Registry.Json := '';
    SecondResult := Writer.Save(Data);
    Require(SecondResult.LegalName = FirstResult.LegalName, 'Falha externa apagou razao social.');
    Require(SecondResult.RegistryJson = FirstResult.RegistryJson, 'Replay apagou cadastro.');
    Require(not FirstResult.Replayed, 'Primeiro onboarding foi marcado como repetido.');
    Require(FirstResult.IntegrationTokenCreated, 'Primeiro onboarding nao criou token.');
    Require(SecondResult.Replayed, 'Reenvio nao foi reconhecido como repeticao.');
    Require(FirstResult.CompanyId = SecondResult.CompanyId, 'Reenvio criou outra empresa.');
    Require(CountRows(Connection, 'select count(*) from certificados where company_id = :company_id',
      FirstResult.CompanyId) = 1, 'Reenvio duplicou certificado.');
    Require(CountRows(Connection, 'select count(*) from integracoes where company_id = :company_id',
      FirstResult.CompanyId) = 1, 'Reenvio duplicou integracao.');
    Require(CountRows(Connection, 'select count(*) from empresas_modulos where company_id = :company_id',
      FirstResult.CompanyId) = 1, 'Reenvio duplicou modulo.');
    Require(CountRows(Connection, 'select count(*) from comandos where company_id = :company_id',
      FirstResult.CompanyId) = 1, 'Reenvio duplicou comando.');
    Writeln('Smoke onboarding aprovado: transacao idempotente sem registros duplicados.');
  finally
    if OrganizationId <> '' then
      DeleteFixture(Connection, OrganizationId, Cnpj);
    Connection.Free;
  end;
end.
