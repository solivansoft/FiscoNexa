unit Application.CertificateIdentity;

interface

uses
  System.SysUtils;

type
  ECertificateInvalid = class(Exception);

  TCertificateIdentity = record
    Cnpj: string;
    Subject: string;
    ValidUntil: TDateTime;
  end;

  ICertificateInspector = interface
    ['{D1C1274A-123A-4C0D-BF49-EC39E674554F}']
    function Inspect(const APfx, APassword: TBytes): TCertificateIdentity;
  end;

function ExtractCnpjFromCertificateSubject(const ASubject: string): string;

implementation

function ExtractDigits(const AValue: string; const AStartIndex: Integer): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := AStartIndex to Length(AValue) do
  begin
    if CharInSet(AValue[Index], ['0'..'9']) then
      Result := Result + AValue[Index]
    else if Result <> '' then
      Break;
    if Length(Result) = 14 then
      Exit;
  end;
end;

function ExtractCnpjFromCertificateSubject(const ASubject: string): string;
const
  CnpjOid = '2.16.76.1.3.3';
var
  OidPosition: Integer;
  CommonNameStart: Integer;
  CommonNameEnd: Integer;
  ColonPosition: Integer;
begin
  OidPosition := Pos(CnpjOid, ASubject);
  if OidPosition > 0 then
    Result := ExtractDigits(ASubject, OidPosition + Length(CnpjOid))
  else
  begin
    CommonNameStart := Pos('CN=', UpperCase(ASubject));
    if CommonNameStart = 0 then
      Exit('');
    CommonNameEnd := Pos(',', Copy(ASubject, CommonNameStart, MaxInt));
    if CommonNameEnd = 0 then
      CommonNameEnd := Length(ASubject) - CommonNameStart + 2;
    ColonPosition := Pos(':', Copy(ASubject, CommonNameStart, CommonNameEnd - 1));
    if ColonPosition = 0 then
      Exit('');
    Result := ExtractDigits(ASubject, CommonNameStart + ColonPosition);
  end;
  if Length(Result) <> 14 then
    Result := '';
end;

end.
