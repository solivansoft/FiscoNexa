unit Integrations.OpenSslToken;

interface

uses
  Application.CompanyOnboarding;

type
  TOpenSslTokenGenerator = class(TInterfacedObject, IIntegrationTokenGenerator)
  public
    function Generate: string;
  end;

implementation

uses
  System.SysUtils;

const
{$IFDEF MSWINDOWS}
  OpenSslLibrary = 'libcrypto-3-x64.dll';
{$ELSE}
  OpenSslLibrary = 'libcrypto.so.3';
{$ENDIF}
  TokenByteLength = 32;

function RAND_bytes(ABuffer: Pointer; ACount: Integer): Integer; cdecl;
  external OpenSslLibrary;

function TOpenSslTokenGenerator.Generate: string;
var
  Bytes: TBytes;
  Index: Integer;
begin
  SetLength(Bytes, TokenByteLength);
  if RAND_bytes(@Bytes[0], Length(Bytes)) <> 1 then
    raise EInvalidOpException.Create('OpenSSL nao gerou token de integracao.');
  Result := '';
  for Index := 0 to High(Bytes) do
    Result := Result + IntToHex(Bytes[Index], 2);
end;

end.
