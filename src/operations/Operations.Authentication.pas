unit Operations.Authentication;

interface

uses
  Application.Authentication;

procedure BootstrapFirstSuperadmin(const AEmail, APassword: string);
function Login(const AEmail, APassword: string): TAuthSession;
function Refresh(const ARefreshToken: string): TAuthSession;
procedure Logout(const AAuthorization: string);
procedure ChangePassword(const AAuthorization, ACurrentPassword, ANewPassword: string);
function RequireSuperadmin(const AAuthorization: string): TAuthUser;

implementation

uses
  Database.Connection,
  Persistence.Authentication,
  FireDAC.Stan.Param, FireDAC.Comp.Client;

function CreateService(out AConnection: TFDConnection): TAuthenticationService;
var
  Store: IAuthenticationStore;
begin
  AConnection := TDatabaseConnection.OpenFromEnvironment;
  Store := TPostgresAuthenticationStore.Create(AConnection);
  Result := TAuthenticationService.Create(Store);
end;

function Refresh(const ARefreshToken: string): TAuthSession;
var
  Connection: TFDConnection;
  Service: TAuthenticationService;
begin
  Service := CreateService(Connection);
  try
    Result := Service.Refresh(ARefreshToken);
  finally
    Service.Free;
    Connection.Free;
  end;
end;

procedure Logout(const AAuthorization: string);
var
  Connection: TFDConnection;
  Service: TAuthenticationService;
begin
  Service := CreateService(Connection);
  try
    Service.Logout(AAuthorization);
  finally
    Service.Free;
    Connection.Free;
  end;
end;

procedure ChangePassword(const AAuthorization, ACurrentPassword, ANewPassword: string);
var
  Connection: TFDConnection;
  Service: TAuthenticationService;
begin
  Service := CreateService(Connection);
  try
    Service.ChangePassword(AAuthorization, ACurrentPassword, ANewPassword);
  finally
    Service.Free;
    Connection.Free;
  end;
end;

procedure BootstrapFirstSuperadmin(const AEmail, APassword: string);
var
  Connection: TFDConnection;
  Service: TAuthenticationService;
begin
  Service := CreateService(Connection);
  try
    Service.BootstrapFirstSuperadmin(AEmail, APassword);
  finally
    Service.Free;
    Connection.Free;
  end;
end;

function Login(const AEmail, APassword: string): TAuthSession;
var
  Connection: TFDConnection;
  Service: TAuthenticationService;
begin
  Service := CreateService(Connection);
  try
    Result := Service.Login(AEmail, APassword);
  finally
    Service.Free;
    Connection.Free;
  end;
end;

function RequireSuperadmin(const AAuthorization: string): TAuthUser;
var
  Connection: TFDConnection;
  Service: TAuthenticationService;
begin
  Service := CreateService(Connection);
  try
    Result := Service.RequireSuperadmin(AAuthorization);
  finally
    Service.Free;
    Connection.Free;
  end;
end;

end.
