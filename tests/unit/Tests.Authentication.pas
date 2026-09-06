unit Tests.Authentication;

interface

uses TestFramework;

type
  TAuthenticationTests = class(TTestCase)
  public
    procedure TestBootstrapCreatesOnlyOneSuperadmin;
    procedure TestLoginCreatesAccessAndRefreshTokens;
    procedure TestRefreshRevokesPreviousToken;
    procedure TestRequireSuperadminRejectsNonSuperadmin;
    procedure TestChangePasswordRevokesCurrentSession;
  end;

implementation

uses
  Application.Authentication,
  Application.Passwords,
  System.SysUtils;

type
  TFakeAuthenticationStore = class(TInterfacedObject, IAuthenticationStore)
  private
    FUser: TAuthUser;
    FSessionUser: TAuthUser;
    FRefreshUser: TAuthUser;
    FRefreshRevoked: Boolean;
  public
    procedure CreateFirstSuperadmin(const AEmail, ADisplayName, APasswordHash: string);
    function FindUserByEmail(const AEmail: string; out AUser: TAuthUser): Boolean;
    procedure CreateSession(const AUserId, AAccessTokenHash, ARefreshTokenHash: string;
      const AAccessExpiresAt, ARefreshExpiresAt: TDateTime);
    function FindSessionUser(const ATokenHash: string; out AUser: TAuthUser): Boolean;
    function FindRefreshSessionUser(const ATokenHash: string; out AUser: TAuthUser): Boolean;
    procedure RevokeByRefreshTokenHash(const ATokenHash: string);
    procedure RevokeByAccessTokenHash(const ATokenHash: string);
    procedure ChangePassword(const AUserId, APasswordHash: string);
    procedure SetPlatformRole(const AValue: string);
    property User: TAuthUser read FUser;
    property RefreshRevoked: Boolean read FRefreshRevoked;
  end;

procedure TFakeAuthenticationStore.CreateFirstSuperadmin(const AEmail,
  ADisplayName, APasswordHash: string);
begin
  if FUser.Id <> '' then
    raise EBootstrapAlreadyExists.Create('already exists');
  FUser.Id := 'user-id';
  FUser.Email := AEmail;
  FUser.DisplayName := ADisplayName;
  FUser.PasswordHash := APasswordHash;
  FUser.PlatformRole := 'superadmin';
end;

function TFakeAuthenticationStore.FindUserByEmail(const AEmail: string;
  out AUser: TAuthUser): Boolean;
begin
  Result := SameText(AEmail, FUser.Email);
  if Result then AUser := FUser else AUser := Default(TAuthUser);
end;

procedure TFakeAuthenticationStore.CreateSession(const AUserId,
  AAccessTokenHash, ARefreshTokenHash: string; const AAccessExpiresAt,
  ARefreshExpiresAt: TDateTime);
begin
  FSessionUser := FUser;
  FRefreshUser := FUser;
end;

function TFakeAuthenticationStore.FindSessionUser(const ATokenHash: string;
  out AUser: TAuthUser): Boolean;
begin
  Result := FSessionUser.Id <> '';
  AUser := FSessionUser;
end;

function TFakeAuthenticationStore.FindRefreshSessionUser(const ATokenHash: string;
  out AUser: TAuthUser): Boolean;
begin
  Result := (FRefreshUser.Id <> '') and not FRefreshRevoked;
  AUser := FRefreshUser;
end;

procedure TFakeAuthenticationStore.RevokeByRefreshTokenHash(const ATokenHash: string);
begin
  FRefreshRevoked := True;
end;

procedure TFakeAuthenticationStore.RevokeByAccessTokenHash(const ATokenHash: string);
begin
  FSessionUser := Default(TAuthUser);
  FRefreshUser := Default(TAuthUser);
end;

procedure TFakeAuthenticationStore.SetPlatformRole(const AValue: string);
begin
  FUser.PlatformRole := AValue;
end;

procedure TFakeAuthenticationStore.ChangePassword(const AUserId, APasswordHash: string);
begin
  FUser.PasswordHash := APasswordHash;
  FSessionUser := Default(TAuthUser);
  FRefreshUser := Default(TAuthUser);
end;

procedure TAuthenticationTests.TestBootstrapCreatesOnlyOneSuperadmin;
var
  StoreObject: TFakeAuthenticationStore;
  Store: IAuthenticationStore;
  Service: TAuthenticationService;
begin
  StoreObject := TFakeAuthenticationStore.Create;
  Store := StoreObject;
  Service := TAuthenticationService.Create(Store);
  try
    Service.BootstrapFirstSuperadmin('admin@example.com', 'senha');
    AssertEquals('superadmin', StoreObject.User.PlatformRole);
    try
      Service.BootstrapFirstSuperadmin('second@example.com', 'senha');
      Fail('Bootstrap duplicado foi aceito.');
    except
      on E: EBootstrapAlreadyExists do AssertTrue(True);
    end;
  finally
    Service.Free;
  end;
end;

procedure TAuthenticationTests.TestLoginCreatesAccessAndRefreshTokens;
var
  Store: IAuthenticationStore;
  Service: TAuthenticationService;
  Session: TAuthSession;
begin
  Store := TFakeAuthenticationStore.Create;
  Service := TAuthenticationService.Create(Store);
  try
    Service.BootstrapFirstSuperadmin('admin@example.com', 'senha');
    Session := Service.Login('admin@example.com', 'senha');
    AssertTrue(Session.AccessToken <> '');
    AssertTrue(Session.RefreshToken <> '');
    AssertFalse(Session.AccessToken = Session.RefreshToken);
  finally
    Service.Free;
  end;
end;

procedure TAuthenticationTests.TestRefreshRevokesPreviousToken;
var
  StoreObject: TFakeAuthenticationStore;
  Store: IAuthenticationStore;
  Service: TAuthenticationService;
  Session: TAuthSession;
begin
  StoreObject := TFakeAuthenticationStore.Create;
  Store := StoreObject;
  Service := TAuthenticationService.Create(Store);
  try
    Service.BootstrapFirstSuperadmin('admin@example.com', 'senha');
    Session := Service.Login('admin@example.com', 'senha');
    Session := Service.Refresh(Session.RefreshToken);
    AssertTrue(StoreObject.RefreshRevoked);
    AssertTrue(Session.RefreshToken <> '');
  finally
    Service.Free;
  end;
end;

procedure TAuthenticationTests.TestRequireSuperadminRejectsNonSuperadmin;
var
  StoreObject: TFakeAuthenticationStore;
  Store: IAuthenticationStore;
  Service: TAuthenticationService;
begin
  StoreObject := TFakeAuthenticationStore.Create;
  Store := StoreObject;
  Service := TAuthenticationService.Create(Store);
  try
    StoreObject.CreateFirstSuperadmin('admin@example.com', 'admin', HashPassword('senha'));
    StoreObject.SetPlatformRole('user');
    StoreObject.CreateSession('user-id', 'access', 'refresh', Now + 1, Now + 1);
    try
      Service.RequireSuperadmin('Bearer access');
      Fail('Usuario comum foi aceito como superadmin.');
    except
      on E: EAuthenticationForbidden do AssertTrue(True);
    end;
  finally
    Service.Free;
  end;
end;

procedure TAuthenticationTests.TestChangePasswordRevokesCurrentSession;
var
  Store: IAuthenticationStore;
  Service: TAuthenticationService;
  Session: TAuthSession;
begin
  Store := TFakeAuthenticationStore.Create;
  Service := TAuthenticationService.Create(Store);
  try
    Service.BootstrapFirstSuperadmin('admin@example.com', 'senha');
    Session := Service.Login('admin@example.com', 'senha');
    Service.ChangePassword('Bearer ' + Session.AccessToken, 'senha', 'nova-senha');
    try
      Service.RequireSuperadmin('Bearer ' + Session.AccessToken);
      Fail('Sessao anterior continuou valida apos troca de senha.');
    except
      on E: EAuthenticationUnauthorized do AssertTrue(True);
    end;
    Session := Service.Login('admin@example.com', 'nova-senha');
    AssertTrue(Session.AccessToken <> '');
  finally
    Service.Free;
  end;
end;

initialization

TTestHelper.RegisterTest(TAuthenticationTests.Create);

end.
