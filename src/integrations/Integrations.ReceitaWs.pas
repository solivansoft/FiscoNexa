unit Integrations.ReceitaWs;

interface

uses Application.CompanyRegistry;

type
  TReceitaWsRegistry = class(TInterfacedObject, ICompanyRegistry)
  public
    function Lookup(const ACnpj: string): TCompanyRegistryData;
  end;

function ParseReceitaWs(const ACnpj, AJson: string): TCompanyRegistryData;

implementation

uses System.SysUtils, System.JSON, System.Net.HttpClient,
  Application.BrazilianStates;

function ParseReceitaWs(const ACnpj, AJson: string): TCompanyRegistryData;
var
  Value: TJSONValue;
  Json: TJSONObject;
  Cnpj: string;
  Ch: Char;
  function Read(const Name: string): string;
  var V: TJSONValue;
  begin
    V := Json.GetValue(Name);
    if V is TJSONString then Result := Trim(V.Value) else Result := '';
  end;
begin
  Result := Default(TCompanyRegistryData);
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Value is TJSONObject) then Exit;
    Json := TJSONObject(Value);
    if not SameText(Read('status'), 'OK') then Exit;
    Cnpj := '';
    for Ch in Read('cnpj') do
      if CharInSet(Ch, ['0'..'9']) then Cnpj := Cnpj + Ch;
    if (Cnpj <> ACnpj) or (Length(Cnpj) <> 14) then Exit;
    Result.State := UpperCase(Read('uf'));
    try BrazilianStateCode(Result.State);
    except on E: EArgumentException do Exit(Default(TCompanyRegistryData)); end;
    Result.LegalName := Read('nome');
    if Result.LegalName = '' then Exit(Default(TCompanyRegistryData));
    Result.TradeName := Read('fantasia');
    Result.Cnpj := Cnpj;
    Result.Json := Json.ToJSON;
    Result.Available := True;
  finally
    Value.Free;
  end;
end;

function TReceitaWsRegistry.Lookup(const ACnpj: string): TCompanyRegistryData;
var
  Client: THTTPClient;
  Response: IHTTPResponse;
  Ch: Char;
begin
  Result := Default(TCompanyRegistryData);
  if Length(ACnpj) <> 14 then Exit;
  for Ch in ACnpj do if not CharInSet(Ch, ['0'..'9']) then Exit;
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := 3000;
    Client.ResponseTimeout := 5000;
    Client.HandleRedirects := False;
    try
      // Consulta unica, sem retry: 429/indisponibilidade nao bloqueiam UF informada.
      Response := Client.Get('https://www.receitaws.com.br/v1/cnpj/' + ACnpj);
      if Response.StatusCode = 200 then
        Result := ParseReceitaWs(ACnpj, Response.ContentAsString(TEncoding.UTF8));
    except
      on E: ENetHTTPClientException do Result := Default(TCompanyRegistryData);
    end;
  finally
    Client.Free;
  end;
end;

end.
