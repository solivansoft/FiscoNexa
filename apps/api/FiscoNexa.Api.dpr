program FiscoNexa.Api;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Api.Server in '..\..\src\api\Api.Server.pas';

begin
  if SameText(ParamStr(1), '--reconciliar-cobrancas') then
  begin
    ReconciliarCobrancas;
    Exit;
  end;
  if SameText(ParamStr(1), '--user-create') then
  begin
    if ParamCount <> 3 then
      raise Exception.Create('Uso: FiscoNexa.Api --user-create <email> <senha>');
    BootstrapAdmin(ParamStr(2), ParamStr(3));
    Exit;
  end;
  RunApi;
end.
