program FiscoNexa.ErpSpike;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.SysUtils;

type
  EContratoApi = class(Exception);

function VariavelObrigatoria(const ANome: string): string;
begin
  Result := Trim(GetEnvironmentVariable(ANome));
  if Result = '' then
    raise EContratoApi.Create('Variavel obrigatoria ausente: ' + ANome);
end;

function UrlBase: string;
begin
  Result := Trim(GetEnvironmentVariable('FISCONEXA_API_URL'));
  if Result = '' then
    Result := 'https://api.fisconexa.com.br';
  while Result.EndsWith('/') do
    Delete(Result, Length(Result), 1);
end;

procedure ExigirStatus(const AResposta: IHTTPResponse;
  const AEsperado: Integer; const AOperacao: string);
begin
  if AResposta.StatusCode <> AEsperado then
    raise EContratoApi.CreateFmt('%s retornou HTTP %d: %s',
      [AOperacao, AResposta.StatusCode,
       AResposta.ContentAsString(TEncoding.UTF8)]);
end;

function GetJson(const ACliente: THTTPClient; const ACaminho,
  AToken: string; const AStatusEsperado: Integer = 200): string;
var
  Resposta: IHTTPResponse;
begin
  if AToken <> '' then
    ACliente.CustomHeaders['Authorization'] := 'Bearer ' + AToken
  else
    ACliente.CustomHeaders['Authorization'] := '';
  Resposta := ACliente.Get(UrlBase + ACaminho);
  ExigirStatus(Resposta, AStatusEsperado, 'GET ' + ACaminho);
  Result := Resposta.ContentAsString(TEncoding.UTF8);
end;

procedure ValidarObjetoJson(const ATexto, ACampo, AOperacao: string);
var
  Json: TJSONValue;
begin
  Json := TJSONObject.ParseJSONValue(ATexto);
  try
    if not (Json is TJSONObject) or
      (TJSONObject(Json).GetValue(ACampo) = nil) then
      raise EContratoApi.Create(AOperacao + ' retornou JSON fora do contrato.');
  finally
    Json.Free;
  end;
end;

procedure ExecutarSmoke(const ACliente: THTTPClient);
var
  Token, Resposta: string;
begin
  Token := VariavelObrigatoria('FISCONEXA_ERP_TOKEN');

  Resposta := GetJson(ACliente, '/saude', '');
  ValidarObjetoJson(Resposta, 'situacao', 'Saude');
  Writeln('SAUDE OK ', Resposta);

  Resposta := GetJson(ACliente, '/v1/monitoramento', Token);
  ValidarObjetoJson(Resposta, 'proxima_consulta_em', 'Monitoramento');
  Writeln('MONITORAMENTO OK ', Resposta);

  Resposta := GetJson(ACliente, '/v1/documentos?nsu=0&limite=5', Token);
  ValidarObjetoJson(Resposta, 'itens', 'Documentos');
  Writeln('DOCUMENTOS OK ', Resposta);
end;

procedure ListarDocumentos(const ACliente: THTTPClient);
var
  Token, Nsu, Limite, Resposta: string;
begin
  Token := VariavelObrigatoria('FISCONEXA_ERP_TOKEN');
  if ParamCount >= 2 then Nsu := ParamStr(2) else Nsu := '0';
  if ParamCount >= 3 then Limite := ParamStr(3) else Limite := '100';
  Resposta := GetJson(ACliente, '/v1/documentos?nsu=' + Nsu +
    '&limite=' + Limite, Token);
  ValidarObjetoJson(Resposta, 'itens', 'Documentos');
  Writeln(Resposta);
end;

procedure BaixarXml(const ACliente: THTTPClient);
var
  Token, IdDocumento, Destino, Corpo: string;
  Resposta: IHTTPResponse;
begin
  if ParamCount < 2 then
    raise EContratoApi.Create('Uso: FiscoNexa.ErpSpike.exe xml ID_DOCUMENTO [ARQUIVO.xml]');
  Token := VariavelObrigatoria('FISCONEXA_ERP_TOKEN');
  IdDocumento := ParamStr(2);
  if ParamCount >= 3 then Destino := ParamStr(3)
  else Destino := IdDocumento + '.xml';
  ACliente.CustomHeaders['Authorization'] := 'Bearer ' + Token;
  Resposta := ACliente.Get(UrlBase + '/v1/documentos/' + IdDocumento + '/xml');
  Corpo := Resposta.ContentAsString(TEncoding.UTF8);
  case Resposta.StatusCode of
    200:
      begin
        TFile.WriteAllText(Destino, Corpo, TEncoding.UTF8);
        Writeln('XML salvo em ', TPath.GetFullPath(Destino));
      end;
    202: Writeln('XML pendente: ', Corpo);
    409: Writeln('XML indisponivel: ', Corpo);
  else
    raise EContratoApi.CreateFmt('Download retornou HTTP %d: %s',
      [Resposta.StatusCode, Corpo]);
  end;
end;

procedure MostrarUso;
begin
  Writeln('FiscoNexa.ErpSpike.exe smoke');
  Writeln('FiscoNexa.ErpSpike.exe documentos [nsu] [limite]');
  Writeln('FiscoNexa.ErpSpike.exe xml ID_DOCUMENTO [ARQUIVO.xml]');
end;

var
  Cliente: THTTPClient;
  Comando: string;
begin
  try
    Cliente := THTTPClient.Create;
    try
      Cliente.ConnectionTimeout := 10000;
      Cliente.ResponseTimeout := 30000;
      Cliente.UserAgent := 'FiscoNexa-ErpSpike/1.0';
      if ParamCount = 0 then Comando := 'smoke'
      else Comando := LowerCase(ParamStr(1));
      if Comando = 'smoke' then ExecutarSmoke(Cliente)
      else if Comando = 'documentos' then ListarDocumentos(Cliente)
      else if Comando = 'xml' then BaixarXml(Cliente)
      else begin MostrarUso; ExitCode := 2; end;
    finally
      Cliente.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'ERRO: ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
