unit Api.Routes.Licenses;

interface

procedure RegisterLicenseRoutes;

implementation

uses
  Application.CommercialAccess,
  Horse,
  Operations.CommercialAccess,
  System.JSON,
  System.SysUtils;

function ReadString(const AJson: TJSONObject; const AName: string): string;
var V: TJSONValue;
begin
  V := AJson.GetValue(AName);
  if V = nil then Exit('');
  Result := V.Value;
end;

function ReadVersion(const AJson: TJSONObject): Int64;
begin
  if not TryStrToInt64(ReadString(AJson, 'versao'), Result) then
    raise ELicenseValidation.Create('Versao obrigatoria.');
end;

function ResultJson(const AResult: TCommercialAccessResult): string;
var J: TJSONObject;
begin
  J := TJSONObject.Create;
  try
    J.AddPair('situacao', AResult.Status);
    J.AddPair('repetido', TJSONBool.Create(AResult.Replayed));
    J.AddPair('versao', TJSONNumber.Create(AResult.SourceVersion));
    if AResult.AccessGrantedUntil <> '' then
      J.AddPair('acesso_liberado_ate', AResult.AccessGrantedUntil);
    if AResult.MonitoringProtectedUntil <> '' then
      J.AddPair('proteger_monitoramento_ate', AResult.MonitoringProtectedUntil);
    Result := J.ToJSON;
  finally J.Free; end;
end;

procedure RegisterLicenseRoutes;
begin
  THorse.Put('/administracao/licencas/empresas/:id_empresa',
    procedure(ARequest: THorseRequest; AResponse: THorseResponse; ANext: TProc)
    var J: TJSONValue; U: TCommercialAccessUpdate; R: TCommercialAccessResult;
    begin
      J := nil;
      try
      try
        AuthenticateLicenseSystem(ARequest.Headers['Authorization']);
        J := TJSONObject.ParseJSONValue(ARequest.Body);
        if not (J is TJSONObject) then raise ELicenseValidation.Create('JSON invalido.');
        U.CompanyId := ARequest.Params['id_empresa'];
        U.Status := ReadString(TJSONObject(J), 'situacao');
        U.AccessGrantedUntil := ReadString(TJSONObject(J), 'acesso_liberado_ate');
        U.MonitoringProtectedUntil := ReadString(TJSONObject(J), 'proteger_monitoramento_ate');
        U.Reference := ReadString(TJSONObject(J), 'referencia');
        U.SourceVersion := ReadVersion(TJSONObject(J));
        R := UpdateCommercialAccess(ARequest.Headers['Authorization'], U);
        AResponse.ContentType('application/json').Send(ResultJson(R));
      except
        on E: ELicenseUnauthorized do
          AResponse.Status(THTTPStatus.Unauthorized).Send('');
        on E: ELicenseCompanyNotFound do
          AResponse.Status(THTTPStatus.NotFound).Send('');
        on E: ELicenseValidation do
          AResponse.ContentType('application/json').Status(
            THTTPStatus.UnprocessableEntity).Send(
            '{"erro":{"codigo":"licenca_invalida","mensagem":"Atualizacao de licenca invalida."}}');
      end;
      finally J.Free; end;
    end);
end;

end.
