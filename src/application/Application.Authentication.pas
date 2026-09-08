unit Application.Authentication;

interface

uses System.SysUtils;

type
  EAuthenticationInvalid = class(Exception);
  EAuthenticationUnauthorized = class(Exception);
  EAuthenticationForbidden = class(Exception);
  EBootstrapAlreadyExists = class(Exception);

  TAuthUser = record
    Id: string;
    Email: string;
    DisplayName: string;
    PasswordHash: string;
    PlatformRole: string;
    Disabled: Boolean;
  end;

  TAuthSession = record
    AccessToken: string;
    RefreshToken: string;
    ExpiresAt: TDateTime;
  end;

  IAuthenticationStore = interface
    ['{EF59B1B6-73D7-4CFA-9BDE-7963F3059109}']
    procedure CreateFirstSuperadmin(const AEmail, ADisplayName, APasswordHash: string);
    function FindUserByEmail(const AEmail: string; out AUser: TAuthUser): Boolean;
    procedure CreateSession(const AUserId, AAccessTokenHash, ARefreshTokenHash: string;
      const AAccessExpiresAt, ARefreshExpiresAt: TDateTime);
    function FindSessionUser(const ATokenHash: string; out AUser: TAuthUser): Boolean;
    function FindRefreshSessionUser(const ATokenHash: string; out AUser: TAuthUser): Boolean;
    procedure RevokeByRefreshTokenHash(const ATokenHash: string);
    procedure RevokeByAccessTokenHash(const ATokenHash: string);
    procedure ChangePassword(const AUserId, APasswordHash: string);
  end;

  TAuthenticationService = class
  private
    FStore: IAuthenticationStore;
    function NewToken: string;
  public
    constructor Create(const AStore: IAuthenticationStore);
    procedure BootstrapFirstSuperadmin(const AEmail, APassword: string);
    function Login(const AEmail, APassword: string): TAuthSession;
    function Refresh(const ARefreshToken: string): TAuthSession;
    procedure Logout(const AAuthorization: string);
    procedure ChangePassword(const AAuthorization, ACurrentPassword, ANewPassword: string);
    function RequireSuperadmin(const AAuthorization: string): TAuthUser;
  end;

implementation

uses
  Application.Authorization,
  Application.Passwords,
  System.DateUtils,
  System.Hash;

const
  AccessTokenDurationMinutes = 15;
  RefreshTokenDurationDays = 30;

constructor TAuthenticationService.Create(const AStore: IAuthenticationStore);
begin
  inherited Create;
  if AStore = nil then
    raise EArgumentNilException.Create('Persistencia de autenticacao nao informada.');
  FStore := AStore;
end;

function TAuthenticationService.NewToken: string;
var
  FirstId: TGUID;
  SecondId: TGUID;
begin
  FirstId := TGUID.NewGuid;
  SecondId := TGUID.NewGuid;
  Result := THashSHA2.GetHashString(FirstId.ToString + SecondId.ToString).ToLowerInvariant;
end;

procedure TAuthenticationService.BootstrapFirstSuperadmin(const AEmail,
  APassword: string);
var
  User: TAuthUser;
  Email: string;
begin
  Email := LowerCase(Trim(AEmail));
  if (Email = '') or (APassword = '') then
    raise EAuthenticationInvalid.Create('Email e senha sao obrigatorios.');
  if FStore.FindUserByEmail(Email, User) then
    raise EBootstrapAlreadyExists.Create('O primeiro superadmin ja foi criado.');
  FStore.CreateFirstSuperadmin(Email, Email, HashPassword(APassword));
end;

function TAuthenticationService.Login(const AEmail, APassword: string): TAuthSession;
var
  User: TAuthUser;
begin
  if not FStore.FindUserByEmail(LowerCase(Trim(AEmail)), User) or User.Disabled or
    not VerifyPassword(APassword, User.PasswordHash) then
    raise EAuthenticationUnauthorized.Create('Email ou senha invalidos.');
  Result.AccessToken := NewToken;
  Result.RefreshToken := NewToken;
  Result.ExpiresAt := IncMinute(Now, AccessTokenDurationMinutes);
  FStore.CreateSession(User.Id, THashSHA2.GetHashString(Result.AccessToken).ToLowerInvariant,
    THashSHA2.GetHashString(Result.RefreshToken).ToLowerInvariant,
    Result.ExpiresAt, IncDay(Now, RefreshTokenDurationDays));
end;

function TAuthenticationService.Refresh(const ARefreshToken: string): TAuthSession;
var
  User: TAuthUser;
  RefreshTokenHash: string;
begin
  RefreshTokenHash := THashSHA2.GetHashString(ARefreshToken).ToLowerInvariant;
  if (ARefreshToken = '') or not FStore.FindRefreshSessionUser(RefreshTokenHash, User) or
    User.Disabled then
    raise EAuthenticationUnauthorized.Create('Refresh token ausente ou invalido.');
  FStore.RevokeByRefreshTokenHash(RefreshTokenHash);
  Result.AccessToken := NewToken;
  Result.RefreshToken := NewToken;
  Result.ExpiresAt := IncMinute(Now, AccessTokenDurationMinutes);
  FStore.CreateSession(User.Id, THashSHA2.GetHashString(Result.AccessToken).ToLowerInvariant,
    THashSHA2.GetHashString(Result.RefreshToken).ToLowerInvariant,
    Result.ExpiresAt, IncDay(Now, RefreshTokenDurationDays));
end;

procedure TAuthenticationService.Logout(const AAuthorization: string);
var
  Token: string;
  User: TAuthUser;
begin
  Token := ParseBearerToken(AAuthorization);
  if (Token = '') or not FStore.FindSessionUser(
    THashSHA2.GetHashString(Token).ToLowerInvariant, User) or User.Disabled then
    raise EAuthenticationUnauthorized.Create('Sessao ausente ou invalida.');
  FStore.RevokeByAccessTokenHash(THashSHA2.GetHashString(Token).ToLowerInvariant);
end;

procedure TAuthenticationService.ChangePassword(const AAuthorization,
  ACurrentPassword, ANewPassword: string);
var
  User: TAuthUser;
  Token: string;
begin
  if ANewPassword = '' then
    raise EAuthenticationInvalid.Create('Nova senha obrigatoria.');
  Token := ParseBearerToken(AAuthorization);
  if (Token = '') or not FStore.FindSessionUser(
    THashSHA2.GetHashString(Token).ToLowerInvariant, User) or User.Disabled then
    raise EAuthenticationUnauthorized.Create('Sessao ausente ou invalida.');
  if not VerifyPassword(ACurrentPassword, User.PasswordHash) then
    raise EAuthenticationUnauthorized.Create('Senha atual invalida.');
  FStore.ChangePassword(User.Id, HashPassword(ANewPassword));
end;

function TAuthenticationService.RequireSuperadmin(
  const AAuthorization: string): TAuthUser;
var
  Token: string;
begin
  Token := ParseBearerToken(AAuthorization);
  if (Token = '') or not FStore.FindSessionUser(
    THashSHA2.GetHashString(Token).ToLowerInvariant, Result) or Result.Disabled then
    raise EAuthenticationUnauthorized.Create('Sessao ausente ou invalida.');
  if Result.PlatformRole <> 'superadmin' then
    raise EAuthenticationForbidden.Create('Superadmin obrigatorio.');
end;

end.
