unit Database.Migrations;

interface

uses Uni;

type
  TDatabaseMigrator = class
  public
    class procedure ApplyPending(const AConnection: TUniConnection); static;
  end;

implementation

uses Schema.Runner;

class procedure TDatabaseMigrator.ApplyPending(const AConnection: TUniConnection);
begin
  TSchemaRunner.Apply(AConnection);
end;

end.
