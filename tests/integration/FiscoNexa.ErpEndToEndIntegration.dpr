program FiscoNexa.ErpEndToEndIntegration;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  Data.DB,
  System.Generics.Collections,
  System.IOUtils,
  System.JSON,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.NetEncoding,
  System.SysUtils,
  Uni,
  Application.ErpKeys in '..\..\src\application\Application.ErpKeys.pas',
  Application.MonitorCycle in '..\..\src\application\Application.MonitorCycle.pas',
  Database.Connection in '..\..\src\db\Database.Connection.pas',
  Integrations.AwsSignature in '..\..\src\integrations\Integrations.AwsSignature.pas',
  Integrations.AwsS3Xml in '..\..\src\integrations\Integrations.AwsS3Xml.pas';

procedure Require(const ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise EInvalidOpException.Create(AMessage);
end;

function EnvironmentValue(const AName: string; const ARequired: Boolean = True): string;
begin
  Result := Trim(GetEnvironmentVariable(AName));
  if ARequired and (Result = '') then
    raise EInvalidOpException.Create('Variavel obrigatoria ausente: ' + AName);
end;

function ApiUrl: string;
begin
  Result := EnvironmentValue('FISCONEXA_API_URL', False);
  if Result = '' then
    Result := 'http://127.0.0.1:9000';
  Result := Result.TrimRight(['/']);
end;

function Headers(const AToken, AIdempotencyKey: string): TNetHeaders;
begin
  SetLength(Result, 1);
  Result[0] := TNameValuePair.Create('Authorization', 'Bearer ' + AToken);
  if AIdempotencyKey <> '' then
  begin
    SetLength(Result, 2);
    Result[1] := TNameValuePair.Create('Idempotency-Key', AIdempotencyKey);
  end;
end;

procedure RequireSuccess(const AResponse: IHTTPResponse; const AOperation: string);
begin
  if (AResponse.StatusCode < 200) or (AResponse.StatusCode >= 300) then
    raise EInvalidOpException.CreateFmt('%s retornou HTTP %d: %s', [AOperation,
      AResponse.StatusCode, AResponse.ContentAsString(TEncoding.UTF8)]);
end;

function PostJson(const AClient: THTTPClient; const AUrl, AToken,
  AIdempotencyKey, ABody: string): string;
var
  Source: TStringStream;
  Response: IHTTPResponse;
begin
  Source := TStringStream.Create(ABody, TEncoding.UTF8, False);
  try
    Response := AClient.Post(AUrl, Source, nil, Headers(AToken, AIdempotencyKey));
  finally
    Source.Free;
  end;
  RequireSuccess(Response, 'POST ' + AUrl);
  Result := Response.ContentAsString(TEncoding.UTF8);
end;

function GetJson(const AClient: THTTPClient; const AUrl, AToken: string): string;
var
  Response: IHTTPResponse;
begin
  Response := AClient.Get(AUrl, nil, Headers(AToken, ''));
  RequireSuccess(Response, 'GET ' + AUrl);
  Result := Response.ContentAsString(TEncoding.UTF8);
end;

function JsonString(const AJson: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Value := AJson.GetValue(AName);
  if Value = nil then
    raise EInvalidOpException.Create('JSON sem campo obrigatorio: ' + AName);
  Result := Value.Value;
end;

procedure InsertBootstrapKey(const AConnection: TUniConnection; const AToken: string;
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
      'select id, ''ERP e2e'', :key_hash, ''["companies:onboard","modules:write"]''::jsonb ' +
      'from organization returning organization_id::text as organization_id';
    Query.ParamByName('legal_name').AsString := 'ERP e2e ' + TGUID.NewGuid.ToString;
    Query.ParamByName('key_hash').AsString := HashErpKey(AToken);
    Query.Open;
    AOrganizationId := Query.FieldByName('organization_id').AsString;
  finally
    Query.Free;
  end;
end;

function CompanyCnpj(const AConnection: TUniConnection; const ACompanyId: string): string;
var
  Query: TUniQuery;
begin
  Query := TUniQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text := 'select cnpj from empresas where id = cast(:company_id as uuid)';
    Query.ParamByName('company_id').AsString := ACompanyId;
    Query.Open;
    Require(not Query.IsEmpty, 'Empresa do onboarding nao foi encontrada.');
    Result := Query.Fields[0].AsString;
  finally
    Query.Free;
  end;
end;

function InsertDocument(const AConnection: TUniConnection; const ACompanyId,
  AAccessKey, AObjectKey, ASha256: string): string;
var
  Query: TUniQuery;
begin
  Query := TUniQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text :=
      'insert into documentos (company_id, access_key, document_type, issuer_cnpj, ' +
      'total_amount, status, xml_object_key, xml_sha256) ' +
      'values (cast(:company_id as uuid), :access_key, ''nfe'', ''12345678000190'', ' +
      '100.00, ''xml_available'', :object_key, :sha256) returning id::text as id';
    Query.ParamByName('company_id').AsString := ACompanyId;
    Query.ParamByName('access_key').AsString := AAccessKey;
    Query.ParamByName('object_key').AsString := AObjectKey;
    Query.ParamByName('sha256').AsString := ASha256;
    Query.Open;
    Result := Query.FieldByName('id').AsString;
  finally
    Query.Free;
  end;
end;

procedure DeleteFixtures(const AConnection: TUniConnection; const ACompanyId,
  AOrganizationId: string);
var
  Query: TUniQuery;
begin
  Query := TUniQuery.Create(nil);
  try
    Query.Connection := AConnection;
    if ACompanyId <> '' then
    begin
      Query.SQL.Text := 'delete from empresas where id = cast(:company_id as uuid)';
      Query.ParamByName('company_id').AsString := ACompanyId;
      Query.Execute;
    end;
    if AOrganizationId <> '' then
    begin
      Query.SQL.Text := 'delete from organizacoes where id = cast(:organization_id as uuid)';
      Query.ParamByName('organization_id').AsString := AOrganizationId;
      Query.Execute;
    end;
  finally
    Query.Free;
  end;
end;

procedure VerifyModuleSuspended(const AConnection: TUniConnection;
  const ACompanyId: string);
var
  Query: TUniQuery;
begin
  Query := TUniQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text := 'select status from empresas_modulos where company_id = cast(:company_id as uuid) ' +
      'and code = ''monitoring''';
    Query.ParamByName('company_id').AsString := ACompanyId;
    Query.Open;
    Require((not Query.IsEmpty) and SameText(Query.Fields[0].AsString, 'suspended'),
      'Suspensao do modulo nao foi persistida.');
  finally
    Query.Free;
  end;
end;

var
  Connection: TUniConnection;
  Client: THTTPClient;
  Storage: TAwsS3XmlStorage;
  Payload: TJSONObject;
  ResponseJson: TJSONObject;
  MonitoringJson: TJSONObject;
  DocumentsJson: TJSONObject;
  Items: TJSONArray;
  Response: IHTTPResponse;
  CertificateBytes: TBytes;
  PasswordBytes: TBytes;
  BootstrapToken: string;
  TenantToken: string;
  OrganizationId: string;
  CompanyId: string;
  DocumentId: string;
  ObjectKey: string;
  Stored: TStoredXml;
  Xml: string;
  AccessKey: string;
  OnboardingResponse: string;
  LastNsu: string;
  ModuleBody: TStringStream;
begin
  OrganizationId := '';
  CompanyId := '';
  ObjectKey := '';
  BootstrapToken := 'fnx-e2e-' + TGUID.NewGuid.ToString;
  AccessKey := '35' + StringOfChar('8', 42);
  Xml := '<nfeProc><NFe><infNFe Id="NFe35123456789012345678901234567890123456789012"/></NFe></nfeProc>';
  CertificateBytes := TFile.ReadAllBytes(EnvironmentValue('FISCONEXA_TEST_PFX_PATH'));
  PasswordBytes := TEncoding.UTF8.GetBytes(EnvironmentValue('FISCONEXA_TEST_PFX_PASSWORD'));
  Connection := TDatabaseConnection.OpenFromEnvironment;
  Client := THTTPClient.Create;
  Storage := nil;
  try
    InsertBootstrapKey(Connection, BootstrapToken, OrganizationId);
    Payload := TJSONObject.Create;
    try
      Payload.AddPair('uf', 'PA');
      Payload.AddPair('certificado_a1_base64',
        TNetEncoding.Base64.EncodeBytesToString(CertificateBytes));
      Payload.AddPair('senha_certificado_base64',
        TNetEncoding.Base64.EncodeBytesToString(PasswordBytes));
      OnboardingResponse := PostJson(Client, ApiUrl + '/v1/empresas', BootstrapToken,
        'erp-e2e-' + TGUID.NewGuid.ToString, Payload.ToJSON);
    finally
      Payload.Free;
    end;
    ResponseJson := TJSONObject.ParseJSONValue(OnboardingResponse) as TJSONObject;
    try
      Require(ResponseJson <> nil, 'Onboarding retornou JSON invalido.');
      CompanyId := JsonString(ResponseJson, 'id_empresa');
      TenantToken := JsonString(ResponseJson, 'token_integracao');
      Require(TenantToken <> '', 'Onboarding nao retornou token do tenant.');
    finally
      ResponseJson.Free;
    end;

    MonitoringJson := TJSONObject.ParseJSONValue(GetJson(Client,
      ApiUrl + '/v1/monitoramento', TenantToken)) as TJSONObject;
    try
      Require(MonitoringJson <> nil, 'Monitoramento retornou JSON invalido.');
      Require(SameText(JsonString(MonitoringJson, 'situacao'), 'ativo'),
        'Onboarding nao iniciou monitoramento ativo.');
    finally
      MonitoringJson.Free;
    end;

    Storage := TAwsS3XmlStorage.CreateFromEnvironment;
    Stored := Storage.Put(CompanyCnpj(Connection, CompanyId), AccessKey, Xml);
    ObjectKey := Stored.ObjectKey;
    DocumentId := InsertDocument(Connection, CompanyId, AccessKey, Stored.ObjectKey, Stored.Sha256);

    DocumentsJson := TJSONObject.ParseJSONValue(GetJson(Client,
      ApiUrl + '/v1/documentos?nsu=0&limite=100', TenantToken)) as TJSONObject;
    try
      Require(DocumentsJson <> nil, 'Lista de documentos retornou JSON invalido.');
      Items := DocumentsJson.GetValue('itens') as TJSONArray;
      Require((Items <> nil) and (Items.Count = 1),
        'ERP nao recebeu exatamente o documento do proprio tenant.');
      Require(JsonString(Items.Items[0] as TJSONObject, 'id_documento') = DocumentId,
        'ERP recebeu documento diferente do inserido.');
      Require(SameText(JsonString(Items.Items[0] as TJSONObject, 'xml_disponivel'), 'true'),
        'Documento pronto nao foi marcado com XML disponivel.');
      Require(StrToInt64(JsonString(DocumentsJson, 'ultimo_nsu')) > 0,
        'Lista inicial nao retornou NSU para retomada.');
      Response := Client.Get(ApiUrl + '/v1/documentos/' + DocumentId + '/xml', nil,
        Headers(TenantToken, ''));
      RequireSuccess(Response, 'GET XML pelo ERP');
      Require(Response.ContentAsString(TEncoding.UTF8) = Xml,
        'XML baixado pela API difere do XML armazenado.');
      LastNsu := JsonString(DocumentsJson, 'ultimo_nsu');
      DocumentsJson.Free;
      DocumentsJson := TJSONObject.ParseJSONValue(GetJson(Client,
        ApiUrl + '/v1/documentos?nsu=' + LastNsu + '&limite=100',
        TenantToken)) as TJSONObject;
      Items := DocumentsJson.GetValue('itens') as TJSONArray;
      Require((Items <> nil) and (Items.Count = 0),
        'ERP recebeu novamente documento ja confirmado pelo NSU.');
    finally
      DocumentsJson.Free;
    end;

    ModuleBody := TStringStream.Create('{"situacao":"suspenso"}', TEncoding.UTF8, False);
    try
      RequireSuccess(Client.Put(ApiUrl + '/v1/empresas/' + CompanyId + '/modulos/monitoramento',
        ModuleBody, nil, Headers(BootstrapToken, '')), 'PUT suspender modulo');
    finally
      ModuleBody.Free;
    end;
    VerifyModuleSuspended(Connection, CompanyId);
    Writeln('E2E ERP aprovado: onboarding A1/KMS, token tenant, monitoramento, NSU, XML S3 e suspensao.');
  finally
    if (Storage <> nil) and (ObjectKey <> '') then
      Storage.Delete(ObjectKey);
    Storage.Free;
    DeleteFixtures(Connection, CompanyId, OrganizationId);
    Connection.Free;
    Client.Free;
    if Length(CertificateBytes) > 0 then
      FillChar(CertificateBytes[0], Length(CertificateBytes), 0);
    if Length(PasswordBytes) > 0 then
      FillChar(PasswordBytes[0], Length(PasswordBytes), 0);
  end;
end.
