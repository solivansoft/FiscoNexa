unit Api.Routes.AdminErps;

interface

procedure RegisterAdminErpRoutes;

implementation

uses
  Application.Authentication,
  Application.ErpAdministration,
  Horse,
  Operations.ErpAdministration,
  System.JSON,
  System.SysUtils;

function ReadString(const AJson: TJSONObject; const AName: string): string;
var Value: TJSONValue;
begin
  Value := AJson.GetValue(AName);
  if Value = nil then Exit('');
  Result := Value.Value;
end;

function IssueJson(const AIssue: TErpKeyIssue): string;
var Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  try
    Json.AddPair('id_erp', AIssue.ErpId);
    Json.AddPair('id_chave', AIssue.KeyId);
    Json.AddPair('chave_erp', AIssue.Secret);
    Result := Json.ToJSON;
  finally Json.Free; end;
end;

procedure SendAuthenticationError(const AResponse: THorseResponse; const E: Exception);
begin
  if E is EAuthenticationForbidden then
    AResponse.ContentType('application/json').Send('{"erro":{"codigo":"proibido","mensagem":"Superadmin obrigatorio."}}').Status(THTTPStatus.Forbidden)
  else
    AResponse.ContentType('application/json').Send('{"erro":{"codigo":"administracao_nao_autorizada","mensagem":"Sessao ausente ou invalida."}}').Status(THTTPStatus.Unauthorized);
end;

procedure RegisterAdminErpRoutes;
begin
  THorse.Post('/administracao/erps',
    procedure(ARequest: THorseRequest; AResponse: THorseResponse; ANext: TProc)
    var Json: TJSONObject; Issue: TErpKeyIssue;
    begin
      Json := TJSONObject.ParseJSONValue(ARequest.Body) as TJSONObject;
      try
        if Json = nil then raise EErpAdministrationValidation.Create('JSON invalido.');
        Issue := CreateErp(ARequest.Headers['Authorization'], ReadString(Json, 'razao_social'), ReadString(Json, 'rotulo_chave'));
        AResponse.ContentType('application/json').Send(IssueJson(Issue)).Status(THTTPStatus.Created);
      except
        on E: EAuthenticationUnauthorized do SendAuthenticationError(AResponse, E);
        on E: EAuthenticationForbidden do SendAuthenticationError(AResponse, E);
        on E: EErpAdministrationValidation do AResponse.ContentType('application/json').Send('{"erro":{"codigo":"erp_invalido","mensagem":"Dados do ERP invalidos."}}').Status(THTTPStatus.UnprocessableEntity);
      end;
      Json.Free;
    end);

  THorse.Post('/administracao/erps/:id_erp/chaves',
    procedure(ARequest: THorseRequest; AResponse: THorseResponse; ANext: TProc)
    var Json: TJSONObject; Issue: TErpKeyIssue;
    begin
      Json := TJSONObject.ParseJSONValue(ARequest.Body) as TJSONObject;
      try
        if Json = nil then raise EErpAdministrationValidation.Create('JSON invalido.');
        Issue := RotateErpKey(ARequest.Headers['Authorization'], ARequest.Params['id_erp'], ReadString(Json, 'rotulo_chave'));
        AResponse.ContentType('application/json').Send(IssueJson(Issue)).Status(THTTPStatus.Created);
      except
        on E: EAuthenticationUnauthorized do SendAuthenticationError(AResponse, E);
        on E: EAuthenticationForbidden do SendAuthenticationError(AResponse, E);
        on E: EErpNotFound do AResponse.Status(THTTPStatus.NotFound);
        on E: EErpAdministrationValidation do AResponse.Status(THTTPStatus.UnprocessableEntity);
      end;
      Json.Free;
    end);

  THorse.Delete('/administracao/erps/:id_erp/chaves/:id_chave',
    procedure(ARequest: THorseRequest; AResponse: THorseResponse; ANext: TProc)
    begin
      try
        RevokeErpKey(ARequest.Headers['Authorization'], ARequest.Params['id_erp'], ARequest.Params['id_chave']);
        AResponse.Status(THTTPStatus.NoContent).Send('');
      except
        on E: EAuthenticationUnauthorized do SendAuthenticationError(AResponse, E);
        on E: EAuthenticationForbidden do SendAuthenticationError(AResponse, E);
        on E: EErpNotFound do AResponse.Status(THTTPStatus.NotFound);
      end;
    end);
end;

end.
