unit Tests.ErpAdministration;

interface

uses TestFramework;

type
  TErpAdministrationTests = class(TTestCase)
  public
    procedure TestCreateErpReturnsSecretButStoreReceivesOnlyHash;
    procedure TestRotateRejectsUnknownErp;
    procedure TestRevokeRejectsUnknownErp;
  end;

implementation

uses
  Application.ErpAdministration,
  Application.ErpKeys;

type
  TFakeErpAdministrationStore = class(TInterfacedObject, IErpAdministrationStore)
  private
    FExists: Boolean;
    FLastHash: string;
  public
    function CreateErp(const ALegalName: string): string;
    function ErpExists(const AErpId: string): Boolean;
    function CreateKey(const AErpId, ALabel, AKeyHash: string): string;
    procedure RevokeKey(const AErpId, AKeyId: string);
    property Exists: Boolean read FExists write FExists;
    property LastHash: string read FLastHash;
  end;

function TFakeErpAdministrationStore.CreateErp(const ALegalName: string): string;
begin
  FExists := True;
  Result := 'erp-id';
end;

function TFakeErpAdministrationStore.ErpExists(const AErpId: string): Boolean;
begin
  Result := FExists and (AErpId = 'erp-id');
end;

function TFakeErpAdministrationStore.CreateKey(const AErpId, ALabel,
  AKeyHash: string): string;
begin
  FLastHash := AKeyHash;
  Result := 'key-id';
end;

procedure TFakeErpAdministrationStore.RevokeKey(const AErpId, AKeyId: string);
begin
  if not ErpExists(AErpId) or (AKeyId <> 'key-id') then
    raise EErpNotFound.Create('not found');
end;

procedure TErpAdministrationTests.TestCreateErpReturnsSecretButStoreReceivesOnlyHash;
var
  StoreObject: TFakeErpAdministrationStore;
  Store: IErpAdministrationStore;
  Service: TErpAdministrationService;
  Issue: TErpKeyIssue;
begin
  StoreObject := TFakeErpAdministrationStore.Create;
  Store := StoreObject;
  Service := TErpAdministrationService.Create(Store);
  try
    Issue := Service.CreateErp('ERP Teste', 'producao');
    AssertEquals('erp-id', Issue.ErpId);
    AssertTrue(Issue.Secret <> '');
    AssertEquals(HashErpKey(Issue.Secret), StoreObject.LastHash);
    AssertFalse(Issue.Secret = StoreObject.LastHash);
  finally
    Service.Free;
  end;
end;

procedure TErpAdministrationTests.TestRotateRejectsUnknownErp;
var
  Store: IErpAdministrationStore;
  Service: TErpAdministrationService;
begin
  Store := TFakeErpAdministrationStore.Create;
  Service := TErpAdministrationService.Create(Store);
  try
    try
      Service.RotateKey('unknown', 'producao');
      Fail('ERP inexistente aceito para rotacao.');
    except
      on E: EErpNotFound do AssertTrue(True);
    end;
  finally Service.Free; end;
end;

procedure TErpAdministrationTests.TestRevokeRejectsUnknownErp;
var
  Store: IErpAdministrationStore;
  Service: TErpAdministrationService;
begin
  Store := TFakeErpAdministrationStore.Create;
  Service := TErpAdministrationService.Create(Store);
  try
    try
      Service.RevokeKey('unknown', 'key-id');
      Fail('ERP inexistente aceito para revogacao.');
    except
      on E: EErpNotFound do AssertTrue(True);
    end;
  finally Service.Free; end;
end;

initialization

TTestHelper.RegisterTest(TErpAdministrationTests.Create);

end.
