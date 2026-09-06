unit Tests.AwsSignature;

interface

uses
  TestFramework;

type
  TAwsSignatureTests = class(TTestCase)
  public
    procedure TestSha256HexUsesLowerCase;
    procedure TestHmacSha256MatchesPublishedVector;
  end;

implementation

uses
  Integrations.AwsSignature,
  System.SysUtils;

procedure TAwsSignatureTests.TestSha256HexUsesLowerCase;
begin
  AssertEquals(
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    TAwsSignatureV4.Sha256Hex('')
  );
end;

procedure TAwsSignatureTests.TestHmacSha256MatchesPublishedVector;
begin
  AssertEquals(
    'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8',
    TAwsSignatureV4.Hex(TAwsSignatureV4.HmacSha256('The quick brown fox jumps over the lazy dog',
      TBytes.Create(Ord('k'), Ord('e'), Ord('y'))))
  );
end;

initialization

TTestHelper.RegisterTest(TAwsSignatureTests.Create);

end.
