unit Tests.AwsKms;

interface

uses
  TestFramework;

type
  TAwsKmsTests = class(TTestCase)
  public
    procedure TestGenerateDataKeyBuildsKmsRequestAndReadsResponse;
    procedure TestGenerateDataKeyRejectsIncompleteResponse;
    procedure TestDecryptDataKeyReadsPlaintext;
  end;

implementation

uses
  System.SysUtils,
  Application.CertificateEnvelope,
  Integrations.AwsKms,
  Integrations.AwsKmsTransport;

type
  TFakeKmsTransport = class(TInterfacedObject, IAwsKmsTransport)
  private
    FResponse: string;
    FUrl: string;
    FBody: string;
  public
    constructor Create(const AResponse: string);
    function PostJson(const AUrl: string; const AHeaders: TArray<string>;
      const ABody: string): string;
    property Url: string read FUrl;
    property Body: string read FBody;
  end;

constructor TFakeKmsTransport.Create(const AResponse: string);
begin
  inherited Create;
  FResponse := AResponse;
end;

function TFakeKmsTransport.PostJson(const AUrl: string;
  const AHeaders: TArray<string>; const ABody: string): string;
begin
  FUrl := AUrl;
  FBody := ABody;
  Result := FResponse;
end;

procedure TAwsKmsTests.TestGenerateDataKeyBuildsKmsRequestAndReadsResponse;
var
  TransportObject: TFakeKmsTransport;
  Transport: IAwsKmsTransport;
  Service: TAwsKmsDataKeyService;
  DataKey: TEnvelopeDataKey;
begin
  TransportObject := TFakeKmsTransport.Create(
    '{"KeyId":"arn:aws:kms:sa-east-1:account:key/test","Plaintext":"AQIDBA==","CiphertextBlob":"BQYHCA=="}');
  Transport := TransportObject;
  Service := TAwsKmsDataKeyService.Create(Transport, 'sa-east-1',
    'arn:aws:kms:sa-east-1:account:key/test');
  try
    DataKey := Service.GenerateDataKey;
    AssertEquals('https://kms.sa-east-1.amazonaws.com/', TransportObject.Url);
    AssertTrue(Pos('"KeySpec":"AES_256"', TransportObject.Body) > 0);
    AssertEquals(4, Length(DataKey.PlaintextKey));
    AssertEquals(4, Length(DataKey.EncryptedKey));
  finally
    Service.Free;
  end;
end;

procedure TAwsKmsTests.TestGenerateDataKeyRejectsIncompleteResponse;
var
  Transport: IAwsKmsTransport;
  Service: TAwsKmsDataKeyService;
begin
  Transport := TFakeKmsTransport.Create('{"KeyId":"key"}');
  Service := TAwsKmsDataKeyService.Create(Transport, 'sa-east-1', 'key');
  try
    try
      Service.GenerateDataKey;
      Fail('Resposta KMS incompleta foi aceita.');
    except
      on E: EInvalidOpException do
        AssertTrue(True);
    end;
  finally
    Service.Free;
  end;
end;

procedure TAwsKmsTests.TestDecryptDataKeyReadsPlaintext;
var
  Transport: IAwsKmsTransport;
  Service: TAwsKmsDataKeyService;
  Plaintext: TBytes;
begin
  Transport := TFakeKmsTransport.Create('{"Plaintext":"AQIDBA=="}');
  Service := TAwsKmsDataKeyService.Create(Transport, 'sa-east-1', 'key');
  try
    Plaintext := Service.DecryptDataKey(TBytes.Create(5, 6, 7));
    AssertEquals(4, Length(Plaintext));
    AssertEquals(1, Plaintext[0]);
  finally
    Service.Free;
  end;
end;

initialization

TTestHelper.RegisterTest(TAwsKmsTests.Create);

end.
