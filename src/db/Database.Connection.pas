unit Database.Connection;

interface

uses
  Uni;

type
  TDatabaseConnection = class
  public
    class function OpenFromEnvironment: TUniConnection; static;
  end;

implementation

uses
  PostgreSQLUniProvider,
  System.SysUtils;

var
  PostgreSQLProvider: TPostgreSQLUniProvider;

function RequiredEnvironmentValue(const AName: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then
    raise EInvalidOpException.Create('Variavel de ambiente obrigatoria ausente: ' + AName);
end;

class function TDatabaseConnection.OpenFromEnvironment: TUniConnection;
begin
  Result := TUniConnection.Create(nil);
  try
    Result.ProviderName := 'PostgreSQL';
    Result.Server := RequiredEnvironmentValue('FISCONEXA_DB_HOST');
    Result.Port := StrToInt(RequiredEnvironmentValue('FISCONEXA_DB_PORT'));
    Result.Database := RequiredEnvironmentValue('FISCONEXA_DB_NAME');
    Result.Username := RequiredEnvironmentValue('FISCONEXA_DB_USER');
    Result.Password := RequiredEnvironmentValue('FISCONEXA_DB_PASSWORD');
    Result.Connect;
  except
    Result.Free;
    raise;
  end;
end;

initialization

PostgreSQLProvider := TPostgreSQLUniProvider.Create(nil);

finalization

PostgreSQLProvider.Free;

end.
