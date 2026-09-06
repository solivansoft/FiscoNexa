unit Tests.CertificateEnvelope;

interface

uses
  TestFramework;

type
  TCertificateEnvelopeTests = class(TTestCase)
  public
    procedure TestProtectStoresOnlyEncryptedMaterial;
    procedure TestProtectRejectsInvalidKmsResponse;
  end;

implementation

uses
  System.SysUtils,
  Application.CertificateEnvelope,
  Application.CertificateRegistration;

type
  TFakeKeyService = class(TInterfacedObject, IEnvelopeKeyService)
  private
    FDataKey: TEnvelopeDataKey;
  public
    constructor Create(const AIsValid: Boolean);
    function GenerateDataKey: TEnvelopeDataKey;
    function DecryptDataKey(const AEncryptedKey: TBytes): TBytes;
  end;

  TFakeCipher = class(TInterfacedObject, IEnvelopeCipher)
  private
    FCalls: Integer;
  public
    function Encrypt(const AKey, APlaintext: TBytes): TEncryptedValue;
    property Calls: Integer read FCalls;
  end;

constructor TFakeKeyService.Create(const AIsValid: Boolean);
begin
  inherited Create;
  if AIsValid then
  begin
    FDataKey.KeyReference := 'arn:aws:kms:sa-east-1:account:key/fisconexa-certificates';
    FDataKey.PlaintextKey := TBytes.Create(1, 2, 3, 4);
    FDataKey.EncryptedKey := TBytes.Create(9, 8, 7, 6);
  end;
end;

function TFakeKeyService.GenerateDataKey: TEnvelopeDataKey;
begin
  Result := FDataKey;
end;

function TFakeKeyService.DecryptDataKey(const AEncryptedKey: TBytes): TBytes;
begin
  Result := FDataKey.PlaintextKey;
end;

function TFakeCipher.Encrypt(const AKey, APlaintext: TBytes): TEncryptedValue;
begin
  Inc(FCalls);
  Result.Ciphertext := TBytes.Create($A5, Byte(Length(APlaintext)));
  Result.Nonce := TBytes.Create(1, 2, 3);
  Result.Tag := TBytes.Create(4, 5, 6);
end;

procedure TCertificateEnvelopeTests.TestProtectStoresOnlyEncryptedMaterial;
var
  KeyService: IEnvelopeKeyService;
  CipherObject: TFakeCipher;
  Cipher: IEnvelopeCipher;
  Service: TCertificateEnvelopeService;
  Envelope: TStoredCertificateEnvelope;
begin
  KeyService := TFakeKeyService.Create(True);
  CipherObject := TFakeCipher.Create;
  Cipher := CipherObject;
  Service := TCertificateEnvelopeService.Create(KeyService, Cipher);
  try
    Envelope := Service.Protect(TBytes.Create(10, 11, 12), TBytes.Create(13, 14));
    AssertEquals('arn:aws:kms:sa-east-1:account:key/fisconexa-certificates',
      Envelope.EncryptionKeyReference);
    AssertEquals(4, Length(Envelope.EncryptedDataKey));
    AssertEquals(2, CipherObject.Calls);
    AssertEquals($A5, Envelope.EncryptedCertificate.Ciphertext[0]);
    AssertEquals($A5, Envelope.EncryptedPassword.Ciphertext[0]);
  finally
    Service.Free;
  end;
end;

procedure TCertificateEnvelopeTests.TestProtectRejectsInvalidKmsResponse;
var
  KeyService: IEnvelopeKeyService;
  Cipher: IEnvelopeCipher;
  Service: TCertificateEnvelopeService;
begin
  KeyService := TFakeKeyService.Create(False);
  Cipher := TFakeCipher.Create;
  Service := TCertificateEnvelopeService.Create(KeyService, Cipher);
  try
    try
      Service.Protect(TBytes.Create(1), TBytes.Create(2));
      Fail('Resposta KMS invalida foi aceita.');
    except
      on E: EInvalidOpException do
        AssertTrue(True);
    end;
  finally
    Service.Free;
  end;
end;

initialization

TTestHelper.RegisterTest(TCertificateEnvelopeTests.Create);

end.
