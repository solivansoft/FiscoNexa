unit Integrations.AwsSignature;

interface

uses
  System.SysUtils;

type
  TAwsSignatureV4 = class
  public
    class function Sha256Hex(const AValue: string): string; static;
    class function HmacSha256(const AData: string; const AKey: TBytes): TBytes; static;
    class function Hex(const AValue: TBytes): string; static;
    class function Sign(const ASecretKey, ADateStamp, ARegion, AService,
      AStringToSign: string): string; static;
  end;

implementation

uses
  System.Hash;

class function TAwsSignatureV4.Sha256Hex(const AValue: string): string;
begin
  Result := THashSHA2.GetHashString(AValue).ToLowerInvariant;
end;

class function TAwsSignatureV4.HmacSha256(const AData: string;
  const AKey: TBytes): TBytes;
begin
  Result := THashSHA2.GetHMACAsBytes(AData, AKey);
end;

class function TAwsSignatureV4.Hex(const AValue: TBytes): string;
var
  Item: Byte;
begin
  Result := '';
  for Item in AValue do
    Result := Result + IntToHex(Item, 2).ToLowerInvariant;
end;

class function TAwsSignatureV4.Sign(const ASecretKey, ADateStamp, ARegion,
  AService, AStringToSign: string): string;
var
  DateKey: TBytes;
  RegionKey: TBytes;
  ServiceKey: TBytes;
  SigningKey: TBytes;
begin
  DateKey := HmacSha256(ADateStamp, TEncoding.UTF8.GetBytes('AWS4' + ASecretKey));
  RegionKey := HmacSha256(ARegion, DateKey);
  ServiceKey := HmacSha256(AService, RegionKey);
  SigningKey := HmacSha256('aws4_request', ServiceKey);
  Result := Hex(HmacSha256(AStringToSign, SigningKey));
end;

end.
