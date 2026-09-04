unit Database.Connection;

interface

uses
  FireDAC.Comp.Client;

type
  TDatabaseConnection = class
  public
    class function OpenFromEnvironment: TFDConnection; static;
  end;

implementation

uses
  System.SysUtils,
  FireDAC.DApt,
  FireDAC.Phys.PG,
  FireDAC.Phys.PGDef,
  FireDAC.Stan.Async,
  FireDAC.Stan.Def,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Param;

function RequiredEnvironmentValue(const AName: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then
    raise EInvalidOpException.Create('Variavel de ambiente obrigatoria ausente: ' + AName);
end;

class function TDatabaseConnection.OpenFromEnvironment: TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  try
    Result.LoginPrompt := False;
    Result.DriverName := 'PG';
    Result.Params.Values['Server'] := RequiredEnvironmentValue('FISCONEXA_DB_HOST');
    Result.Params.Values['Port'] := RequiredEnvironmentValue('FISCONEXA_DB_PORT');
    Result.Params.Values['Database'] := RequiredEnvironmentValue('FISCONEXA_DB_NAME');
    Result.Params.Values['User_Name'] := RequiredEnvironmentValue('FISCONEXA_DB_USER');
    Result.Params.Values['Password'] := RequiredEnvironmentValue('FISCONEXA_DB_PASSWORD');
    Result.Connected := True;
  except
    Result.Free;
    raise;
  end;
end;

end.
