unit Api.Routes.ErpMonitoring;

interface

procedure RegisterErpMonitoringRoutes;

implementation

uses
  System.JSON,
  System.StrUtils,
  Application.ErpIntegration,
  Application.ErpMonitoring,
  Horse;

function MonitoringStatusJson(const AStatus: TErpMonitoringStatus): string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('situacao', IfThen(AStatus.Status = 'active', 'ativo',
      IfThen(AStatus.Status = 'suspended', 'suspenso', 'cancelado')));
    Root.AddPair('intervalo_minutos', TJSONNumber.Create(AStatus.IntervalMinutes));
    Root.AddPair('consultado_em', AStatus.LastCheckedAt);
    Root.AddPair('proxima_consulta_em', AStatus.NextCheckAt);
    Root.AddPair('ultimo_cstat', TJSONNumber.Create(AStatus.LastCStat));
    Root.AddPair('situacao_certificado', IfThen(AStatus.CertificateStatus = 'valid', 'valido',
      IfThen(AStatus.CertificateStatus = 'expiring', 'a_vencer', 'vencido')));
    Root.AddPair('certificado_valido_ate', AStatus.CertificateValidUntil);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

procedure RegisterErpMonitoringRoutes;
begin
  THorse.Get('/v1/monitoramento',
    procedure(ARequest: THorseRequest; AResponse: THorseResponse; ANext: TProc)
    var
      Principal: TErpIntegrationPrincipal;
      Monitoring: TErpMonitoringStatus;
    begin
      try
        Principal := AuthenticateErpToken(ARequest.Headers['Authorization']);
        Monitoring := GetErpMonitoringStatus(Principal.CompanyId);
        AResponse.ContentType('application/json').Send(MonitoringStatusJson(Monitoring));
      except
        on E: EErpIntegrationForbidden do
          AResponse.Status(THTTPStatus.Forbidden).Send('');
        on E: EErpIntegrationUnauthorized do
          AResponse.ContentType('application/json').Send(
            '{"erro":{"codigo":"integracao_nao_autorizada","mensagem":"Token de integracao ausente ou invalido."}}'
          ).Status(THTTPStatus.Unauthorized);
        on E: EErpMonitoringNotFound do
          AResponse.ContentType('application/json').Send(
            '{"erro":{"codigo":"monitoramento_nao_encontrado","mensagem":"Monitoramento nao encontrado."}}'
          ).Status(THTTPStatus.NotFound);
      end;
    end);
end;

end.
