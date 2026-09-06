unit Integrations.OpenSslCipher;

interface

uses
  Application.CertificateEnvelope,
  System.SysUtils;

type
  TOpenSslGcmCipher = class(TInterfacedObject, IEnvelopeCipher, IEnvelopeDecipher)
  private
    procedure ValidateKey(const AKey: TBytes);
  public
    function Encrypt(const AKey, APlaintext: TBytes): TEncryptedValue;
    function Decrypt(const AKey: TBytes; const AValue: TEncryptedValue): TBytes;
  end;

implementation

const
{$IFDEF MSWINDOWS}
  OpenSslLibrary = 'libcrypto-3-x64.dll';
{$ELSE}
  OpenSslLibrary = 'libcrypto.so.3';
{$ENDIF}
  GcmNonceLength = 12;
  GcmTagLength = 16;
  EvpCtrlGcmSetIvLength = $09;
  EvpCtrlGcmGetTag = $10;
  EvpCtrlGcmSetTag = $11;

function EVP_CIPHER_CTX_new: Pointer; cdecl; external OpenSslLibrary;
procedure EVP_CIPHER_CTX_free(AContext: Pointer); cdecl; external OpenSslLibrary;
function EVP_aes_256_gcm: Pointer; cdecl; external OpenSslLibrary;
function EVP_EncryptInit_ex(AContext, ACipher, AEngine, AKey, AIv: Pointer): Integer; cdecl; external OpenSslLibrary;
function EVP_EncryptUpdate(AContext, AOutput: Pointer; out AOutputLength: Integer;
  AInput: Pointer; AInputLength: Integer): Integer; cdecl; external OpenSslLibrary;
function EVP_EncryptFinal_ex(AContext, AOutput: Pointer; out AOutputLength: Integer): Integer; cdecl; external OpenSslLibrary;
function EVP_DecryptInit_ex(AContext, ACipher, AEngine, AKey, AIv: Pointer): Integer; cdecl; external OpenSslLibrary;
function EVP_DecryptUpdate(AContext, AOutput: Pointer; out AOutputLength: Integer;
  AInput: Pointer; AInputLength: Integer): Integer; cdecl; external OpenSslLibrary;
function EVP_DecryptFinal_ex(AContext, AOutput: Pointer; out AOutputLength: Integer): Integer; cdecl; external OpenSslLibrary;
function EVP_CIPHER_CTX_ctrl(AContext: Pointer; AControl, AArgument: Integer;
  AValue: Pointer): Integer; cdecl; external OpenSslLibrary;
function RAND_bytes(ABuffer: Pointer; ACount: Integer): Integer; cdecl; external OpenSslLibrary;

procedure RequireSuccess(const AResult: Integer; const AOperation: string);
begin
  if AResult <> 1 then
    raise EInvalidOpException.Create('OpenSSL falhou em ' + AOperation + '.');
end;

function BytesPointer(const AValue: TBytes): Pointer;
begin
  if Length(AValue) = 0 then
    Exit(nil);
  Result := @AValue[0];
end;

procedure ResizeToWrittenLength(var AValue: TBytes; const AWrittenLength: Integer);
begin
  SetLength(AValue, AWrittenLength);
end;

procedure TOpenSslGcmCipher.ValidateKey(const AKey: TBytes);
begin
  if Length(AKey) <> 32 then
    raise EArgumentException.Create('A data key deve possuir 32 bytes para AES-256-GCM.');
end;

function TOpenSslGcmCipher.Encrypt(const AKey, APlaintext: TBytes): TEncryptedValue;
var
  Context: Pointer;
  WrittenLength: Integer;
  FinalLength: Integer;
begin
  ValidateKey(AKey);
  SetLength(Result.Nonce, GcmNonceLength);
  RequireSuccess(RAND_bytes(BytesPointer(Result.Nonce), GcmNonceLength), 'RAND_bytes');

  Context := EVP_CIPHER_CTX_new;
  if Context = nil then
    raise EOutOfMemory.Create('OpenSSL nao criou o contexto de cifra.');
  try
    RequireSuccess(EVP_EncryptInit_ex(Context, EVP_aes_256_gcm, nil, nil, nil), 'EncryptInit');
    RequireSuccess(EVP_CIPHER_CTX_ctrl(Context, EvpCtrlGcmSetIvLength,
      GcmNonceLength, nil), 'SetIvLength');
    RequireSuccess(EVP_EncryptInit_ex(Context, nil, nil, BytesPointer(AKey),
      BytesPointer(Result.Nonce)), 'SetKeyAndNonce');
    SetLength(Result.Ciphertext, Length(APlaintext) + GcmTagLength);
    RequireSuccess(EVP_EncryptUpdate(Context, BytesPointer(Result.Ciphertext),
      WrittenLength, BytesPointer(APlaintext), Length(APlaintext)), 'EncryptUpdate');
    RequireSuccess(EVP_EncryptFinal_ex(Context,
      @Result.Ciphertext[WrittenLength], FinalLength), 'EncryptFinal');
    ResizeToWrittenLength(Result.Ciphertext, WrittenLength + FinalLength);
    SetLength(Result.Tag, GcmTagLength);
    RequireSuccess(EVP_CIPHER_CTX_ctrl(Context, EvpCtrlGcmGetTag, GcmTagLength,
      BytesPointer(Result.Tag)), 'GetTag');
  finally
    EVP_CIPHER_CTX_free(Context);
  end;
end;

function TOpenSslGcmCipher.Decrypt(const AKey: TBytes;
  const AValue: TEncryptedValue): TBytes;
var
  Context: Pointer;
  WrittenLength: Integer;
  FinalLength: Integer;
begin
  ValidateKey(AKey);
  if Length(AValue.Nonce) <> GcmNonceLength then
    raise EArgumentException.Create('Nonce GCM invalido.');
  if Length(AValue.Tag) <> GcmTagLength then
    raise EArgumentException.Create('Tag GCM invalida.');

  Context := EVP_CIPHER_CTX_new;
  if Context = nil then
    raise EOutOfMemory.Create('OpenSSL nao criou o contexto de cifra.');
  try
    RequireSuccess(EVP_DecryptInit_ex(Context, EVP_aes_256_gcm, nil, nil, nil), 'DecryptInit');
    RequireSuccess(EVP_CIPHER_CTX_ctrl(Context, EvpCtrlGcmSetIvLength,
      Length(AValue.Nonce), nil), 'SetIvLength');
    RequireSuccess(EVP_DecryptInit_ex(Context, nil, nil, BytesPointer(AKey),
      BytesPointer(AValue.Nonce)), 'SetKeyAndNonce');
    SetLength(Result, Length(AValue.Ciphertext));
    RequireSuccess(EVP_DecryptUpdate(Context, BytesPointer(Result), WrittenLength,
      BytesPointer(AValue.Ciphertext), Length(AValue.Ciphertext)), 'DecryptUpdate');
    RequireSuccess(EVP_CIPHER_CTX_ctrl(Context, EvpCtrlGcmSetTag, GcmTagLength,
      BytesPointer(AValue.Tag)), 'SetTag');
    RequireSuccess(EVP_DecryptFinal_ex(Context, @Result[WrittenLength], FinalLength),
      'DecryptFinal');
    ResizeToWrittenLength(Result, WrittenLength + FinalLength);
  finally
    EVP_CIPHER_CTX_free(Context);
  end;
end;

end.
