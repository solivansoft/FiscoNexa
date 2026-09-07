unit Persistence.Authentication;

interface

uses
  Application.Authentication,
  FireDAC.Stan.Param, FireDAC.Comp.Client;

type
  TPostgresAuthenticationStore = class(TInterfacedObject, IAuthenticationStore)
  private
    FConnection: TFDConnection;
  public
    constructor Create(const AConnection: TFDConnection);
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

implementation

uses
  Data.DB,
  System.SysUtils;

constructor TPostgresAuthenticationStore.Create(const AConnection: TFDConnection);
begin
  inherited Create;
  if AConnection = nil then
    raise EArgumentNilException.Create('Conexao PostgreSQL nao informada.');
  FConnection := AConnection;
end;

procedure TPostgresAuthenticationStore.CreateFirstSuperadmin(const AEmail,
  ADisplayName, APasswordHash: string);
var
  Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'insert into usuarios (email, display_name, password_hash, platform_role) ' +
      'select :email, :display_name, :password_hash, ''superadmin'' ' +
      'where not exists (select 1 from usuarios where platform_role = ''superadmin'')';
    Query.ParamByName('email').AsString := AEmail;
    Query.ParamByName('display_name').AsString := ADisplayName;
    Query.ParamByName('password_hash').AsString := APasswordHash;
    Query.ExecSQL;
    if Query.RowsAffected <> 1 then
      raise EBootstrapAlreadyExists.Create('O primeiro superadmin ja foi criado.');
  finally
    Query.Free;
  end;
end;

function TPostgresAuthenticationStore.FindUserByEmail(const AEmail: string;
  out AUser: TAuthUser): Boolean;
var
  Query: TFDQuery;
begin
  AUser := Default(TAuthUser);
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'select id::text as id, email, display_name, password_hash, platform_role, ' +
      '(disabled_at is not null) as disabled from usuarios where lower(email) = lower(:email)';
    Query.ParamByName('email').AsString := AEmail;
    Query.Open;
    Result := not Query.IsEmpty;
    if Result then
    begin
      AUser.Id := Query.FieldByName('id').AsString;
      AUser.Email := Query.FieldByName('email').AsString;
      AUser.DisplayName := Query.FieldByName('display_name').AsString;
      AUser.PasswordHash := Query.FieldByName('password_hash').AsString;
      AUser.PlatformRole := Query.FieldByName('platform_role').AsString;
      AUser.Disabled := Query.FieldByName('disabled').AsBoolean;
    end;
  finally
    Query.Free;
  end;
end;

procedure TPostgresAuthenticationStore.CreateSession(const AUserId,
  AAccessTokenHash, ARefreshTokenHash: string; const AAccessExpiresAt,
  ARefreshExpiresAt: TDateTime);
var
  Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'insert into sessoes (user_id, access_token_hash, refresh_token_hash, ' +
      'access_expires_at, refresh_expires_at) values (cast(:user_id as uuid), ' +
      ':access_token_hash, :refresh_token_hash, now() + interval ''15 minutes'', ' +
      'now() + interval ''30 days'')';
    Query.ParamByName('user_id').AsString := AUserId;
    Query.ParamByName('access_token_hash').AsString := AAccessTokenHash;
    Query.ParamByName('refresh_token_hash').AsString := ARefreshTokenHash;
    Query.ExecSQL;
  finally
    Query.Free;
  end;
end;

function TPostgresAuthenticationStore.FindSessionUser(const ATokenHash: string;
  out AUser: TAuthUser): Boolean;
var
  Query: TFDQuery;
begin
  AUser := Default(TAuthUser);
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'select user_data.id::text as id, user_data.email, user_data.display_name, ' +
      'user_data.password_hash, user_data.platform_role, ' +
      '(user_data.disabled_at is not null) as disabled ' +
      'from sessoes session join usuarios user_data on user_data.id = session.user_id ' +
      'where session.access_token_hash = :token_hash and session.revoked_at is null ' +
      'and session.access_expires_at > now()';
    Query.ParamByName('token_hash').AsString := ATokenHash;
    Query.Open;
    Result := not Query.IsEmpty;
    if Result then
    begin
      AUser.Id := Query.FieldByName('id').AsString;
      AUser.Email := Query.FieldByName('email').AsString;
      AUser.DisplayName := Query.FieldByName('display_name').AsString;
      AUser.PasswordHash := Query.FieldByName('password_hash').AsString;
      AUser.PlatformRole := Query.FieldByName('platform_role').AsString;
      AUser.Disabled := Query.FieldByName('disabled').AsBoolean;
    end;
  finally
    Query.Free;
  end;
end;

function TPostgresAuthenticationStore.FindRefreshSessionUser(
  const ATokenHash: string; out AUser: TAuthUser): Boolean;
var
  Query: TFDQuery;
begin
  AUser := Default(TAuthUser);
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'select user_data.id::text as id, user_data.email, user_data.display_name, ' +
      'user_data.password_hash, user_data.platform_role, ' +
      '(user_data.disabled_at is not null) as disabled ' +
      'from sessoes session join usuarios user_data on user_data.id = session.user_id ' +
      'where session.refresh_token_hash = :token_hash and session.revoked_at is null ' +
      'and session.refresh_expires_at > now()';
    Query.ParamByName('token_hash').AsString := ATokenHash;
    Query.Open;
    Result := not Query.IsEmpty;
    if Result then
    begin
      AUser.Id := Query.FieldByName('id').AsString;
      AUser.Email := Query.FieldByName('email').AsString;
      AUser.DisplayName := Query.FieldByName('display_name').AsString;
      AUser.PasswordHash := Query.FieldByName('password_hash').AsString;
      AUser.PlatformRole := Query.FieldByName('platform_role').AsString;
      AUser.Disabled := Query.FieldByName('disabled').AsBoolean;
    end;
  finally
    Query.Free;
  end;
end;

procedure TPostgresAuthenticationStore.RevokeByRefreshTokenHash(const ATokenHash: string);
var
  Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text := 'update sessoes set revoked_at = now() ' +
      'where refresh_token_hash = :token_hash and revoked_at is null';
    Query.ParamByName('token_hash').AsString := ATokenHash;
    Query.ExecSQL;
  finally
    Query.Free;
  end;
end;

procedure TPostgresAuthenticationStore.RevokeByAccessTokenHash(const ATokenHash: string);
var
  Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text := 'update sessoes set revoked_at = now() ' +
      'where access_token_hash = :token_hash and revoked_at is null';
    Query.ParamByName('token_hash').AsString := ATokenHash;
    Query.ExecSQL;
  finally
    Query.Free;
  end;
end;

procedure TPostgresAuthenticationStore.ChangePassword(const AUserId,
  APasswordHash: string);
var
  Query: TFDQuery;
begin
  FConnection.StartTransaction;
  try
    Query := TFDQuery.Create(nil);
    try
      Query.Connection := FConnection;
      Query.SQL.Text := 'update usuarios set password_hash = :password_hash ' +
        'where id = cast(:user_id as uuid)';
      Query.ParamByName('password_hash').AsString := APasswordHash;
      Query.ParamByName('user_id').AsString := AUserId;
      Query.ExecSQL;
      Query.SQL.Text := 'update sessoes set revoked_at = now() ' +
        'where user_id = cast(:user_id as uuid) and revoked_at is null';
      Query.ParamByName('user_id').AsString := AUserId;
      Query.ExecSQL;
    finally
      Query.Free;
    end;
    FConnection.Commit;
  except
    FConnection.Rollback;
    raise;
  end;
end;

end.
