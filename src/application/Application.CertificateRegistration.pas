unit Application.CertificateRegistration;

interface

uses
  Application.CertificateEnvelope,
  Application.CertificateIdentity,
  System.SysUtils;

type
  TPreparedCertificate = record
    Identity: TCertificateIdentity;
    Envelope: TStoredCertificateEnvelope;
  end;

  TCertificateRegistrationService = class
  private
    FInspector: ICertificateInspector;
    FEnvelopeService: TCertificateEnvelopeService;
  public
    constructor Create(const AInspector: ICertificateInspector;
      const AEnvelopeService: TCertificateEnvelopeService);
    function Prepare(const APfx, APassword: TBytes): TPreparedCertificate;
  end;

implementation

constructor TCertificateRegistrationService.Create(const AInspector: ICertificateInspector;
  const AEnvelopeService: TCertificateEnvelopeService);
begin
  inherited Create;
  if AInspector = nil then
    raise EArgumentNilException.Create('Inspetor de certificado nao informado.');
  if AEnvelopeService = nil then
    raise EArgumentNilException.Create('Servico de envelope nao informado.');
  FInspector := AInspector;
  FEnvelopeService := AEnvelopeService;
end;

function TCertificateRegistrationService.Prepare(const APfx,
  APassword: TBytes): TPreparedCertificate;
begin
  Result.Identity := FInspector.Inspect(APfx, APassword);
  Result.Envelope := FEnvelopeService.Protect(APfx, APassword);
end;

end.
