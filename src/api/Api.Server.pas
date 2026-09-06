unit Api.Server;

interface

procedure RunApi;
procedure BootstrapAdmin(const AEmail, APassword: string);

implementation

uses
  Horse,
  Api.Routes.AdminErps,
  Api.Routes.Auth,
  Api.Routes.ErpCompanies,
  Api.Routes.ErpMonitoring,
  Api.Routes.ErpModules,
  Uni,
  Api.Routes.ErpDocuments,
  Api.Routes.Health,
  Database.Connection,
  Database.Migrations,
  Operations.Authentication;

procedure ApplyMigrations;
var
  Connection: TUniConnection;
begin
  Connection := TDatabaseConnection.OpenFromEnvironment;
  try
    TDatabaseMigrator.ApplyPending(Connection);
  finally
    Connection.Free;
  end;
end;

procedure RunApi;
begin
  ApplyMigrations;
  RegisterHealthRoute;
  RegisterAuthRoutes;
  RegisterAdminErpRoutes;
  RegisterErpCompanyRoutes;
  RegisterErpModuleRoutes;
  RegisterErpDocumentRoutes;
  RegisterErpMonitoringRoutes;
  THorse.Listen(9000);
end;

procedure BootstrapAdmin(const AEmail, APassword: string);
begin
  ApplyMigrations;
  Operations.Authentication.BootstrapFirstSuperadmin(AEmail, APassword);
end;

end.
