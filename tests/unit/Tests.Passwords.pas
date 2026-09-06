unit Tests.Passwords;

interface

uses
  TestFramework;

type
  TPasswordsTests = class(TTestCase)
  public
    procedure TestHashVerifiesOriginalPassword;
    procedure TestHashRejectsDifferentPassword;
    procedure TestHashRejectsMalformedValue;
  end;

implementation

uses Application.Passwords;

procedure TPasswordsTests.TestHashVerifiesOriginalPassword;
var
  PasswordHash: string;
begin
  PasswordHash := HashPassword('senha-de-teste');
  AssertTrue(VerifyPassword('senha-de-teste', PasswordHash));
end;

procedure TPasswordsTests.TestHashRejectsDifferentPassword;
var
  PasswordHash: string;
begin
  PasswordHash := HashPassword('senha-de-teste');
  AssertFalse(VerifyPassword('outra-senha', PasswordHash));
end;

procedure TPasswordsTests.TestHashRejectsMalformedValue;
begin
  AssertFalse(VerifyPassword('senha', 'nao-e-um-hash'));
end;

initialization

TTestHelper.RegisterTest(TPasswordsTests.Create);

end.
