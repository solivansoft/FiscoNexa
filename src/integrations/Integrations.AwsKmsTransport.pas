unit Integrations.AwsKmsTransport;

interface

uses
  Integrations.AwsKms;

type
  TAwsKmsSignedTransport = class(TInterfacedObject, IAwsKmsTransport)
  private
    FAccessKey: string;
    FSecretKey: string;
    FRegion: string;
    function RequiredEnvironmentValue(const AName: string): string;
    function RequestTimestamp: string;
    function BuildHeaders(const AUrl: string; const ATarget, ABody: string): TArray<string>;
    function HeaderValue(const AHeaders: TArray<string>; const AName: string): string;
    function KmsErrorCode(const AResponse: string): string;
  public
    constructor CreateFromEnvironment;
    function PostJson(const AUrl: string; const AHeaders: TArray<string>;
      const ABody: string): string;
  end;

implementation

uses
  System.Classes,
  System.DateUtils,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.JSON,
  System.StrUtils,
  System.SysUtils,
  Integrations.AwsSignature;

function TAwsKmsSignedTransport.RequiredEnvironmentValue(const AName: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then
    raise EInvalidOpException.Create('Variavel AWS obrigatoria ausente: ' + AName);
end;

constructor TAwsKmsSignedTransport.CreateFromEnvironment;
begin
  inherited Create;
  FAccessKey := RequiredEnvironmentValue('AWS_ACCESS_KEY_ID');
  FSecretKey := RequiredEnvironmentValue('AWS_SECRET_ACCESS_KEY');
  FRegion := RequiredEnvironmentValue('AWS_REGION');
end;

function TAwsKmsSignedTransport.RequestTimestamp: string;
begin
  Result := FormatDateTime('yyyymmdd"T"hhnnss"Z"', TTimeZone.Local.ToUniversalTime(Now));
end;

function TAwsKmsSignedTransport.HeaderValue(const AHeaders: TArray<string>;
  const AName: string): string;
var
  Header: string;
  Prefix: string;
begin
  Prefix := LowerCase(AName) + ':';
  for Header in AHeaders do
    if StartsText(Prefix, LowerCase(Header)) then
      Exit(Trim(Copy(Header, Length(Prefix) + 1, MaxInt)));
  raise EArgumentException.Create('Header AWS obrigatorio ausente: ' + AName);
end;

function TAwsKmsSignedTransport.KmsErrorCode(const AResponse: string): string;
var
  Json: TJSONObject;
  ErrorType: TJSONValue;
  ErrorMessage: TJSONValue;
begin
  Result := 'unknown';
  Json := TJSONObject.ParseJSONValue(AResponse) as TJSONObject;
  try
    if Json = nil then
      Exit;
    ErrorType := Json.GetValue('__type');
    if ErrorType <> nil then
      Result := ErrorType.Value;
    ErrorMessage := Json.GetValue('message');
    if ErrorMessage <> nil then
      Result := Result + ': ' + ErrorMessage.Value;
  finally
    Json.Free;
  end;
end;

function TAwsKmsSignedTransport.BuildHeaders(const AUrl: string;
  const ATarget, ABody: string): TArray<string>;
var
  Host: string;
  Timestamp: string;
  DateStamp: string;
  PayloadHash: string;
  CanonicalHeaders: string;
  CanonicalRequest: string;
  Scope: string;
  StringToSign: string;
  Signature: string;
begin
  Host := 'kms.' + FRegion + '.amazonaws.com';
  Timestamp := RequestTimestamp;
  DateStamp := Copy(Timestamp, 1, 8);
  PayloadHash := TAwsSignatureV4.Sha256Hex(ABody);
  CanonicalHeaders :=
    'content-type:application/x-amz-json-1.1' + #10 +
    'host:' + Host + #10 +
    'x-amz-date:' + Timestamp + #10 +
    'x-amz-target:' + ATarget + #10;
  CanonicalRequest := 'POST' + #10 + '/' + #10 + #10 + CanonicalHeaders + #10 +
    'content-type;host;x-amz-date;x-amz-target' + #10 + PayloadHash;
  Scope := DateStamp + '/' + FRegion + '/kms/aws4_request';
  StringToSign := 'AWS4-HMAC-SHA256' + #10 + Timestamp + #10 + Scope + #10 +
    TAwsSignatureV4.Sha256Hex(CanonicalRequest);
  Signature := TAwsSignatureV4.Sign(FSecretKey, DateStamp, FRegion, 'kms', StringToSign);
  Result := TArray<string>.Create(
    'Content-Type: application/x-amz-json-1.1',
    'Host: ' + Host,
    'X-Amz-Date: ' + Timestamp,
    'X-Amz-Target: ' + ATarget,
    'Authorization: AWS4-HMAC-SHA256 Credential=' + FAccessKey + '/' + Scope +
      ', SignedHeaders=content-type;host;x-amz-date;x-amz-target, Signature=' + Signature
  );
end;

function TAwsKmsSignedTransport.PostJson(const AUrl: string;
  const AHeaders: TArray<string>; const ABody: string): string;
var
  Client: THTTPClient;
  RequestBody: TStringStream;
  ResponseBody: TStringStream;
  Response: IHTTPResponse;
  Headers: TNetHeaders;
  SignedHeaders: TArray<string>;
  Index: Integer;
begin
  SignedHeaders := BuildHeaders(AUrl, HeaderValue(AHeaders, 'X-Amz-Target'), ABody);
  SetLength(Headers, Length(SignedHeaders));
  for Index := 0 to High(SignedHeaders) do
  begin
    Headers[Index].Name := Copy(SignedHeaders[Index], 1,
      Pos(':', SignedHeaders[Index]) - 1);
    Headers[Index].Value := Trim(Copy(SignedHeaders[Index],
      Pos(':', SignedHeaders[Index]) + 1, MaxInt));
  end;
  Client := THTTPClient.Create;
  RequestBody := TStringStream.Create(ABody, TEncoding.UTF8, False);
  ResponseBody := TStringStream.Create('', TEncoding.UTF8, False);
  try
    Response := Client.Post(AUrl, RequestBody, ResponseBody, Headers);
    Result := ResponseBody.DataString;
    if (Response.StatusCode < 200) or (Response.StatusCode >= 300) then
      raise EInvalidOpException.Create('AWS KMS recusou a solicitacao. HTTP ' +
        Response.StatusCode.ToString + ' (' + KmsErrorCode(Result) + ')');
  finally
    ResponseBody.Free;
    RequestBody.Free;
    Client.Free;
  end;
end;

end.
