unit Api.Routes.ErpDocuments;

interface

procedure RegisterErpDocumentRoutes;

implementation

uses
  System.JSON,
  System.SysUtils,
  Application.CommercialAccess,
  Application.ErpDocuments,
  Application.ErpIntegration,
  Integrations.AwsS3Xml,
  Operations.CommercialAccess,
  Horse;

function DocumentoNumero(const AChaveAcesso: string): string;
begin
  if Length(AChaveAcesso) = 44 then
    Result := Copy(AChaveAcesso, 26, 9)
  else
    Result := '';
end;

function DocumentoSerie(const AChaveAcesso: string): string;
begin
  if Length(AChaveAcesso) = 44 then
    Result := Copy(AChaveAcesso, 23, 3)
  else
    Result := '';
end;

function DocumentoModelo(const AChaveAcesso: string): string;
begin
  if Length(AChaveAcesso) = 44 then
    Result := Copy(AChaveAcesso, 21, 2)
  else
    Result := '';
end;

function SituacaoProcessamento(const AStatus: string): string;
begin
  if AStatus = 'located' then Exit('localizado');
  if AStatus = 'awareness_registered' then Exit('ciencia_registrada');
  if AStatus = 'manifested' then Exit('manifestado');
  if AStatus = 'xml_available' then Exit('xml_disponivel');
  if AStatus = 'cancelled' then Exit('cancelado');
  Result := 'desconhecida';
end;

function MotivoCienciaRecusada(const ACStat: Integer): string;
begin
  if ACStat = 596 then Exit('prazo_ciencia_encerrado');
  if ACStat = 655 then Exit('manifestacao_final_existente');
  Result := 'ciencia_recusada';
end;

function DocumentListJson(const APage: TErpDocumentPage): string;
var
  Root: TJSONObject;
  Items: TJSONArray;
  Item: TErpDocumentSummary;
  JsonItem: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Items := TJSONArray.Create;
    Root.AddPair('itens', Items);
    for Item in APage.Items do
    begin
      JsonItem := TJSONObject.Create;
      JsonItem.AddPair('nsu', TJSONNumber.Create(Item.Nsu));
      JsonItem.AddPair('id_documento', Item.Id);
      JsonItem.AddPair('chave_acesso', Item.AccessKey);
      JsonItem.AddPair('tipo_documento', Item.DocumentType);
      JsonItem.AddPair('modelo', DocumentoModelo(Item.AccessKey));
      JsonItem.AddPair('serie', DocumentoSerie(Item.AccessKey));
      JsonItem.AddPair('numero', DocumentoNumero(Item.AccessKey));
      JsonItem.AddPair('emitido_em', Item.IssuedAt);
      JsonItem.AddPair('cnpj_emitente', Item.IssuerCnpj);
      JsonItem.AddPair('nome_emitente', Item.IssuerName);
      JsonItem.AddPair('tipo_operacao', Item.OperationType);
      JsonItem.AddPair('situacao_fiscal', Item.FiscalStatus);
      JsonItem.AddPair('valor_total', Item.TotalAmount);
        JsonItem.AddPair('situacao', SituacaoProcessamento(Item.Status));
        if Item.AwarenessCStat <> 0 then
          JsonItem.AddPair('ciencia_cstat', TJSONNumber.Create(Item.AwarenessCStat));
      JsonItem.AddPair('xml_disponivel', TJSONBool.Create(Item.XmlAvailable));
      Items.AddElement(JsonItem);
    end;
    Root.AddPair('ultimo_nsu', TJSONNumber.Create(APage.LastNsu));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

procedure SendErpXml(const ARequest: THorseRequest; const AResponse: THorseResponse);
var
  Principal: TErpIntegrationPrincipal;
  Request: TErpXmlRequest;
  Storage: TAwsS3XmlStorage;
  ProtectedUntil: string;
begin
  try
    Principal := AuthenticateErpToken(ARequest.Headers['Authorization']);
  except
    on E: EErpIntegrationForbidden do
    begin AResponse.Status(THTTPStatus.Forbidden).Send(''); Exit; end;
    on E: EErpIntegrationUnauthorized do
    begin
      AResponse.Status(THTTPStatus.Unauthorized).Send(''); Exit;
    end;
  end;
  try
    RequireCommercialDelivery(Principal.CompanyId, ProtectedUntil);
  except
    on E: ECommercialAccessRestricted do
    begin
      AResponse.ContentType('application/json').Status(402).Send(
        '{"erro":{"codigo":"licenca_restrita","mensagem":"Acesso aos XMLs temporariamente restrito."}}');
      Exit;
    end;
  end;
  Request := RequestErpDocumentXml(Principal.CompanyId, ARequest.Params['id_documento']);
  if not Request.Found then begin AResponse.Status(THTTPStatus.NotFound).Send(''); Exit; end;
  if Request.ObjectKey = '' then
  begin
    if Request.CommandStatus = 'failed' then
    begin
      AResponse.ContentType('application/json').Status(THTTPStatus.Conflict).Send(
        '{"situacao":"indisponivel","motivo":"' +
        MotivoCienciaRecusada(Request.CommandCStat) + '","ciencia_cstat":' +
        IntToStr(Request.CommandCStat) + '}');
      Exit;
    end;
    AResponse.ContentType('application/json').Status(THTTPStatus.Accepted).Send(
      '{"situacao":"pendente","id_comando":"' + Request.CommandId + '"}');
    Exit;
  end;
  Storage := TAwsS3XmlStorage.CreateFromEnvironment;
  try
    AResponse.ContentType('application/xml').Send(Storage.Get(Request.ObjectKey));
  finally Storage.Free; end;
end;

procedure RegisterErpDocumentRoutes;
begin
  THorse.Get('/v1/documentos',
    procedure(ARequest: THorseRequest; AResponse: THorseResponse; ANext: TProc)
    var
      Principal: TErpIntegrationPrincipal;
      Documents: TErpDocumentPage;
      SinceNsu, Limit: Int64;
      ProtectedUntil: string;
    begin
      try
        Principal := AuthenticateErpToken(ARequest.Headers['Authorization']);
      except
        on E: EErpIntegrationForbidden do
        begin
          AResponse.Status(THTTPStatus.Forbidden).Send('');
          Exit;
        end;
        on E: EErpIntegrationUnauthorized do
        begin
          AResponse.ContentType('application/json').Send(
            '{"erro":{"codigo":"integracao_nao_autorizada","mensagem":"Token de integracao ausente ou invalido."}}'
          ).Status(THTTPStatus.Unauthorized);
          Exit;
        end;
      end;

      try
        RequireCommercialDelivery(Principal.CompanyId, ProtectedUntil);
      except
        on E: ECommercialAccessRestricted do
        begin
          AResponse.ContentType('application/json').Status(402).Send(
            '{"erro":{"codigo":"licenca_restrita","mensagem":"Acesso aos documentos temporariamente restrito."}}');
          Exit;
        end;
      end;

      SinceNsu := 0;
      Limit := 100;
      if ((ARequest.Query['nsu'] <> '') and not TryStrToInt64(ARequest.Query['nsu'], SinceNsu)) or
        ((ARequest.Query['limite'] <> '') and not TryStrToInt64(ARequest.Query['limite'], Limit)) or
        (SinceNsu < 0) or (Limit < 1) or (Limit > 500) then
      begin
        AResponse.Status(THTTPStatus.BadRequest).Send(''); Exit;
      end;
      Documents := ListErpDocuments(Principal.CompanyId, SinceNsu, Limit);
      AResponse.ContentType('application/json').Send(DocumentListJson(Documents));
    end);
  THorse.Get('/v1/documentos/:id_documento/xml',
    procedure(ARequest: THorseRequest; AResponse: THorseResponse; ANext: TProc)
    begin
      SendErpXml(ARequest, AResponse);
    end);
end;

end.
