unit Api.Server;

interface

procedure RunApi;
procedure BootstrapAdmin(const AEmail, APassword: string);
procedure ReconciliarCobrancas;

implementation

uses
  System.SysUtils,
  Persistence.Assinaturas,
  System.JSON,
  Horse,
  Api.Routes.Documentation,
  Api.Routes.Assinaturas,
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

procedure ReconciliarCobrancas;
var C: TFDConnection; S: TAssinaturasService; Total: Integer;
begin
  C:=TDatabaseConnection.OpenFromEnvironment;
  try
    S:=TAssinaturasService.Create(C);
    try
      Total:=S.Reconciliar;
      RegistrarLog('info','cobrancas','reconciliacao_concluida',
        '{"cobrancas_processadas":'+IntToStr(Total)+'}');
    finally S.Free; end;
  finally C.Free; end;
end;

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
var
  Port: Integer;
  ConfiguredPort: string;
  BindAddress: string;
begin
  ConfiguredPort := GetEnvironmentVariable('FISCONEXA_HTTP_PORT');
  Port := 9000;
  if ConfiguredPort <> '' then
    if not TryStrToInt(ConfiguredPort, Port) or (Port < 1) or (Port > 65535) then
      raise EInvalidOpException.Create('FISCONEXA_HTTP_PORT deve estar entre 1 e 65535.');
  BindAddress := GetEnvironmentVariable('FISCONEXA_HTTP_HOST');
  if BindAddress = '' then BindAddress := '0.0.0.0';
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
  RegisterDocumentationRoutes;
  RegisterSubscriptionRoutes;
  RegisterAuthRoutes;
  RegisterAdminErpRoutes;
  RegisterErpCompanyRoutes;
  RegisterErpModuleRoutes;
  RegisterErpDocumentRoutes;
  RegisterErpMonitoringRoutes;
  RegisterLicenseRoutes;
  THorse.Listen(Port, BindAddress);
end;

procedure BootstrapAdmin(const AEmail, APassword: string);
begin
  ApplyMigrations;
  Operations.Authentication.BootstrapFirstSuperadmin(AEmail, APassword);
end;

end.
