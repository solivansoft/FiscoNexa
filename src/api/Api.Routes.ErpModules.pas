unit Api.Routes.ErpModules;

interface
procedure RegisterErpModuleRoutes;

implementation

uses
  Application.ErpKeys, System.JSON, System.SysUtils, System.StrUtils, Horse, Operations.ErpModules;

procedure RegisterErpModuleRoutes;
begin
  THorse.Put('/v1/empresas/:id_empresa/modulos/monitoramento',
    procedure(ARequest: THorseRequest; AResponse: THorseResponse; ANext: TProc)
    var Json: TJSONObject; StatusValue: TJSONValue;
    begin
      try
        Json := TJSONObject.ParseJSONValue(ARequest.Body) as TJSONObject;
        try
          if Json = nil then raise EArgumentException.Create('JSON invalido.');
          StatusValue := Json.GetValue('situacao');
          if StatusValue = nil then raise EArgumentException.Create('Situacao obrigatoria.');
          ChangeErpMonitoringModule(ARequest.Headers['Authorization'],
            ARequest.Params['id_empresa'],
            IfThen(StatusValue.Value = 'ativo', 'active',
              IfThen(StatusValue.Value = 'suspenso', 'suspended',
                IfThen(StatusValue.Value = 'cancelado', 'cancelled', StatusValue.Value))));
          AResponse.ContentType('application/json').Status(THTTPStatus.OK).Send('{"situacao":"atualizada"}');
        finally Json.Free; end;
      except
        on E: EErpKeyUnauthorized do AResponse.Status(THTTPStatus.Unauthorized).Send('');
        on E: EArgumentException do AResponse.Status(THTTPStatus.NotFound).Send('');
      end;
    end);
end;
end.
