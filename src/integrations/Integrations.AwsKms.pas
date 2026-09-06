unit Integrations.AwsKms;

interface

uses
  Application.CertificateEnvelope,
  System.SysUtils;

type
  IAwsKmsTransport = interface
    ['{EFC69C17-077C-47F6-81BE-4D1F61E4980D}']
    function PostJson(const AUrl: string; const AHeaders: TArray<string>;
      const ABody: string): string;
  end;

  TAwsKmsDataKeyService = class(TInterfacedObject, IEnvelopeKeyService)
  private
    FTransport: IAwsKmsTransport;
    FRegion: string;
    FKeyReference: string;
    function Endpoint: string;
    function RequestHeaders(const ATarget: string): TArray<string>;
    function ReadDataKey(const AResponse: string): TEnvelopeDataKey;
  public
    constructor Create(const ATransport: IAwsKmsTransport; const ARegion,
      AKeyReference: string);
    function GenerateDataKey: TEnvelopeDataKey;
    function DecryptDataKey(const AEncryptedKey: TBytes): TBytes;
  end;

implementation

uses
  System.JSON,
  System.NetEncoding;

constructor TAwsKmsDataKeyService.Create(const ATransport: IAwsKmsTransport;
  const ARegion, AKeyReference: string);
begin
  inherited Create;
  if ATransport = nil then
    raise EArgumentNilException.Create('Transporte AWS nao informado.');
  if ARegion = '' then
    raise EArgumentException.Create('Regiao AWS nao informada.');
  if AKeyReference = '' then
    raise EArgumentException.Create('Chave KMS nao informada.');
  FTransport := ATransport;
  FRegion := ARegion;
  FKeyReference := AKeyReference;
end;

function TAwsKmsDataKeyService.Endpoint: string;
begin
  Result := 'https://kms.' + FRegion + '.amazonaws.com/';
end;

function TAwsKmsDataKeyService.RequestHeaders(const ATarget: string): TArray<string>;
begin
  Result := TArray<string>.Create(
    'Content-Type: application/x-amz-json-1.1',
    'X-Amz-Target: ' + ATarget
  );
end;

function TAwsKmsDataKeyService.ReadDataKey(const AResponse: string): TEnvelopeDataKey;
var
  Json: TJSONObject;
  Plaintext: TJSONValue;
  Ciphertext: TJSONValue;
  KeyId: TJSONValue;
begin
  Json := TJSONObject.ParseJSONValue(AResponse) as TJSONObject;
  try
    if Json = nil then
      raise EInvalidOpException.Create('KMS retornou JSON invalido.');
    Plaintext := Json.GetValue('Plaintext');
    Ciphertext := Json.GetValue('CiphertextBlob');
    KeyId := Json.GetValue('KeyId');
    if (Plaintext = nil) or (Ciphertext = nil) or (KeyId = nil) then
      raise EInvalidOpException.Create('KMS nao retornou a data key completa.');
    Result.KeyReference := KeyId.Value;
    Result.PlaintextKey := TNetEncoding.Base64.DecodeStringToBytes(Plaintext.Value);
    Result.EncryptedKey := TNetEncoding.Base64.DecodeStringToBytes(Ciphertext.Value);
  finally
    Json.Free;
  end;
end;

function TAwsKmsDataKeyService.GenerateDataKey: TEnvelopeDataKey;
var
  Body: string;
  Response: string;
begin
  Body := '{"KeyId":"' + FKeyReference + '","KeySpec":"AES_256"}';
  Response := FTransport.PostJson(Endpoint,
    RequestHeaders('TrentService.GenerateDataKey'), Body);
  Result := ReadDataKey(Response);
end;

function TAwsKmsDataKeyService.DecryptDataKey(const AEncryptedKey: TBytes): TBytes;
var
  Body: string;
  Response: string;
  Json: TJSONObject;
  Plaintext: TJSONValue;
begin
  if Length(AEncryptedKey) = 0 then
    raise EArgumentException.Create('Data key cifrada nao informada.');
  Body := '{"CiphertextBlob":"' + StringReplace(StringReplace(
    TNetEncoding.Base64.EncodeBytesToString(AEncryptedKey), #13, '',
    [rfReplaceAll]), #10, '', [rfReplaceAll]) + '"}';
  Response := FTransport.PostJson(Endpoint,
    RequestHeaders('TrentService.Decrypt'), Body);
  Json := TJSONObject.ParseJSONValue(Response) as TJSONObject;
  try
    if Json = nil then
      raise EInvalidOpException.Create('KMS retornou JSON invalido.');
    Plaintext := Json.GetValue('Plaintext');
    if Plaintext = nil then
      raise EInvalidOpException.Create('KMS nao retornou a data key decifrada.');
    Result := TNetEncoding.Base64.DecodeStringToBytes(Plaintext.Value);
  finally
    Json.Free;
  end;
end;

end.
