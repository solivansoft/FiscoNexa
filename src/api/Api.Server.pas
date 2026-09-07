unit Api.Server;

interface

procedure RunApi;
procedure BootstrapAdmin(const AEmail, APassword: string);

implementation

uses
  System.JSON,
  Horse,
  Api.Routes.AdminErps,
  Api.Routes.Auth,
  Api.Routes.ErpCompanies,
  Api.Routes.ErpMonitoring,
  Api.Routes.ErpModules,
  FireDAC.Stan.Param, FireDAC.Comp.Client,
  Api.Routes.ErpDocuments,
  Api.Routes.Health,
  Api.Routes.Licenses,
  Database.Connection,
  Database.Migrations,
  Operations.Authentication,
  Operations.StructuredLogs;

procedure ApplyMigrations;
var
  Connection: TFDConnection;
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
  RegistrarLog('info', 'api', 'api_iniciando');
  THorse.AddOnTelemetry(
    procedure(const ARequest: THorseRequest; const AResponse: THorseResponse;
      const AExecutionTimeMS: Double)
    var J: TJSONObject;
    begin
      J := TJSONObject.Create;
      try
        J.AddPair('metodo', ARequest.RawWebRequest.Method);
        J.AddPair('rota', ARequest.PathInfo);
        J.AddPair('status_http', TJSONNumber.Create(AResponse.Status));
        J.AddPair('duracao_ms', TJSONNumber.Create(AExecutionTimeMS));
        RegistrarLog('info', 'api', 'requisicao_http', J.ToJSON);
      finally J.Free; end;
    end);
  RegisterHealthRoute;
  RegisterAuthRoutes;
  RegisterAdminErpRoutes;
  RegisterErpCompanyRoutes;
  RegisterErpModuleRoutes;
  RegisterErpDocumentRoutes;
  RegisterErpMonitoringRoutes;
  RegisterLicenseRoutes;
  THorse.Listen(9000);
end;

procedure BootstrapAdmin(const AEmail, APassword: string);
begin
  ApplyMigrations;
  Operations.Authentication.BootstrapFirstSuperadmin(AEmail, APassword);
end;

end.
