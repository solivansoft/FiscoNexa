unit Application.CertificateMaterial;

interface

uses
  Application.CertificateEnvelope,
  System.SysUtils;

type
  TStoredCertificateMaterial = record
    Cnpj: string;
    State: string;
    Envelope: TStoredCertificateEnvelope;
  end;

  TActiveCertificateMaterial = record
    Cnpj: string;
    State: string;
    Pfx: TBytes;
    Password: TBytes;
  end;

  IStoredCertificateReader = interface
    ['{6884A52D-5F53-4E92-AFEE-68E319493A9A}']
    function ReadActive(const ACompanyId: string): TStoredCertificateMaterial;
  end;

  IActiveCertificateProvider = interface
    ['{C7DDEE51-6BA1-4536-B9D5-CE2F5A560BE9}']
    function LoadActive(const ACompanyId: string): TActiveCertificateMaterial;
  end;

  TActiveCertificateService = class(TInterfacedObject, IActiveCertificateProvider)
  private
    FReader: IStoredCertificateReader;
    FKeyService: IEnvelopeKeyService;
    FDecipher: IEnvelopeDecipher;
    procedure ClearBytes(var AValue: TBytes);
  public
    constructor Create(const AReader: IStoredCertificateReader;
      const AKeyService: IEnvelopeKeyService; const ADecipher: IEnvelopeDecipher);
    function LoadActive(const ACompanyId: string): TActiveCertificateMaterial;
  end;

procedure ClearActiveCertificateMaterial(var AValue: TActiveCertificateMaterial);

implementation

procedure ClearActiveCertificateMaterial(var AValue: TActiveCertificateMaterial);
begin
  if Length(AValue.Pfx) > 0 then
    FillChar(AValue.Pfx[0], Length(AValue.Pfx), 0);
  if Length(AValue.Password) > 0 then
    FillChar(AValue.Password[0], Length(AValue.Password), 0);
  AValue := Default(TActiveCertificateMaterial);
end;

constructor TActiveCertificateService.Create(const AReader: IStoredCertificateReader;
  const AKeyService: IEnvelopeKeyService; const ADecipher: IEnvelopeDecipher);
begin
  inherited Create;
  if AReader = nil then
    raise EArgumentNilException.Create('Leitor de certificado nao informado.');
  if AKeyService = nil then
    raise EArgumentNilException.Create('Servico KMS nao informado.');
  if ADecipher = nil then
    raise EArgumentNilException.Create('Decifrador do certificado nao informado.');
  FReader := AReader;
  FKeyService := AKeyService;
  FDecipher := ADecipher;
end;

procedure TActiveCertificateService.ClearBytes(var AValue: TBytes);
begin
  if Length(AValue) > 0 then
    FillChar(AValue[0], Length(AValue), 0);
  AValue := nil;
end;

function TActiveCertificateService.LoadActive(
  const ACompanyId: string): TActiveCertificateMaterial;
var
  Stored: TStoredCertificateMaterial;
  DataKey: TBytes;
begin
  Result := Default(TActiveCertificateMaterial);
  Stored := FReader.ReadActive(ACompanyId);
  DataKey := FKeyService.DecryptDataKey(Stored.Envelope.EncryptedDataKey);
  try
    try
      Result.Cnpj := Stored.Cnpj;
      Result.State := Stored.State;
      Result.Pfx := FDecipher.Decrypt(DataKey, Stored.Envelope.EncryptedCertificate);
      Result.Password := FDecipher.Decrypt(DataKey, Stored.Envelope.EncryptedPassword);
    except
      ClearActiveCertificateMaterial(Result);
      raise;
    end;
  finally
    ClearBytes(DataKey);
  end;
end;

end.
