unit Integrations.AwsS3Xml;

interface

uses Application.MonitorCycle;

type
  TAwsS3XmlStorage = class(TInterfacedObject, IXmlStorage)
  private
    FAccessKey: string;
    FSecretKey: string;
    FRegion: string;
    FBucket: string;
    function RequiredEnvironmentValue(const AName: string): string;
    function ObjectKey(const ACompanyCnpj, AAccessKey: string): string;
    function Timestamp: string;
    function Headers(const AMethod, AObjectKey, APayloadHash, ATimestamp: string): TArray<string>;
  public
    constructor CreateFromEnvironment;
    function Put(const ACompanyCnpj, AAccessKey, AXml: string): TStoredXml;
    function Get(const AObjectKey: string): string;
    procedure Delete(const AObjectKey: string);
  end;

implementation

uses
  System.Classes,
  System.DateUtils,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.SysUtils,
  Integrations.AwsSignature;

function TAwsS3XmlStorage.RequiredEnvironmentValue(const AName: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then
    raise EInvalidOpException.Create('Variavel AWS obrigatoria ausente: ' + AName);
end;

constructor TAwsS3XmlStorage.CreateFromEnvironment;
begin
  inherited Create;
  FAccessKey := RequiredEnvironmentValue('AWS_ACCESS_KEY_ID');
  FSecretKey := RequiredEnvironmentValue('AWS_SECRET_ACCESS_KEY');
  FRegion := RequiredEnvironmentValue('AWS_REGION');
  FBucket := RequiredEnvironmentValue('S3_XML_BUCKET');
end;

function TAwsS3XmlStorage.ObjectKey(const ACompanyCnpj, AAccessKey: string): string;
begin
  if (Trim(ACompanyCnpj) = '') or (Trim(AAccessKey) = '') then
    raise EArgumentException.Create('CNPJ e chave de acesso obrigatorios para o XML.');
  Result := 'nfe/' + Trim(ACompanyCnpj) + '/' + Trim(AAccessKey) + '.xml';
end;

function TAwsS3XmlStorage.Timestamp: string;
begin
  Result := FormatDateTime('yyyymmdd"T"hhnnss"Z"', TTimeZone.Local.ToUniversalTime(Now));
end;

function TAwsS3XmlStorage.Headers(const AMethod, AObjectKey, APayloadHash, ATimestamp: string): TArray<string>;
var
  Host, DateStamp, CanonicalHeaders, CanonicalRequest, Scope, StringToSign: string;
  Signature: string;
begin
  Host := 's3.' + FRegion + '.amazonaws.com';
  DateStamp := Copy(ATimestamp, 1, 8);
  CanonicalHeaders := 'content-type:application/xml' + #10 +
    'host:' + Host + #10 +
    'x-amz-content-sha256:' + APayloadHash + #10 +
    'x-amz-date:' + ATimestamp + #10;
  CanonicalRequest := AMethod + #10 + '/' + FBucket + '/' + AObjectKey + #10 + #10 +
    CanonicalHeaders + #10 +
    'content-type;host;x-amz-content-sha256;x-amz-date' + #10 + APayloadHash;
  Scope := DateStamp + '/' + FRegion + '/s3/aws4_request';
  StringToSign := 'AWS4-HMAC-SHA256' + #10 + ATimestamp + #10 + Scope + #10 +
    TAwsSignatureV4.Sha256Hex(CanonicalRequest);
  Signature := TAwsSignatureV4.Sign(FSecretKey, DateStamp, FRegion, 's3', StringToSign);
  Result := TArray<string>.Create(
    'Content-Type: application/xml', 'Host: ' + Host,
    'X-Amz-Content-Sha256: ' + APayloadHash, 'X-Amz-Date: ' + ATimestamp,
    'Authorization: AWS4-HMAC-SHA256 Credential=' + FAccessKey + '/' + Scope +
    ', SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date, Signature=' + Signature);
end;

function TAwsS3XmlStorage.Put(const ACompanyCnpj, AAccessKey, AXml: string): TStoredXml;
var
  Body: TStringStream;
  Client: THTTPClient;
  Response: IHTTPResponse;
  NetHeaders: TNetHeaders;
  Signed: TArray<string>;
  Index, Separator: Integer;
  Stamp: string;
begin
  Result.ObjectKey := ObjectKey(ACompanyCnpj, AAccessKey);
  Result.Sha256 := TAwsSignatureV4.Sha256Hex(AXml);
  Stamp := Timestamp;
  Signed := Headers('PUT', Result.ObjectKey, Result.Sha256, Stamp);
  SetLength(NetHeaders, Length(Signed));
  for Index := 0 to High(Signed) do
  begin
    Separator := Pos(':', Signed[Index]);
    NetHeaders[Index].Name := Copy(Signed[Index], 1, Separator - 1);
    NetHeaders[Index].Value := Trim(Copy(Signed[Index], Separator + 1, MaxInt));
  end;
  Body := TStringStream.Create(AXml, TEncoding.UTF8, False);
  Client := THTTPClient.Create;
  try
    Response := Client.Put('https://s3.' + FRegion + '.amazonaws.com/' + FBucket +
      '/' + Result.ObjectKey, Body, nil, NetHeaders);
    if (Response.StatusCode < 200) or (Response.StatusCode >= 300) then
      raise EInvalidOpException.Create('S3 recusou o XML. HTTP ' + Response.StatusCode.ToString);
  finally
    Client.Free;
    Body.Free;
  end;
end;

function TAwsS3XmlStorage.Get(const AObjectKey: string): string;
var
  Client: THTTPClient;
  Response: IHTTPResponse;
  HeadersArray: TArray<string>;
  NetHeaders: TNetHeaders;
  Index, Separator: Integer;
  Body: TStringStream;
  EmptyHash: string;
begin
  if Trim(AObjectKey) = '' then
    raise EArgumentException.Create('Chave do objeto obrigatoria.');
  EmptyHash := TAwsSignatureV4.Sha256Hex('');
  HeadersArray := Headers('GET', AObjectKey, EmptyHash, Timestamp);
  SetLength(NetHeaders, Length(HeadersArray));
  for Index := 0 to High(HeadersArray) do
  begin
    Separator := Pos(':', HeadersArray[Index]);
    NetHeaders[Index].Name := Copy(HeadersArray[Index], 1, Separator - 1);
    NetHeaders[Index].Value := Trim(Copy(HeadersArray[Index], Separator + 1, MaxInt));
  end;
  Body := TStringStream.Create('', TEncoding.UTF8, False);
  Client := THTTPClient.Create;
  try
    Response := Client.Get('https://s3.' + FRegion + '.amazonaws.com/' + FBucket +
      '/' + AObjectKey, Body, NetHeaders);
    if (Response.StatusCode < 200) or (Response.StatusCode >= 300) then
      raise EInvalidOpException.Create('S3 recusou a leitura do XML. HTTP ' + Response.StatusCode.ToString);
    Result := Body.DataString;
  finally
    Client.Free;
    Body.Free;
  end;
end;

procedure TAwsS3XmlStorage.Delete(const AObjectKey: string);
var
  Client: THTTPClient;
  Response: IHTTPResponse;
  HeadersArray: TArray<string>;
  NetHeaders: TNetHeaders;
  Index, Separator: Integer;
  EmptyHash: string;
begin
  if Trim(AObjectKey) = '' then
    Exit;
  EmptyHash := TAwsSignatureV4.Sha256Hex('');
  HeadersArray := Headers('DELETE', AObjectKey, EmptyHash, Timestamp);
  SetLength(NetHeaders, Length(HeadersArray));
  for Index := 0 to High(HeadersArray) do
  begin
    Separator := Pos(':', HeadersArray[Index]);
    NetHeaders[Index].Name := Copy(HeadersArray[Index], 1, Separator - 1);
    NetHeaders[Index].Value := Trim(Copy(HeadersArray[Index], Separator + 1, MaxInt));
  end;
  Client := THTTPClient.Create;
  try
    Response := Client.Delete('https://s3.' + FRegion + '.amazonaws.com/' + FBucket +
      '/' + AObjectKey, nil, NetHeaders);
    if (Response.StatusCode < 200) or (Response.StatusCode >= 300) then
      raise EInvalidOpException.Create('S3 recusou excluir o XML. HTTP ' +
        Response.StatusCode.ToString);
  finally
    Client.Free;
  end;
end;

end.
