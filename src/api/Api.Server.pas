unit Api.Server;

interface

procedure RunApi;

implementation

uses
  Horse,
  FireDAC.Comp.Client,
  Api.Routes.Health,
  Database.Connection,
  Database.Migrations;

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
  RegisterHealthRoute;
  THorse.Listen(9000);
end;

end.
