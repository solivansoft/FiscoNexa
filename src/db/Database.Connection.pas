unit Database.Connection;

interface

uses
  FireDAC.Stan.Param, FireDAC.Comp.Client;

type
  TDatabaseConnection = class
  public
    class function OpenFromEnvironment: TFDConnection; static;
  end;

implementation

uses
  FireDAC.ConsoleUI.Wait,
  FireDAC.Phys.PG,
  FireDAC.Phys.PGDef,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.DApt,
  System.SysUtils;

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
    Result.Params.Values['DriverID'] := 'PG';
    Result.Params.Values['CharacterSet'] := 'UTF8';
    Result.Params.Values['Server'] := RequiredEnvironmentValue('FISCONEXA_DB_HOST');
    Result.Params.Values['Port'] := IntToStr(StrToInt(RequiredEnvironmentValue('FISCONEXA_DB_PORT')));
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
