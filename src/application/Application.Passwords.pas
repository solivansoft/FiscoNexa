unit Application.Passwords;

interface

uses
  System.SysUtils;

type
  EPasswordHashInvalid = class(Exception);

function HashPassword(const APassword: string): string;
function VerifyPassword(const APassword, AEncodedHash: string): Boolean;

implementation

uses
  System.Hash,
  System.NetEncoding;

const
  IterationCount = 150000;
  HashPrefix = 'pbkdf2-sha256';

function JoinBytes(const ALeft, ARight: TBytes): TBytes;
var
  Offset: Integer;
begin
  SetLength(Result, Length(ALeft) + Length(ARight));
  Offset := 0;
  if Length(ALeft) > 0 then
  begin
    Move(ALeft[0], Result[0], Length(ALeft));
    Offset := Length(ALeft);
  end;
  if Length(ARight) > 0 then
    Move(ARight[0], Result[Offset], Length(ARight));
end;

function BlockBytes(const ABlock: Integer): TBytes;
begin
  SetLength(Result, 4);
  Result[0] := (ABlock shr 24) and $FF;
  Result[1] := (ABlock shr 16) and $FF;
  Result[2] := (ABlock shr 8) and $FF;
  Result[3] := ABlock and $FF;
end;

function DeriveHash(const APassword: string; const ASalt: TBytes): TBytes;
var
  PasswordBytes: TBytes;
  Input: TBytes;
  U: TBytes;
  Index: Integer;
  ByteIndex: Integer;
begin
  PasswordBytes := TEncoding.UTF8.GetBytes(APassword);
  Input := JoinBytes(ASalt, BlockBytes(1));
  U := THashSHA2.GetHMACAsBytes(Input, PasswordBytes);
  Result := Copy(U);
  for Index := 2 to IterationCount do
  begin
    U := THashSHA2.GetHMACAsBytes(U, PasswordBytes);
    for ByteIndex := 0 to High(Result) do
      Result[ByteIndex] := Result[ByteIndex] xor U[ByteIndex];
  end;
end;

function NewSalt: TBytes;
var
  FirstId: TGUID;
  SecondId: TGUID;
begin
  FirstId := TGUID.NewGuid;
  SecondId := TGUID.NewGuid;
  SetLength(Result, SizeOf(FirstId) + SizeOf(SecondId));
  Move(FirstId, Result[0], SizeOf(FirstId));
  Move(SecondId, Result[SizeOf(FirstId)], SizeOf(SecondId));
end;

function HashPassword(const APassword: string): string;
var
  Salt: TBytes;
  Hash: TBytes;
begin
  if APassword = '' then
    raise EPasswordHashInvalid.Create('Senha vazia nao pode ser armazenada.');
  Salt := NewSalt;
  Hash := DeriveHash(APassword, Salt);
  Result := HashPrefix + '$' + IntToStr(IterationCount) + '$' +
    TNetEncoding.Base64.EncodeBytesToString(Salt) + '$' +
    TNetEncoding.Base64.EncodeBytesToString(Hash);
end;

function ConstantTimeEquals(const ALeft, ARight: TBytes): Boolean;
var
  Index: Integer;
  Difference: Byte;
begin
  Difference := Byte(Length(ALeft) xor Length(ARight));
  for Index := 0 to High(ALeft) do
    if Index < Length(ARight) then
      Difference := Difference or (ALeft[Index] xor ARight[Index])
    else
      Difference := Difference or ALeft[Index];
  Result := Difference = 0;
end;

function VerifyPassword(const APassword, AEncodedHash: string): Boolean;
var
  Parts: TArray<string>;
  Iterations: Integer;
  Salt: TBytes;
  Expected: TBytes;
  Actual: TBytes;
begin
  Result := False;
  Parts := AEncodedHash.Split(['$']);
  if Length(Parts) <> 4 then
    Exit;
  if Parts[0] <> HashPrefix then
    Exit;
  if not TryStrToInt(Parts[1], Iterations) or (Iterations <> IterationCount) then
    Exit;
  try
    Salt := TNetEncoding.Base64.DecodeStringToBytes(Parts[2]);
    Expected := TNetEncoding.Base64.DecodeStringToBytes(Parts[3]);
    Actual := DeriveHash(APassword, Salt);
    Result := ConstantTimeEquals(Actual, Expected);
  except
    on E: Exception do
      Result := False;
  end;
end;

end.
