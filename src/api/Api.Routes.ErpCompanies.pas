unit Api.Routes.ErpCompanies;

interface

procedure RegisterErpCompanyRoutes;

implementation

uses
  System.JSON,
  System.NetEncoding,
  Application.CertificateIdentity,
  Application.CompanyOnboarding,
  Application.ErpKeys,
  Horse,
  Operations.CompanyOnboarding;

function ReadString(const AJson: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Value := AJson.GetValue(AName);
  if Value = nil then
    Exit('');
  Result := Value.Value;
end;

function ReadRequest(const ARequest: THorseRequest): TCompanyOnboardingRequest;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.ParseJSONValue(ARequest.Body) as TJSONObject;
  try
    if Json = nil then
      raise ECompanyOnboardingValidation.Create('JSON de onboarding invalido.');
    Result.IdempotencyKey := ARequest.Headers['Idempotency-Key'];
    Result.State := ReadString(Json, 'uf');
    Result.CertificatePfx := TNetEncoding.Base64.DecodeStringToBytes(
      ReadString(Json, 'certificado_a1_base64'));
    Result.CertificatePassword := TNetEncoding.Base64.DecodeStringToBytes(
      ReadString(Json, 'senha_certificado_base64'));
  finally
    Json.Free;
  end;
end;

function ResponseJson(const AResult: TCompanyOnboardingResult): string;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.Create;
  try
    Json.AddPair('id_empresa', AResult.CompanyId);
    Json.AddPair('id_integracao', AResult.IntegrationId);
    Json.AddPair('repetido', TJSONBool.Create(AResult.Replayed));
    Json.AddPair('uf', AResult.State);
    Json.AddPair('razao_social', AResult.LegalName);
    Json.AddPair('nome_fantasia', AResult.TradeName);
    Json.AddPair('cadastro_disponivel', TJSONBool.Create(AResult.RegistryJson <> ''));
    if AResult.RegistryJson <> '' then
      Json.AddPair('dados_cadastrais', TJSONObject.ParseJSONValue(AResult.RegistryJson));
    if AResult.IntegrationToken <> '' then
      Json.AddPair('token_integracao', AResult.IntegrationToken);
    Result := Json.ToJSON;
  finally
    Json.Free;
  end;
end;

procedure RegisterErpCompanyRoutes;
begin
  THorse.Post('/v1/empresas',
    procedure(ARequest: THorseRequest; AResponse: THorseResponse; ANext: TProc)
    var
      RequestData: TCompanyOnboardingRequest;
      ResultData: TCompanyOnboardingResult;
    begin
      try
        RequestData := ReadRequest(ARequest);
        ResultData := ExecuteErpCompanyOnboarding(ARequest.Headers['Authorization'], RequestData);
        AResponse.ContentType('application/json').Send(ResponseJson(ResultData));
        if ResultData.Replayed then
          AResponse.Status(THTTPStatus.OK)
        else
          AResponse.Status(THTTPStatus.Created);
      except
        on E: EErpKeyUnauthorized do
          AResponse.ContentType('application/json').Send(
            '{"erro":{"codigo":"erp_nao_autorizado","mensagem":"Chave do ERP ausente ou sem permissao."}}'
          ).Status(THTTPStatus.Unauthorized);
        on E: ECompanyStateRequired do
          AResponse.ContentType('application/json').Send(
            '{"erro":{"codigo":"uf_obrigatoria","mensagem":"Informe uf: UF indisponivel na consulta cadastral."}}'
          ).Status(THTTPStatus.UnprocessableEntity);
        on E: ECompanyOnboardingValidation do
          AResponse.ContentType('application/json').Send(
            '{"erro":{"codigo":"cadastro_invalido","mensagem":"Dados de cadastro invalidos."}}'
          ).Status(THTTPStatus.UnprocessableEntity);
        on E: ECertificateInvalid do
          AResponse.ContentType('application/json').Send(
            '{"erro":{"codigo":"certificado_invalido","mensagem":"Certificado A1 ou senha invalidos."}}'
          ).Status(THTTPStatus.UnprocessableEntity);
      end;
    end);
end;

end.
