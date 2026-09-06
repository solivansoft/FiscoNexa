unit Tests.CompanyOnboarding;

interface

uses
  TestFramework;

type
  TCompanyOnboardingTests = class(TTestCase)
  public
    procedure TestValidateAcceptsCompleteRequest;
    procedure TestValidateRejectsMissingIdempotencyKey;
    procedure TestExecuteReturnsTokenOnlyForNewOnboarding;
    procedure TestWriterRejectsMissingConnection;
    procedure TestReceitaWsRejectsForeignCnpjAndInvalidState;
  end;

implementation

uses
  Application.CompanyRegistry,
  Integrations.ReceitaWs,
  Application.CompanyOnboarding,
  Application.CertificateEnvelope,
  Application.CertificateIdentity,
  Application.CertificateRegistration,
  Application.ErpKeys,
  Persistence.CompanyOnboarding,
  System.SysUtils;

type
  TFakeRegistry = class(TInterfacedObject, ICompanyRegistry)
  public
    Data: TCompanyRegistryData;
    function Lookup(const ACnpj: string): TCompanyRegistryData;
  end;
  TFakeCertificateInspector = class(TInterfacedObject, ICertificateInspector)
  public
    function Inspect(const APfx, APassword: TBytes): TCertificateIdentity;
  end;

  TFakeKeyService = class(TInterfacedObject, IEnvelopeKeyService)
  public
    function GenerateDataKey: TEnvelopeDataKey;
    function DecryptDataKey(const AEncryptedKey: TBytes): TBytes;
  end;

  TFakeCipher = class(TInterfacedObject, IEnvelopeCipher)
  public
    function Encrypt(const AKey, APlaintext: TBytes): TEncryptedValue;
  end;

  TFixedTokenGenerator = class(TInterfacedObject, IIntegrationTokenGenerator)
  public
    function Generate: string;
  end;

  TFakeOnboardingWriter = class(TInterfacedObject, ICompanyOnboardingWriter)
  private
    FReplay: Boolean;
    FLastData: TCompanyOnboardingData;
  public
    constructor Create(const AReplay: Boolean);
    function Save(const AData: TCompanyOnboardingData): TCompanyOnboardingResult;
    property LastData: TCompanyOnboardingData read FLastData;
  end;

function TFakeRegistry.Lookup(const ACnpj: string): TCompanyRegistryData;
begin
  Result := Data;
end;

procedure TCompanyOnboardingTests.TestReceitaWsRejectsForeignCnpjAndInvalidState;
var Data: TCompanyRegistryData;
begin
  Data := ParseReceitaWs('12345678000190', '{"status":"OK","cnpj":"12.345.678/0001-90","uf":"PA","nome":"Empresa","logradouro":"Rua A"}');
  AssertTrue(Data.Available);
  AssertEquals('PA', Data.State);
  AssertTrue(Pos('logradouro', Data.Json) > 0);
  AssertFalse(ParseReceitaWs('99999999000199', Data.Json).Available);
  AssertFalse(ParseReceitaWs('12345678000190', '{"status":"ERROR"}').Available);
  AssertFalse(ParseReceitaWs('12345678000190', '[]').Available);
  AssertFalse(ParseReceitaWs('12345678000190', '{"status":"OK","cnpj":"12345678000190","uf":"ZZ","nome":"Empresa"}').Available);
end;

function TFakeCertificateInspector.Inspect(const APfx,
  APassword: TBytes): TCertificateIdentity;
begin
  Result.Cnpj := '12345678000190';
  Result.Subject := 'Empresa Teste';
  Result.ValidUntil := EncodeDate(2030, 1, 1);
end;

function TFakeKeyService.GenerateDataKey: TEnvelopeDataKey;
begin
  Result.KeyReference := 'kms-key';
  Result.PlaintextKey := TBytes.Create(1, 2, 3, 4);
  Result.EncryptedKey := TBytes.Create(5, 6, 7, 8);
end;

function TFakeKeyService.DecryptDataKey(const AEncryptedKey: TBytes): TBytes;
begin
  Result := TBytes.Create(1, 2, 3, 4);
end;

function TFakeCipher.Encrypt(const AKey, APlaintext: TBytes): TEncryptedValue;
begin
  Result.Ciphertext := TBytes.Create(Byte(Length(APlaintext)));
  Result.Nonce := TBytes.Create(1);
  Result.Tag := TBytes.Create(2);
end;

function TFixedTokenGenerator.Generate: string;
begin
  Result := 'tenant-secret-token';
end;

constructor TFakeOnboardingWriter.Create(const AReplay: Boolean);
begin
  inherited Create;
  FReplay := AReplay;
end;

function TFakeOnboardingWriter.Save(
  const AData: TCompanyOnboardingData): TCompanyOnboardingResult;
begin
  FLastData := AData;
  Result.CompanyId := 'company-id';
  Result.IntegrationId := 'integration-id';
  Result.IntegrationTokenCreated := not FReplay;
  Result.Replayed := FReplay;
end;

procedure TCompanyOnboardingTests.TestValidateAcceptsCompleteRequest;
var
  Request: TCompanyOnboardingRequest;
begin
  Request.IdempotencyKey := 'erp-request-123';
  Request.State := 'PA';
  Request.CertificatePfx := TBytes.Create(1);
  Request.CertificatePassword := TBytes.Create(2);
  ValidateCompanyOnboardingRequest(Request);
  AssertTrue(True);
end;

procedure TCompanyOnboardingTests.TestValidateRejectsMissingIdempotencyKey;
var
  Request: TCompanyOnboardingRequest;
begin
  Request.CertificatePfx := TBytes.Create(1);
  Request.CertificatePassword := TBytes.Create(2);
  try
    ValidateCompanyOnboardingRequest(Request);
    Fail('Requisicao sem idempotencia foi aceita.');
  except
    on E: ECompanyOnboardingValidation do
      AssertTrue(True);
  end;
end;

procedure TCompanyOnboardingTests.TestExecuteReturnsTokenOnlyForNewOnboarding;
var
  KeyService: IEnvelopeKeyService;
  Cipher: IEnvelopeCipher;
  Inspector: ICertificateInspector;
  TokenGenerator: IIntegrationTokenGenerator;
  WriterObject: TFakeOnboardingWriter;
  Writer: ICompanyOnboardingWriter;
  Envelope: TCertificateEnvelopeService;
  CertificateService: TCertificateRegistrationService;
  Service: TCompanyOnboardingService;
  Request: TCompanyOnboardingRequest;
  Principal: TErpKeyPrincipal;
  ResultData: TCompanyOnboardingResult;
  RegistryObject: TFakeRegistry;
  Registry: ICompanyRegistry;
begin
  KeyService := TFakeKeyService.Create;
  Cipher := TFakeCipher.Create;
  Inspector := TFakeCertificateInspector.Create;
  TokenGenerator := TFixedTokenGenerator.Create;
  WriterObject := TFakeOnboardingWriter.Create(False);
  Writer := WriterObject;
  Envelope := TCertificateEnvelopeService.Create(KeyService, Cipher);
  CertificateService := TCertificateRegistrationService.Create(Inspector, Envelope);
  RegistryObject := TFakeRegistry.Create;
  Registry := RegistryObject;
  Service := TCompanyOnboardingService.Create(CertificateService, TokenGenerator, Writer, Registry);
  try
    Principal.OrganizationId := 'erp-organization';
    Request.IdempotencyKey := 'request-1';
    Request.State := 'PA';
    Request.CertificatePfx := TBytes.Create(1);
    Request.CertificatePassword := TBytes.Create(2);
    ResultData := Service.Execute(Principal, Request);
    AssertEquals('company-id', ResultData.CompanyId);
    AssertEquals('tenant-secret-token', ResultData.IntegrationToken);
    AssertEquals(HashIntegrationToken('tenant-secret-token'),
      WriterObject.LastData.IntegrationTokenHash);
    AssertEquals('12345678000190', WriterObject.LastData.Certificate.Identity.Cnpj);
    AssertEquals('PA', WriterObject.LastData.State);
    Request.State := '';
    try
      Service.Execute(Principal, Request);
      Fail('UF ausente e Receita indisponivel deveriam ser recusadas.');
    except on E: ECompanyStateRequired do AssertTrue(True); end;
    RegistryObject.Data := ParseReceitaWs('12345678000190',
      '{"status":"OK","cnpj":"12345678000190","uf":"CE","nome":"Empresa"}');
    Service.Execute(Principal, Request);
    AssertEquals('CE', WriterObject.LastData.State);
    AssertEquals('Empresa', WriterObject.LastData.Registry.LegalName);
    Request.State := 'PA';
    Service.Execute(Principal, Request);
    AssertEquals('PA', WriterObject.LastData.State);
  finally
    Service.Free;
    CertificateService.Free;
    Envelope.Free;
  end;
end;

procedure TCompanyOnboardingTests.TestWriterRejectsMissingConnection;
var
  Writer: TPostgresCompanyOnboardingWriter;
begin
  try
    Writer := TPostgresCompanyOnboardingWriter.Create(nil);
    try
      Fail('Writer aceitou conexao ausente.');
    finally
      Writer.Free;
    end;
  except
    on E: EArgumentNilException do
      AssertTrue(True);
  end;
end;

initialization

TTestHelper.RegisterTest(TCompanyOnboardingTests.Create);

end.
