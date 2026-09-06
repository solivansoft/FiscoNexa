unit Persistence.CompanyOnboarding;

interface

uses
  Application.CompanyOnboarding,
  Uni;

type
  TPostgresCompanyOnboardingWriter = class(TInterfacedObject,
    ICompanyOnboardingWriter)
  private
    FConnection: TUniConnection;
    procedure ReadCompany(const ACompanyId: string; var AResult: TCompanyOnboardingResult);
    function FindCompanyId(const ACnpj: string): string;
    function FindIntegrationId(const ACompanyId, AOrganizationId: string): string;
    function HasCommand(const ACompanyId, AIdempotencyKey: string): Boolean;
    function InsertCompany(const AData: TCompanyOnboardingData): string;
    procedure UpdateCompanyState(const ACompanyId: string;
      const AData: TCompanyOnboardingData);
    function InsertIntegration(const ACompanyId: string;
      const AData: TCompanyOnboardingData): string;
    procedure InsertCompanyOrganization(const ACompanyId: string;
      const AData: TCompanyOnboardingData);
    procedure InsertCertificate(const ACompanyId: string;
      const AData: TCompanyOnboardingData);
    procedure InsertMonitoring(const ACompanyId: string;
      const AData: TCompanyOnboardingData);
  public
    constructor Create(const AConnection: TUniConnection);
    function Save(const AData: TCompanyOnboardingData): TCompanyOnboardingResult;
  end;

implementation

uses
  Data.DB,
  System.Classes,
  System.SysUtils;

function NewQuery(const AConnection: TUniConnection): TUniQuery;
begin
  Result := TUniQuery.Create(nil);
  Result.Connection := AConnection;
end;

procedure SetBinaryParameter(const AQuery: TUniQuery; const AName: string;
  const AValue: TBytes);
var
  Stream: TBytesStream;
begin
  Stream := TBytesStream.Create(AValue);
  try
    AQuery.ParamByName(AName).LoadFromStream(Stream, ftBlob);
  finally
    Stream.Free;
  end;
end;

function TPostgresCompanyOnboardingWriter.FindCompanyId(const ACnpj: string): string;
var
  Query: TUniQuery;
begin
  Result := '';
  Query := NewQuery(FConnection);
  try
    Query.SQL.Text := 'select id::text as id from empresas where cnpj = :cnpj';
    Query.ParamByName('cnpj').AsString := ACnpj;
    Query.Open;
    if not Query.IsEmpty then
      Result := Query.FieldByName('id').AsString;
  finally
    Query.Free;
  end;
end;

function TPostgresCompanyOnboardingWriter.FindIntegrationId(const ACompanyId,
  AOrganizationId: string): string;
var
  Query: TUniQuery;
begin
  Result := '';
  Query := NewQuery(FConnection);
  try
    Query.SQL.Text :=
      'select id::text as id from integracoes ' +
      'where company_id = :company_id and organization_id = :organization_id ' +
      'and revoked_at is null order by created_at limit 1';
    Query.ParamByName('company_id').AsString := ACompanyId;
    Query.ParamByName('organization_id').AsString := AOrganizationId;
    Query.Open;
    if not Query.IsEmpty then
      Result := Query.FieldByName('id').AsString;
  finally
    Query.Free;
  end;
end;

function TPostgresCompanyOnboardingWriter.HasCommand(const ACompanyId,
  AIdempotencyKey: string): Boolean;
var
  Query: TUniQuery;
begin
  Query := NewQuery(FConnection);
  try
    Query.SQL.Text :=
      'select 1 from comandos where company_id = :company_id ' +
      'and command_type = ''start_monitoring'' ' +
      'and idempotency_key = :idempotency_key';
    Query.ParamByName('company_id').AsString := ACompanyId;
    Query.ParamByName('idempotency_key').AsString := AIdempotencyKey;
    Query.Open;
    Result := not Query.IsEmpty;
  finally
    Query.Free;
  end;
end;

function TPostgresCompanyOnboardingWriter.InsertCompany(
  const AData: TCompanyOnboardingData): string;
var
  Query: TUniQuery;
begin
  Query := NewQuery(FConnection);
  try
    Query.SQL.Text :=
      'insert into empresas (cnpj, state, legal_name) values (:cnpj, :state, :legal_name) ' +
      'returning id::text as id';
    Query.ParamByName('cnpj').AsString := AData.Certificate.Identity.Cnpj;
    Query.ParamByName('state').AsString := AData.State;
    Query.ParamByName('legal_name').AsString := AData.Certificate.Identity.Subject;
    Query.Open;
    Result := Query.FieldByName('id').AsString;
  finally
    Query.Free;
  end;
end;

procedure TPostgresCompanyOnboardingWriter.UpdateCompanyState(
  const ACompanyId: string; const AData: TCompanyOnboardingData);
var
  Query: TUniQuery;
begin
  Query := NewQuery(FConnection);
  try
    Query.SQL.Text :=
      'update empresas set state = :state, ' +
      'legal_name = coalesce(nullif(:legal_name, ''''), legal_name), ' +
      'trade_name = case when :available then :trade_name else trade_name end, ' +
      'dados_receita = coalesce(cast(nullif(:registry, '''') as jsonb), dados_receita), ' +
      'receita_consultada_em = case when :available then now() else receita_consultada_em end ' +
      'where id = cast(:company_id as uuid)';
    Query.ParamByName('legal_name').AsString := AData.Registry.LegalName;
    Query.ParamByName('trade_name').AsString := AData.Registry.TradeName;
    Query.ParamByName('registry').AsString := AData.Registry.Json;
    Query.ParamByName('available').AsBoolean := AData.Registry.Available;
    Query.ParamByName('state').AsString := AData.State;
    Query.ParamByName('company_id').AsString := ACompanyId;
    Query.ExecSQL;
  finally
    Query.Free;
  end;
end;

function TPostgresCompanyOnboardingWriter.InsertIntegration(const ACompanyId: string;
  const AData: TCompanyOnboardingData): string;
var
  Query: TUniQuery;
begin
  Query := NewQuery(FConnection);
  try
    Query.SQL.Text :=
      'insert into integracoes (company_id, organization_id, display_name, api_token_hash) ' +
      'values (:company_id, :organization_id, :display_name, :api_token_hash) ' +
      'returning id::text as id';
    Query.ParamByName('company_id').AsString := ACompanyId;
    Query.ParamByName('organization_id').AsString := AData.ErpKey.OrganizationId;
    Query.ParamByName('display_name').AsString := 'ERP';
    Query.ParamByName('api_token_hash').AsString := AData.IntegrationTokenHash;
    Query.Open;
    Result := Query.FieldByName('id').AsString;
  finally
    Query.Free;
  end;
end;

procedure TPostgresCompanyOnboardingWriter.InsertCompanyOrganization(
  const ACompanyId: string; const AData: TCompanyOnboardingData);
var
  Query: TUniQuery;
begin
  Query := NewQuery(FConnection);
  try
    Query.SQL.Text :=
      'insert into empresas_organizacoes (company_id, organization_id, relationship_type) ' +
      'values (:company_id, :organization_id, ''erp'') on conflict do nothing';
    Query.ParamByName('company_id').AsString := ACompanyId;
    Query.ParamByName('organization_id').AsString := AData.ErpKey.OrganizationId;
    Query.Execute;
  finally
    Query.Free;
  end;
end;

procedure TPostgresCompanyOnboardingWriter.InsertCertificate(const ACompanyId: string;
  const AData: TCompanyOnboardingData);
var
  Query: TUniQuery;
begin
  Query := NewQuery(FConnection);
  try
    Query.SQL.Text :=
      'update certificados set revoked_at = now() ' +
      'where company_id = :company_id and revoked_at is null and lower(sha256) <> :sha256';
    Query.ParamByName('company_id').AsString := ACompanyId;
    Query.ParamByName('sha256').AsString := AData.CertificateSha256;
    Query.Execute;
    Query.SQL.Text :=
      'insert into certificados (company_id, uploaded_by_key_id, encryption_key_ref, ' +
      'encrypted_data_key, encrypted_certificate, certificate_nonce, certificate_tag, ' +
      'encrypted_password, password_nonce, password_tag, sha256, subject, valid_until) ' +
      'values (:company_id, :key_id, :key_ref, :data_key, :certificate, :certificate_nonce, ' +
      ':certificate_tag, :password, :password_nonce, :password_tag, :sha256, :subject, :valid_until) ' +
      'on conflict (sha256) do update set revoked_at = null, valid_until = excluded.valid_until, ' +
      'encryption_key_ref = excluded.encryption_key_ref, encrypted_data_key = excluded.encrypted_data_key, ' +
      'encrypted_certificate = excluded.encrypted_certificate, certificate_nonce = excluded.certificate_nonce, ' +
      'certificate_tag = excluded.certificate_tag, encrypted_password = excluded.encrypted_password, ' +
      'password_nonce = excluded.password_nonce, password_tag = excluded.password_tag, ' +
      'subject = excluded.subject, uploaded_by_key_id = excluded.uploaded_by_key_id';
    Query.ParamByName('company_id').AsString := ACompanyId;
    Query.ParamByName('key_id').AsString := AData.ErpKey.KeyId;
    Query.ParamByName('key_ref').AsString := AData.Certificate.Envelope.EncryptionKeyReference;
    SetBinaryParameter(Query, 'data_key', AData.Certificate.Envelope.EncryptedDataKey);
    SetBinaryParameter(Query, 'certificate', AData.Certificate.Envelope.EncryptedCertificate.Ciphertext);
    SetBinaryParameter(Query, 'certificate_nonce', AData.Certificate.Envelope.EncryptedCertificate.Nonce);
    SetBinaryParameter(Query, 'certificate_tag', AData.Certificate.Envelope.EncryptedCertificate.Tag);
    SetBinaryParameter(Query, 'password', AData.Certificate.Envelope.EncryptedPassword.Ciphertext);
    SetBinaryParameter(Query, 'password_nonce', AData.Certificate.Envelope.EncryptedPassword.Nonce);
    SetBinaryParameter(Query, 'password_tag', AData.Certificate.Envelope.EncryptedPassword.Tag);
    Query.ParamByName('sha256').AsString := AData.CertificateSha256;
    Query.ParamByName('subject').AsString := AData.Certificate.Identity.Subject;
    Query.ParamByName('valid_until').AsDateTime := AData.Certificate.Identity.ValidUntil;
    Query.Execute;
  finally
    Query.Free;
  end;
end;

procedure TPostgresCompanyOnboardingWriter.InsertMonitoring(const ACompanyId: string;
  const AData: TCompanyOnboardingData);
var
  Query: TUniQuery;
begin
  Query := NewQuery(FConnection);
  try
    Query.SQL.Text :=
      'insert into configuracoes_monitoramento (company_id) values (:company_id) on conflict do nothing';
    Query.ParamByName('company_id').AsString := ACompanyId;
    Query.Execute;
    Query.SQL.Text :=
      'insert into status_monitoramento (company_id, status) values (:company_id, ''active'') ' +
      'on conflict do nothing';
    Query.ParamByName('company_id').AsString := ACompanyId;
    Query.Execute;
    Query.SQL.Text :=
      'insert into empresas_modulos (company_id, organization_id, code, status) ' +
      'values (:company_id, :organization_id, ''monitoring'', ''active'') on conflict do nothing';
    Query.ParamByName('company_id').AsString := ACompanyId;
    Query.ParamByName('organization_id').AsString := AData.ErpKey.OrganizationId;
    Query.Execute;
    Query.SQL.Text :=
      'insert into comandos (company_id, command_type, idempotency_key) ' +
      'values (:company_id, ''start_monitoring'', :idempotency_key) on conflict do nothing';
    Query.ParamByName('company_id').AsString := ACompanyId;
    Query.ParamByName('idempotency_key').AsString := AData.IdempotencyKey;
    Query.Execute;
  finally
    Query.Free;
  end;
end;

constructor TPostgresCompanyOnboardingWriter.Create(const AConnection: TUniConnection);
begin
  inherited Create;
  if AConnection = nil then
    raise EArgumentNilException.Create('Conexao PostgreSQL nao informada.');
  FConnection := AConnection;
end;

function TPostgresCompanyOnboardingWriter.Save(
  const AData: TCompanyOnboardingData): TCompanyOnboardingResult;
var
  CompanyId: string;
  IntegrationId: string;
begin
  Result := Default(TCompanyOnboardingResult);
  FConnection.StartTransaction;
  try
    CompanyId := FindCompanyId(AData.Certificate.Identity.Cnpj);
    if CompanyId <> '' then
    begin
      IntegrationId := FindIntegrationId(CompanyId, AData.ErpKey.OrganizationId);
      if (IntegrationId <> '') and HasCommand(CompanyId, AData.IdempotencyKey) then
      begin
        Result.CompanyId := CompanyId;
        Result.IntegrationId := IntegrationId;
        Result.Replayed := True;
        UpdateCompanyState(CompanyId, AData);
        ReadCompany(CompanyId, Result);
        FConnection.Commit;
        Exit;
      end;
    end
    else
      CompanyId := InsertCompany(AData);

    UpdateCompanyState(CompanyId, AData);

    InsertCompanyOrganization(CompanyId, AData);
    IntegrationId := FindIntegrationId(CompanyId, AData.ErpKey.OrganizationId);
    if IntegrationId = '' then
    begin
      IntegrationId := InsertIntegration(CompanyId, AData);
      Result.IntegrationTokenCreated := True;
    end;
    InsertCertificate(CompanyId, AData);
    InsertMonitoring(CompanyId, AData);
    Result.CompanyId := CompanyId;
    Result.IntegrationId := IntegrationId;
    ReadCompany(CompanyId, Result);
    FConnection.Commit;
  except
    FConnection.Rollback;
    raise;
  end;
end;

procedure TPostgresCompanyOnboardingWriter.ReadCompany(const ACompanyId: string;
  var AResult: TCompanyOnboardingResult);
var Query: TUniQuery;
begin
  Query := NewQuery(FConnection);
  try
    Query.SQL.Text := 'select state, legal_name, trade_name, dados_receita::text as registry ' +
      'from empresas where id = cast(:id as uuid)';
    Query.ParamByName('id').AsString := ACompanyId;
    Query.Open;
    AResult.State := Query.FieldByName('state').AsString;
    AResult.LegalName := Query.FieldByName('legal_name').AsString;
    AResult.TradeName := Query.FieldByName('trade_name').AsString;
    AResult.RegistryJson := Query.FieldByName('registry').AsString;
  finally Query.Free; end;
end;

end.
