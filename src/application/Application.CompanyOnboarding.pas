unit Application.CompanyOnboarding;

interface

uses
  Application.CompanyRegistry,
  Application.CertificateRegistration,
  Application.ErpKeys,
  System.Classes,
  System.Hash,
  System.SysUtils;

type
  ECompanyOnboardingValidation = class(Exception);
  ECompanyStateRequired = class(ECompanyOnboardingValidation);

  TCompanyOnboardingRequest = record
    IdempotencyKey: string;
    State: string;
    CertificatePfx: TBytes;
    CertificatePassword: TBytes;
  end;

  TCompanyOnboardingResult = record
    State, LegalName, TradeName, RegistryJson: string;
    CompanyId: string;
    IntegrationId: string;
    IntegrationToken: string;
    IntegrationTokenCreated: Boolean;
    Replayed: Boolean;
  end;

  TCompanyOnboardingData = record
    Registry: TCompanyRegistryData;
    ErpKey: TErpKeyPrincipal;
    IdempotencyKey: string;
    State: string;
    CertificateSha256: string;
    Certificate: TPreparedCertificate;
    IntegrationTokenHash: string;
  end;

  IIntegrationTokenGenerator = interface
    ['{2D444696-670A-4C1F-A41B-BEA70811FD55}']
    function Generate: string;
  end;

  ICompanyOnboardingWriter = interface
    ['{46E51C99-820A-4249-9F10-25FD3D5EDC25}']
    function Save(const AData: TCompanyOnboardingData): TCompanyOnboardingResult;
  end;

  TCompanyOnboardingService = class
  private
    FRegistry: ICompanyRegistry;
    FCertificateService: TCertificateRegistrationService;
    FTokenGenerator: IIntegrationTokenGenerator;
    FWriter: ICompanyOnboardingWriter;
    function CreateData(const AErpKey: TErpKeyPrincipal;
      const ARequest: TCompanyOnboardingRequest): TCompanyOnboardingData;
  public
    constructor Create(const ACertificateService: TCertificateRegistrationService;
      const ATokenGenerator: IIntegrationTokenGenerator;
      const AWriter: ICompanyOnboardingWriter; const ARegistry: ICompanyRegistry);
    function Execute(const AErpKey: TErpKeyPrincipal;
      const ARequest: TCompanyOnboardingRequest): TCompanyOnboardingResult;
  end;

procedure ValidateCompanyOnboardingRequest(const ARequest: TCompanyOnboardingRequest);
function HashIntegrationToken(const AToken: string): string;

implementation

uses Application.BrazilianStates;

procedure ValidateCompanyOnboardingRequest(const ARequest: TCompanyOnboardingRequest);
begin
  if Trim(ARequest.IdempotencyKey) = '' then
    raise ECompanyOnboardingValidation.Create('Idempotency-Key obrigatoria.');
  if Trim(ARequest.State) <> '' then
    try BrazilianStateCode(ARequest.State);
    except on E: EArgumentException do
      raise ECompanyOnboardingValidation.Create('UF da empresa invalida.'); end;
  if Length(ARequest.CertificatePfx) = 0 then
    raise ECompanyOnboardingValidation.Create('Certificado A1 obrigatorio.');
  if Length(ARequest.CertificatePassword) = 0 then
    raise ECompanyOnboardingValidation.Create('Senha do certificado obrigatoria.');
end;

function HashIntegrationToken(const AToken: string): string;
begin
  Result := THashSHA2.GetHashString(AToken).ToLowerInvariant;
end;

function HashCertificate(const ACertificate: TBytes): string;
var
  Stream: TBytesStream;
begin
  Stream := TBytesStream.Create(ACertificate);
  try
    Result := THashSHA2.GetHashString(Stream).ToLowerInvariant;
  finally
    Stream.Free;
  end;
end;

constructor TCompanyOnboardingService.Create(
  const ACertificateService: TCertificateRegistrationService;
  const ATokenGenerator: IIntegrationTokenGenerator;
  const AWriter: ICompanyOnboardingWriter; const ARegistry: ICompanyRegistry);
begin
  inherited Create;
  if ARegistry = nil then
    raise EArgumentNilException.Create('Consulta cadastral nao informada.');
  FRegistry := ARegistry;
  if ACertificateService = nil then
    raise EArgumentNilException.Create('Servico de certificado nao informado.');
  if ATokenGenerator = nil then
    raise EArgumentNilException.Create('Gerador de token nao informado.');
  if AWriter = nil then
    raise EArgumentNilException.Create('Persistencia de onboarding nao informada.');
  FCertificateService := ACertificateService;
  FTokenGenerator := ATokenGenerator;
  FWriter := AWriter;
end;

function TCompanyOnboardingService.CreateData(const AErpKey: TErpKeyPrincipal;
  const ARequest: TCompanyOnboardingRequest): TCompanyOnboardingData;
begin
  ValidateCompanyOnboardingRequest(ARequest);
  if Trim(AErpKey.OrganizationId) = '' then
    raise ECompanyOnboardingValidation.Create('Organizacao do ERP obrigatoria.');

  Result.ErpKey := AErpKey;
  Result.IdempotencyKey := ARequest.IdempotencyKey;
  Result.State := UpperCase(Trim(ARequest.State));
  Result.CertificateSha256 := HashCertificate(ARequest.CertificatePfx);
  Result.Certificate := FCertificateService.Prepare(ARequest.CertificatePfx,
    ARequest.CertificatePassword);
  Result.Registry := FRegistry.Lookup(Result.Certificate.Identity.Cnpj);
  if Result.Registry.Available and
    (Result.Registry.Cnpj <> Result.Certificate.Identity.Cnpj) then
    Result.Registry := Default(TCompanyRegistryData);
  if (Result.State = '') and Result.Registry.Available then
    Result.State := Result.Registry.State;
  if Result.State = '' then
    raise ECompanyStateRequired.Create('Informe state: UF indisponivel na consulta cadastral.');
end;

function TCompanyOnboardingService.Execute(const AErpKey: TErpKeyPrincipal;
  const ARequest: TCompanyOnboardingRequest): TCompanyOnboardingResult;
var
  Data: TCompanyOnboardingData;
  Token: string;
begin
  Data := CreateData(AErpKey, ARequest);
  Token := FTokenGenerator.Generate;
  if Trim(Token) = '' then
    raise ECompanyOnboardingValidation.Create('Gerador de token retornou valor vazio.');
  Data.IntegrationTokenHash := HashIntegrationToken(Token);
  Result := FWriter.Save(Data);
  if Result.IntegrationTokenCreated then
    Result.IntegrationToken := Token;
end;

end.
