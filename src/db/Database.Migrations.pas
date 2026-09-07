unit Database.Migrations;

interface

uses FireDAC.Stan.Param, FireDAC.Comp.Client;

type
  TDatabaseMigrator = class
  public
    class procedure ApplyPending(const AConnection: TFDConnection); static;
  end;

implementation

uses Schema.Runner;

class procedure TDatabaseMigrator.ApplyPending(const AConnection: TFDConnection);
begin
  TSchemaRunner.Apply(AConnection);
end;

end.
