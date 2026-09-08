unit Api.Routes.Assinaturas;
interface
procedure RegisterSubscriptionRoutes;
implementation
uses System.SysUtils, System.JSON, Horse, FireDAC.Comp.Client,
  Database.Connection, Application.ErpIntegration, Application.Assinaturas,
  Persistence.Assinaturas, Operations.StructuredLogs;
procedure Handle(const Req: THorseRequest; const Res: THorseResponse; const Operation: string);
var C: TFDConnection; S: TAssinaturasService; P: TErpIntegrationPrincipal;
  J: TJSONValue; Payment: TJSONValue; Body: string;
begin
  C:=nil; S:=nil; J:=nil;
  try
    try
      if Operation='webhook' then
        AutenticarWebhook(Req.Headers['asaas-access-token'],GetEnvironmentVariable('ASAAS_WEBHOOK_TOKEN'))
      else P:=AuthenticateErpToken(Req.Headers['Authorization']);
      C:=TDatabaseConnection.OpenFromEnvironment;
      S:=TAssinaturasService.Create(C);
      if Operation='assinatura' then Body:=S.Assinatura(P.CompanyId)
      else if Operation='planos' then Body:=S.Planos
      else if Operation='consultar' then Body:=S.ConsultarCobranca(P.CompanyId,Req.Params['id_cobranca'])
      else if Operation='cancelar' then Body:=S.ConsultarCobranca(P.CompanyId,Req.Params['id_cobranca'],True)
      else begin
        if Length(Req.Body)>131072 then raise EAssinaturaInvalida.Create('Corpo muito grande.');
        J:=TJSONObject.ParseJSONValue(Req.Body);
        if not (J is TJSONObject) then raise EAssinaturaInvalida.Create('JSON invalido.');
        if Operation='criar' then
          Body:=S.CriarCobranca(P.CompanyId,TextoJson(TJSONObject(J),'plano_codigo'),Req.Headers['Idempotency-Key'])
        else begin
          Payment:=TJSONObject(J).GetValue('payment');
          if not (Payment is TJSONObject) then raise EAssinaturaInvalida.Create('Pagamento ausente.');
          S.ReceberWebhook(TextoJson(TJSONObject(J),'id'),TextoJson(TJSONObject(J),'event'),TextoJson(TJSONObject(Payment),'id'));
          Body:='{"recebido":true}';
        end;
      end;
      Res.ContentType('application/json').Send(Body);
    except
      on E: EErpIntegrationUnauthorized do Res.Status(401).Send('');
      on E: EErpIntegrationForbidden do Res.Status(403).Send('');
      on E: EWebhookNaoAutorizado do Res.Status(401).Send('');
      on E: ECobrancaAusente do Res.Status(404).Send('');
      on E: EAssinaturaInvalida do Res.ContentType('application/json').Status(422).Send(
        '{"erro":{"codigo":"assinatura_invalida","mensagem":"Confira o plano, o identificador e a chave de idempotencia."}}');
      on E: ECobrancaConflito do Res.ContentType('application/json').Status(409).Send(
        '{"erro":{"codigo":"cobranca_em_conflito","mensagem":"Consulte a cobranca atual antes de tentar novamente ou trocar o plano."}}');
      on E: EAsaasIndisponivel do begin
        RegistrarLog('erro','api','cobranca_provedor_indisponivel');
        Res.ContentType('application/json').Status(503).Send(
          '{"erro":{"codigo":"cobranca_temporariamente_indisponivel","mensagem":"Tente consultar a cobranca novamente em alguns instantes."}}');
      end;
      on E: Exception do begin
        RegistrarLog('erro','api','assinatura_falha_interna');
        Res.ContentType('application/json').Status(500).Send('{"erro":{"codigo":"assinatura_erro_interno"}}');
      end;
    end;
  finally J.Free; S.Free; C.Free; end;
end;
procedure RegisterSubscriptionRoutes;
begin
  THorse.Get('/v1/assinatura',procedure(R: THorseRequest; S: THorseResponse; N: TProc) begin Handle(R,S,'assinatura'); end);
  THorse.Get('/v1/planos',procedure(R: THorseRequest; S: THorseResponse; N: TProc) begin Handle(R,S,'planos'); end);
  THorse.Post('/v1/cobrancas',procedure(R: THorseRequest; S: THorseResponse; N: TProc) begin Handle(R,S,'criar'); end);
  THorse.Get('/v1/cobrancas/:id_cobranca',procedure(R: THorseRequest; S: THorseResponse; N: TProc) begin Handle(R,S,'consultar'); end);
  THorse.Delete('/v1/cobrancas/:id_cobranca',procedure(R: THorseRequest; S: THorseResponse; N: TProc) begin Handle(R,S,'cancelar'); end);
  THorse.Post('/webhooks/asaas',procedure(R: THorseRequest; S: THorseResponse; N: TProc) begin Handle(R,S,'webhook'); end);
end;
end.
