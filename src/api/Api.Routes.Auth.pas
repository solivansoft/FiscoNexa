unit Api.Routes.Auth;

interface

procedure RegisterAuthRoutes;

implementation

uses
  Application.Authentication,
  Horse,
  Operations.Authentication,
  System.JSON,
  System.SysUtils;

function ReadString(const AJson: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Value := AJson.GetValue(AName);
  if Value = nil then
    Exit('');
  Result := Value.Value;
end;

function SessionJson(const ASession: TAuthSession): string;
var
  Response: TJSONObject;
begin
  Response := TJSONObject.Create;
  try
    Response.AddPair('token_acesso', ASession.AccessToken);
    Response.AddPair('token_renovacao', ASession.RefreshToken);
    Response.AddPair('tipo_token', 'Bearer');
    Response.AddPair('expira_em', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"',
      ASession.ExpiresAt));
    Result := Response.ToJSON;
  finally
    Response.Free;
  end;
end;

procedure RegisterAuthRoutes;
begin
  THorse.Post('/auth/login',
    procedure(ARequest: THorseRequest; AResponse: THorseResponse; ANext: TProc)
    var
      Json: TJSONObject;
      Session: TAuthSession;
    begin
      Json := TJSONObject.ParseJSONValue(ARequest.Body) as TJSONObject;
      try
        if Json = nil then
          raise EAuthenticationInvalid.Create('JSON de login invalido.');
        Session := Login(ReadString(Json, 'email'), ReadString(Json, 'senha'));
        AResponse.ContentType('application/json').Send(SessionJson(Session)).Status(THTTPStatus.OK);
      except
        on E: EAuthenticationUnauthorized do
          AResponse.ContentType('application/json').Send(
            '{"erro":{"codigo":"credenciais_invalidas","mensagem":"Email ou senha invalidos."}}'
          ).Status(THTTPStatus.Unauthorized);
        on E: EAuthenticationInvalid do
          AResponse.ContentType('application/json').Send(
            '{"erro":{"codigo":"login_invalido","mensagem":"Dados de login invalidos."}}'
          ).Status(THTTPStatus.UnprocessableEntity);
      end;
      Json.Free;
    end);

  THorse.Post('/auth/refresh',
    procedure(ARequest: THorseRequest; AResponse: THorseResponse; ANext: TProc)
    var
      Json: TJSONObject;
      Session: TAuthSession;
    begin
      Json := TJSONObject.ParseJSONValue(ARequest.Body) as TJSONObject;
      try
        if Json = nil then
          raise EAuthenticationInvalid.Create('JSON de refresh invalido.');
        Session := Refresh(ReadString(Json, 'token_renovacao'));
        AResponse.ContentType('application/json').Send(SessionJson(Session)).Status(THTTPStatus.OK);
      except
        on E: EAuthenticationUnauthorized do
          AResponse.ContentType('application/json').Send(
            '{"erro":{"codigo":"token_renovacao_invalido","mensagem":"Token de renovacao ausente ou invalido."}}'
          ).Status(THTTPStatus.Unauthorized);
        on E: EAuthenticationInvalid do
          AResponse.ContentType('application/json').Send(
            '{"erro":{"codigo":"renovacao_invalida","mensagem":"Dados de renovacao invalidos."}}'
          ).Status(THTTPStatus.UnprocessableEntity);
      end;
      Json.Free;
    end);

  THorse.Put('/auth/password',
    procedure(ARequest: THorseRequest; AResponse: THorseResponse; ANext: TProc)
    var
      Json: TJSONObject;
    begin
      Json := TJSONObject.ParseJSONValue(ARequest.Body) as TJSONObject;
      try
        if Json = nil then
          raise EAuthenticationInvalid.Create('JSON de senha invalido.');
        ChangePassword(ARequest.Headers['Authorization'], ReadString(Json, 'senha_atual'),
          ReadString(Json, 'nova_senha'));
        AResponse.Status(THTTPStatus.NoContent).Send('');
      except
        on E: EAuthenticationUnauthorized do
          AResponse.ContentType('application/json').Send(
            '{"erro":{"codigo":"senha_nao_autorizada","mensagem":"Sessao ou senha atual invalida."}}'
          ).Status(THTTPStatus.Unauthorized);
        on E: EAuthenticationInvalid do
          AResponse.ContentType('application/json').Send(
            '{"erro":{"codigo":"senha_invalida","mensagem":"Dados de senha invalidos."}}'
          ).Status(THTTPStatus.UnprocessableEntity);
      end;
      Json.Free;
    end);

  THorse.Post('/auth/logout',
    procedure(ARequest: THorseRequest; AResponse: THorseResponse; ANext: TProc)
    begin
      try
        Logout(ARequest.Headers['Authorization']);
        AResponse.Status(THTTPStatus.NoContent).Send('');
      except
        on E: EAuthenticationUnauthorized do
          AResponse.ContentType('application/json').Send(
            '{"erro":{"codigo":"saida_nao_autorizada","mensagem":"Sessao ausente ou invalida."}}'
          ).Status(THTTPStatus.Unauthorized);
      end;
    end);
end;

end.
