unit Tests.ErpKeys;

interface

uses
  TestFramework;

type
  TErpKeysTests = class(TTestCase)
  public
    procedure TestHashErpKeyIsStable;
    procedure TestHasErpScopeAcceptsGrantedScope;
    procedure TestHasErpScopeRejectsMissingScope;
    procedure TestHasErpScopeRejectsInvalidJson;
    procedure TestAuthenticateErpKeyReturnsPrincipalForKnownKey;
    procedure TestAuthenticateErpKeyRejectsUnknownKey;
    procedure TestRequireErpScopeRejectsMissingScope;
  end;

implementation

uses
  Application.ErpKeys;

type
  TFakeErpKeyReader = class(TInterfacedObject, IErpKeyReader)
  private
    FExpectedHash: string;
    FPrincipal: TErpKeyPrincipal;
  public
    constructor Create(const AToken: string; const AScopesJson: string);
    function FindActiveByHash(const AKeyHash: string;
      out APrincipal: TErpKeyPrincipal): Boolean;
  end;

constructor TFakeErpKeyReader.Create(const AToken: string;
  const AScopesJson: string);
begin
  inherited Create;
  FExpectedHash := HashErpKey(AToken);
  FPrincipal.KeyId := 'key-id';
  FPrincipal.OrganizationId := 'organization-id';
  FPrincipal.ScopesJson := AScopesJson;
end;

function TFakeErpKeyReader.FindActiveByHash(const AKeyHash: string;
  out APrincipal: TErpKeyPrincipal): Boolean;
begin
  Result := AKeyHash = FExpectedHash;
  if Result then
    APrincipal := FPrincipal
  else
    APrincipal := Default(TErpKeyPrincipal);
end;

procedure TErpKeysTests.TestHashErpKeyIsStable;
begin
  AssertEquals(
    'eaeeef06ac4972e14c10ddaaf051d3722ff5a4ccc36301928bf54bdd1f851f95',
    HashErpKey('erp-bootstrap-key')
  );
end;

procedure TErpKeysTests.TestHasErpScopeAcceptsGrantedScope;
begin
  AssertTrue(HasErpScope('["companies:write","modules:write"]', 'companies:write'));
end;

procedure TErpKeysTests.TestHasErpScopeRejectsMissingScope;
begin
  AssertFalse(HasErpScope('["companies:write"]', 'documents:read'));
end;

procedure TErpKeysTests.TestHasErpScopeRejectsInvalidJson;
begin
  AssertFalse(HasErpScope('not-json', 'companies:write'));
end;

procedure TErpKeysTests.TestAuthenticateErpKeyReturnsPrincipalForKnownKey;
var
  Reader: IErpKeyReader;
  Principal: TErpKeyPrincipal;
begin
  Reader := TFakeErpKeyReader.Create('known-key', '["companies:onboard"]');
  Principal := AuthenticateErpKey('Bearer known-key', Reader);
  AssertEquals('key-id', Principal.KeyId);
  AssertEquals('organization-id', Principal.OrganizationId);
end;

procedure TErpKeysTests.TestAuthenticateErpKeyRejectsUnknownKey;
var
  Reader: IErpKeyReader;
begin
  Reader := TFakeErpKeyReader.Create('known-key', '["companies:onboard"]');
  try
    AuthenticateErpKey('Bearer other-key', Reader);
    Fail('Chave desconhecida foi aceita.');
  except
    on E: EErpKeyUnauthorized do
      AssertTrue(True);
  end;
end;

procedure TErpKeysTests.TestRequireErpScopeRejectsMissingScope;
var
  Principal: TErpKeyPrincipal;
begin
  Principal.ScopesJson := '["companies:onboard"]';
  try
    RequireErpScope(Principal, 'documents:read');
    Fail('Escopo ausente foi aceito.');
  except
    on E: EErpKeyUnauthorized do
      AssertTrue(True);
  end;
end;

initialization

TTestHelper.RegisterTest(TErpKeysTests.Create);

end.
