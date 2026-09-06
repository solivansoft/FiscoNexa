unit Integrations.OpenSslCertificate;

interface

uses
  Application.CertificateIdentity,
  System.DateUtils,
  System.SysUtils;

type
  TOpenSslCertificateInspector = class(TInterfacedObject, ICertificateInspector)
  public
    function Inspect(const APfx, APassword: TBytes): TCertificateIdentity;
  end;

implementation

const
{$IFDEF MSWINDOWS}
  OpenSslLibrary = 'libcrypto-3-x64.dll';
{$ELSE}
  OpenSslLibrary = 'libcrypto.so.3';
{$ENDIF}

type
  TCTm = record
    tm_sec: Integer;
    tm_min: Integer;
    tm_hour: Integer;
    tm_mday: Integer;
    tm_mon: Integer;
    tm_year: Integer;
    tm_wday: Integer;
    tm_yday: Integer;
    tm_isdst: Integer;
  end;

function BIO_new_mem_buf(ABuffer: Pointer; ALength: Integer): Pointer; cdecl; external OpenSslLibrary;
function BIO_free(ABio: Pointer): Integer; cdecl; external OpenSslLibrary;
function d2i_PKCS12_bio(ABio: Pointer; AValue: Pointer): Pointer; cdecl; external OpenSslLibrary;
procedure PKCS12_free(AValue: Pointer); cdecl; external OpenSslLibrary;
function PKCS12_parse(APkcs12: Pointer; APassword: PAnsiChar; out APrivateKey,
  ACertificate, ACaCertificates: Pointer): Integer; cdecl; external OpenSslLibrary;
procedure EVP_PKEY_free(AKey: Pointer); cdecl; external OpenSslLibrary;
procedure X509_free(ACertificate: Pointer); cdecl; external OpenSslLibrary;
function X509_get_subject_name(ACertificate: Pointer): Pointer; cdecl; external OpenSslLibrary;
function X509_NAME_oneline(AName: Pointer; ABuffer: PAnsiChar;
  ABufferLength: Integer): PAnsiChar; cdecl; external OpenSslLibrary;
function X509_get0_notAfter(ACertificate: Pointer): Pointer; cdecl; external OpenSslLibrary;
function ASN1_TIME_to_tm(ATime: Pointer; out AValue: TCTm): Integer; cdecl; external OpenSslLibrary;
function OSSL_PROVIDER_load(ALibCtx: Pointer; AName: PAnsiChar): Pointer; cdecl; external OpenSslLibrary;
function OSSL_PROVIDER_set_default_search_path(ALibCtx: Pointer;
  APath: PAnsiChar): Integer; cdecl; external OpenSslLibrary;

procedure TryLoadLegacyProvider;
var
  ProviderName: AnsiString;
  ModulePath: AnsiString;
begin
  // Alguns A1 ainda usam algoritmos legados de PKCS#12, como RC2. O provider
  // e opcional: PFXs modernos continuam funcionando sem o modulo legacy.
  ProviderName := 'default';
  OSSL_PROVIDER_load(nil, PAnsiChar(ProviderName));
  ModulePath := AnsiString(IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
    'ossl-modules');
  if DirectoryExists(string(ModulePath)) then
    OSSL_PROVIDER_set_default_search_path(nil, PAnsiChar(ModulePath));
  ProviderName := 'legacy';
  OSSL_PROVIDER_load(nil, PAnsiChar(ProviderName));
end;

procedure RequireOpenSslSuccess(const AResult: Integer; const AMessage: string);
begin
  if AResult <> 1 then
    raise ECertificateInvalid.Create(AMessage);
end;

function SubjectFromCertificate(const ACertificate: Pointer): string;
var
  Buffer: TBytes;
begin
  SetLength(Buffer, 4096);
  if X509_NAME_oneline(X509_get_subject_name(ACertificate),
    PAnsiChar(@Buffer[0]), Length(Buffer)) = nil then
    raise ECertificateInvalid.Create('Nao foi possivel ler o subject do certificado.');
  Result := string(AnsiString(PAnsiChar(@Buffer[0])));
end;

function ValidUntilFromCertificate(const ACertificate: Pointer): TDateTime;
var
  Time: TCTm;
begin
  RequireOpenSslSuccess(ASN1_TIME_to_tm(X509_get0_notAfter(ACertificate), Time),
    'Nao foi possivel ler a validade do certificado.');
  Result := EncodeDateTime(Time.tm_year + 1900, Time.tm_mon + 1, Time.tm_mday,
    Time.tm_hour, Time.tm_min, Time.tm_sec, 0);
end;

function TOpenSslCertificateInspector.Inspect(const APfx,
  APassword: TBytes): TCertificateIdentity;
var
  Bio: Pointer;
  Pkcs12: Pointer;
  PrivateKey: Pointer;
  Certificate: Pointer;
  CaCertificates: Pointer;
  Password: AnsiString;
begin
  if Length(APfx) = 0 then
    raise ECertificateInvalid.Create('Arquivo PFX nao informado.');
  Bio := BIO_new_mem_buf(@APfx[0], Length(APfx));
  if Bio = nil then
    raise ECertificateInvalid.Create('OpenSSL nao abriu o PFX.');
  try
    Pkcs12 := d2i_PKCS12_bio(Bio, nil);
    if Pkcs12 = nil then
      raise ECertificateInvalid.Create('Arquivo PFX invalido.');
    try
      Password := AnsiString(TEncoding.UTF8.GetString(APassword));
      PrivateKey := nil;
      Certificate := nil;
      CaCertificates := nil;
      TryLoadLegacyProvider;
      RequireOpenSslSuccess(PKCS12_parse(Pkcs12, PAnsiChar(Password), PrivateKey,
        Certificate, CaCertificates), 'Senha do PFX invalida ou certificado inacessivel.');
      try
        Result.Subject := SubjectFromCertificate(Certificate);
        Result.Cnpj := ExtractCnpjFromCertificateSubject(Result.Subject);
        Result.ValidUntil := ValidUntilFromCertificate(Certificate);
        if Result.Cnpj = '' then
          raise ECertificateInvalid.Create('O certificado nao possui CNPJ valido.');
      finally
        EVP_PKEY_free(PrivateKey);
        X509_free(Certificate);
      end;
    finally
      PKCS12_free(Pkcs12);
    end;
  finally
    BIO_free(Bio);
  end;
end;

end.
