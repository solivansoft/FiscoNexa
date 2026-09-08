unit Integrations.Asaas;
interface
uses System.JSON;
type TAsaasClient = class
private
  FToken, FBase, FAmbiente: string;
public
  constructor Create;
  function Request(const AMethod, APath: string; const ABody: TJSONObject = nil): TJSONObject;
  property Ambiente: string read FAmbiente;
end;
function AmbienteAsaas: string;
implementation
uses System.SysUtils, System.Classes, System.Net.HttpClient,
  System.Net.URLClient, Application.Assinaturas;
function AmbienteAsaas: string;
begin
  Result := GetEnvironmentVariable('ASAAS_AMBIENTE');
  if (Result<>'sandbox') and (Result<>'producao') then
    raise EAsaasIndisponivel.Create('Ambiente Asaas nao configurado.');
  if (Result='sandbox') and SameText(GetEnvironmentVariable('FISCONEXA_ENVIRONMENT'),'producao') then
    raise EAsaasIndisponivel.Create('Sandbox nao pode conceder assinatura em producao.');
end;
constructor TAsaasClient.Create;
begin
  inherited Create;
  FAmbiente := AmbienteAsaas;
  if FAmbiente='sandbox' then FBase := 'https://api-sandbox.asaas.com/v3'
  else FBase := 'https://api.asaas.com/v3';
  FToken := GetEnvironmentVariable('ASAAS_API_TOKEN');
  if FToken='' then raise EAsaasIndisponivel.Create('Cobranca ainda nao configurada.');
end;
function TAsaasClient.Request(const AMethod, APath: string; const ABody: TJSONObject): TJSONObject;
var C: THTTPClient; S: TStringStream; R: IHTTPResponse; J: TJSONValue;
begin
  Result := nil;
  C := THTTPClient.Create;
  S := nil;
  try
    C.ConnectionTimeout := 5000;
    C.ResponseTimeout := 15000;
    C.HandleRedirects := False;
    C.CustomHeaders['access_token'] := FToken;
    C.CustomHeaders['User-Agent'] := 'FiscoNexa/1.0';
    C.ContentType := 'application/json';
    try
      if AMethod='GET' then R:=C.Get(FBase+APath)
      else if AMethod='DELETE' then R:=C.Delete(FBase+APath)
      else begin
        if ABody=nil then raise EAsaasIndisponivel.Create('Corpo obrigatorio.');
        S := TStringStream.Create(ABody.ToJSON,TEncoding.UTF8);
        R := C.Post(FBase+APath,S);
      end;
    except
      on E: Exception do raise EAsaasIndisponivel.Create('Asaas indisponivel; consulte novamente a cobranca.');
    end;
    if (R.StatusCode=400) or (R.StatusCode=401) or (R.StatusCode=403) or (R.StatusCode=422) then
      raise EAsaasRejeitado.CreateFmt('Asaas recusou a requisicao: HTTP %d.',[R.StatusCode]);
    if (R.StatusCode<200) or (R.StatusCode>=300) then
      raise EAsaasIndisponivel.CreateFmt('Asaas retornou HTTP %d.',[R.StatusCode]);
    J := TJSONObject.ParseJSONValue(R.ContentAsString(TEncoding.UTF8));
    if not (J is TJSONObject) then begin J.Free; raise EAsaasIndisponivel.Create('Resposta Asaas invalida.'); end;
    Result := TJSONObject(J);
  finally S.Free; C.Free; end;
end;
end.
