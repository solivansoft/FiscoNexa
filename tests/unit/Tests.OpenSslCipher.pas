unit Tests.OpenSslCipher;

interface

uses
  TestFramework;

type
  TOpenSslCipherTests = class(TTestCase)
  public
    procedure TestEncryptDecryptRoundTrip;
    procedure TestDecryptRejectsChangedTag;
  end;

implementation

uses
  System.SysUtils,
  Application.CertificateEnvelope,
  Integrations.OpenSslCipher;

function TestKey: TBytes;
begin
  Result := TBytes.Create(
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31);
end;

procedure TOpenSslCipherTests.TestEncryptDecryptRoundTrip;
var
  Cipher: TOpenSslGcmCipher;
  Encrypted: TEncryptedValue;
  Plaintext: TBytes;
begin
  Cipher := TOpenSslGcmCipher.Create;
  try
    Encrypted := Cipher.Encrypt(TestKey, TBytes.Create(10, 20, 30, 40));
    Plaintext := Cipher.Decrypt(TestKey, Encrypted);
    AssertEquals(4, Length(Plaintext));
    AssertEquals(10, Plaintext[0]);
    AssertEquals(40, Plaintext[3]);
  finally
    Cipher.Free;
  end;
end;

procedure TOpenSslCipherTests.TestDecryptRejectsChangedTag;
var
  Cipher: TOpenSslGcmCipher;
  Encrypted: TEncryptedValue;
begin
  Cipher := TOpenSslGcmCipher.Create;
  try
    Encrypted := Cipher.Encrypt(TestKey, TBytes.Create(10));
    Encrypted.Tag[0] := Encrypted.Tag[0] xor $FF;
    try
      Cipher.Decrypt(TestKey, Encrypted);
      Fail('Tag alterada foi aceita.');
    except
      on E: EInvalidOpException do
        AssertTrue(True);
    end;
  finally
    Cipher.Free;
  end;
end;

initialization

TTestHelper.RegisterTest(TOpenSslCipherTests.Create);

end.
