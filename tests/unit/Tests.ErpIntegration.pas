unit Tests.ErpIntegration;

interface

uses
  TestFramework;

type
  TErpIntegrationTests = class(TTestCase)
  public
    procedure TestParseBearerTokenAcceptsBearerSchemeCaseInsensitive;
    procedure TestParseBearerTokenRejectsMissingBearerScheme;
    procedure TestParseBearerTokenRejectsEmptyToken;
  end;

implementation

uses
  Application.ErpIntegration;

procedure TErpIntegrationTests.TestParseBearerTokenAcceptsBearerSchemeCaseInsensitive;
begin
  AssertEquals('token-do-tenant', ParseErpBearerToken('bearer token-do-tenant'));
end;

procedure TErpIntegrationTests.TestParseBearerTokenRejectsMissingBearerScheme;
begin
  AssertEquals('', ParseErpBearerToken('Basic usuario:senha'));
end;

procedure TErpIntegrationTests.TestParseBearerTokenRejectsEmptyToken;
begin
  AssertEquals('', ParseErpBearerToken('Bearer   '));
end;

initialization

TTestHelper.RegisterTest(TErpIntegrationTests.Create);

end.
