unit Application.CertificateEnvelope;

interface

uses
  System.SysUtils;

type
  TEnvelopeDataKey = record
    KeyReference: string;
    PlaintextKey: TBytes;
    EncryptedKey: TBytes;
  end;

  TEncryptedValue = record
    Ciphertext: TBytes;
    Nonce: TBytes;
    Tag: TBytes;
  end;

  TStoredCertificateEnvelope = record
    EncryptionKeyReference: string;
    EncryptedDataKey: TBytes;
    EncryptedCertificate: TEncryptedValue;
    EncryptedPassword: TEncryptedValue;
  end;

  IEnvelopeKeyService = interface
    ['{2C4A2F17-D5AB-4C00-9DB8-7E5F3A78C3BD}']
    function GenerateDataKey: TEnvelopeDataKey;
    function DecryptDataKey(const AEncryptedKey: TBytes): TBytes;
  end;

  IEnvelopeCipher = interface
    ['{5FE700D9-B7D2-483D-B04C-DB30F8EA548D}']
    function Encrypt(const AKey, APlaintext: TBytes): TEncryptedValue;
  end;

  IEnvelopeDecipher = interface
    ['{0834BA6D-7B5B-4AFE-9537-3537DCB4E20C}']
    function Decrypt(const AKey: TBytes; const AValue: TEncryptedValue): TBytes;
  end;

  TCertificateEnvelopeService = class
  private
    FKeyService: IEnvelopeKeyService;
    FCipher: IEnvelopeCipher;
    procedure ClearBytes(var AValue: TBytes);
  public
    constructor Create(const AKeyService: IEnvelopeKeyService;
      const ACipher: IEnvelopeCipher);
    function Protect(const ACertificate, APassword: TBytes): TStoredCertificateEnvelope;
  end;

implementation

constructor TCertificateEnvelopeService.Create(const AKeyService: IEnvelopeKeyService;
  const ACipher: IEnvelopeCipher);
begin
  inherited Create;
  if AKeyService = nil then
    raise EArgumentNilException.Create('Servico de chave nao informado.');
  if ACipher = nil then
    raise EArgumentNilException.Create('Cifra local nao informada.');
  FKeyService := AKeyService;
  FCipher := ACipher;
end;

procedure TCertificateEnvelopeService.ClearBytes(var AValue: TBytes);
begin
  if Length(AValue) > 0 then
    FillChar(AValue[0], Length(AValue), 0);
  AValue := nil;
end;

function TCertificateEnvelopeService.Protect(const ACertificate,
  APassword: TBytes): TStoredCertificateEnvelope;
var
  DataKey: TEnvelopeDataKey;
begin
  DataKey := FKeyService.GenerateDataKey;
  if (DataKey.KeyReference = '') or (Length(DataKey.PlaintextKey) = 0) or
    (Length(DataKey.EncryptedKey) = 0) then
    raise EInvalidOpException.Create('KMS retornou uma data key invalida.');

  try
    Result.EncryptionKeyReference := DataKey.KeyReference;
    Result.EncryptedDataKey := DataKey.EncryptedKey;
    Result.EncryptedCertificate := FCipher.Encrypt(DataKey.PlaintextKey, ACertificate);
    Result.EncryptedPassword := FCipher.Encrypt(DataKey.PlaintextKey, APassword);
  finally
    ClearBytes(DataKey.PlaintextKey);
  end;
end;

end.
