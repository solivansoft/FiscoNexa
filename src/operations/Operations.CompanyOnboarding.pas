unit Operations.CompanyOnboarding;

interface

uses
  Application.CompanyOnboarding;

function ExecuteErpCompanyOnboarding(const AAuthorization: string;
  const ARequest: TCompanyOnboardingRequest): TCompanyOnboardingResult;

implementation

uses
  System.SysUtils,
  Integrations.ReceitaWs,
  Application.CertificateEnvelope,
  Application.CertificateIdentity,
  Application.CertificateRegistration,
  Application.ErpKeys,
  Database.Connection,
  Integrations.AwsKms,
  Integrations.AwsKmsTransport,
  Integrations.OpenSslCertificate,
  Integrations.OpenSslCipher,
  Integrations.OpenSslToken,
  Persistence.CompanyOnboarding,
  Persistence.ErpKeys,
  FireDAC.Stan.Param, FireDAC.Comp.Client;

function ExecuteErpCompanyOnboarding(const AAuthorization: string;
  const ARequest: TCompanyOnboardingRequest): TCompanyOnboardingResult;
var
  Connection: TFDConnection;
  KeyReader: IErpKeyReader;
  Principal: TErpKeyPrincipal;
  Transport: IAwsKmsTransport;
  KeyService: IEnvelopeKeyService;
  Cipher: IEnvelopeCipher;
  Inspector: ICertificateInspector;
  TokenGenerator: IIntegrationTokenGenerator;
  Writer: ICompanyOnboardingWriter;
  EnvelopeService: TCertificateEnvelopeService;
  CertificateService: TCertificateRegistrationService;
  OnboardingService: TCompanyOnboardingService;
begin
  Connection := TDatabaseConnection.OpenFromEnvironment;
  try
    KeyReader := TPostgresErpKeyReader.Create(Connection);
    Principal := AuthenticateErpKey(AAuthorization, KeyReader);
    RequireErpScope(Principal, 'companies:onboard');
    ValidateCompanyOnboardingRequest(ARequest);
    Transport := TAwsKmsSignedTransport.CreateFromEnvironment;
    KeyService := TAwsKmsDataKeyService.Create(Transport,
      GetEnvironmentVariable('AWS_REGION'),
      GetEnvironmentVariable('FISCONEXA_KMS_KEY_ID'));
    Cipher := TOpenSslGcmCipher.Create;
    Inspector := TOpenSslCertificateInspector.Create;
    TokenGenerator := TOpenSslTokenGenerator.Create;
    Writer := TPostgresCompanyOnboardingWriter.Create(Connection);
    EnvelopeService := TCertificateEnvelopeService.Create(KeyService, Cipher);
    CertificateService := TCertificateRegistrationService.Create(Inspector,
      EnvelopeService);
    OnboardingService := TCompanyOnboardingService.Create(CertificateService,
      TokenGenerator, Writer, TReceitaWsRegistry.Create);
    try
      Result := OnboardingService.Execute(Principal, ARequest);
    finally
      OnboardingService.Free;
      CertificateService.Free;
      EnvelopeService.Free;
    end;
  finally
    Connection.Free;
  end;
end;

end.
