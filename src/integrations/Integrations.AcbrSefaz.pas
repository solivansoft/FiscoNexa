unit Integrations.AcbrSefaz;

interface

uses
  ACBrNFe,
  Application.CertificateMaterial,
  Application.MonitorCycle;

type
  TAcbrSefazDistributionGateway = class(TInterfacedObject, IDistributionGateway, IXmlRetrievalGateway)
  private
    FCertificateProvider: IActiveCertificateProvider;
    FAutoRegisterAwareness: Boolean;
    function RegisterAwareness(const ANFe: TACBrNFe; const ACertificate: TActiveCertificateMaterial;
      const AAccessKey: string): Integer;
    function ReadResponse(const ANFe: TACBrNFe;
      const ACertificate: TActiveCertificateMaterial): TDistributionResponse;
    function Query(const ACompanyId, AUltNsu, ANsu, AAccessKey: string): TDistributionResponse;
  public
    function QueryDocument(const ACompanyId, AAccessKey: string): TDistributionResponse;
    constructor Create(const ACertificateProvider: IActiveCertificateProvider;
      const AAutoRegisterAwareness: Boolean = True);
    function QueryDistribution(const ACompanyId, ALastNsu: string): TDistributionResponse;
    function QueryDistributionByNsu(const ACompanyId, ANsu: string): TDistributionResponse;
  end;

implementation

uses
  ACBrDFe.Conversao,
  ACBrDFeComum.RetDistDFeInt,
  ACBrDFeSSL,
  Application.BrazilianStates,
  Application.SefazMonitoringPolicy,
  Integrations.OpenSslCertificate,
  System.SysUtils;

const
  MinimumTimeoutMilliseconds = 60000;

function SchemaDirectory: string;
begin
  Result := IncludeTrailingPathDelimiter(
    IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'Schemas');
  if not DirectoryExists(Result) then
    raise EInvalidOpException.Create('Schemas ACBr ausentes em: ' + Result);
end;

function BytesToAnsiString(const AValue: TBytes): AnsiString;
begin
  if Length(AValue) = 0 then
    Exit('');
  SetString(Result, PAnsiChar(@AValue[0]), Length(AValue));
end;

constructor TAcbrSefazDistributionGateway.Create(
  const ACertificateProvider: IActiveCertificateProvider;
  const AAutoRegisterAwareness: Boolean);
begin
  inherited Create;
  if ACertificateProvider = nil then
    raise EArgumentNilException.Create('Provedor de certificado nao informado.');
  FCertificateProvider := ACertificateProvider;
  FAutoRegisterAwareness := AAutoRegisterAwareness;
end;

function TAcbrSefazDistributionGateway.RegisterAwareness(const ANFe: TACBrNFe;
  const ACertificate: TActiveCertificateMaterial; const AAccessKey: string): Integer;
var
  EventIndex: Integer;
  CStat: Integer;
begin
  ANFe.EventoNFe.Evento.Clear;
  ANFe.EventoNFe.Evento.New;
  EventIndex := ANFe.EventoNFe.Evento.Count - 1;
  ANFe.EventoNFe.Evento.Items[EventIndex].infEvento.chNFe := AAccessKey;
  ANFe.EventoNFe.Evento.Items[EventIndex].infEvento.CNPJ := ACertificate.Cnpj;
  ANFe.EventoNFe.Evento.Items[EventIndex].infEvento.dhEvento := Now;
  ANFe.EventoNFe.Evento.Items[EventIndex].infEvento.cOrgao := 91;
  ANFe.EventoNFe.Evento.Items[EventIndex].infEvento.tpEvento := teManifDestCiencia;
  ANFe.EnviarEvento(0);
  if ANFe.WebServices.EnvEvento.EventoRetorno.retEvento.Count = 0 then
    raise EInvalidOpException.Create('SEFAZ nao retornou a ciencia da operacao.');
  CStat := ANFe.WebServices.EnvEvento.EventoRetorno.retEvento.Items[0].RetInfEvento.CStat;
  if (CStat <> 135) and (CStat <> 136) and (CStat <> 573) and
    (CStat <> 596) and (CStat <> 655) then
    raise EInvalidOpException.Create('SEFAZ recusou a ciencia. cStat=' + CStat.ToString);
  Result := CStat;
end;

function TAcbrSefazDistributionGateway.ReadResponse(const ANFe: TACBrNFe;
  const ACertificate: TActiveCertificateMaterial): TDistributionResponse;
var
  Retorno: TRetDistDFeInt;
  Document: TdocZipCollectionItem;
  DocumentCount: Integer;
  Index: Integer;
  AwarenessCStat: Integer;
begin
  Retorno := ANFe.WebServices.DistribuicaoDFe.RetDistDFeInt;
  if not Assigned(Retorno) then
    raise EInvalidOpException.Create('SEFAZ nao retornou RetDistDFeInt.');
  Result.CStat := Retorno.CStat;
  Result.ReturnedNsu := Retorno.UltNSU;
  Result.MaxNsu := Retorno.maxNSU;
  Result.MessageText := Retorno.xMotivo;
  SetLength(Result.Documents, Retorno.docZip.Count);
  DocumentCount := 0;
  for Index := 0 to Retorno.docZip.Count - 1 do
  begin
    Document := Retorno.docZip.Items[Index];
    if not (Document.schema in [schresNFe, schprocNFe]) then
      Continue;
    if Trim(Document.resDFe.chDFe) = '' then
      Continue;
    Result.Documents[DocumentCount].SefazNsu := Document.NSU;
    Result.Documents[DocumentCount].AccessKey := Document.resDFe.chDFe;
    Result.Documents[DocumentCount].IssuedAt := Document.resDFe.dhEmi;
    Result.Documents[DocumentCount].IssuerCnpj := Document.resDFe.CNPJCPF;
    Result.Documents[DocumentCount].IssuerName := Document.resDFe.xNome;
    case Document.resDFe.tpNF of
      tnEntrada: Result.Documents[DocumentCount].OperationType := 'entrada';
      tnSaida: Result.Documents[DocumentCount].OperationType := 'saida';
    end;
    case Document.resDFe.cSitDFe of
      snAutorizado: Result.Documents[DocumentCount].FiscalStatus := 'autorizada';
      snDenegado: Result.Documents[DocumentCount].FiscalStatus := 'denegada';
      snCancelado: Result.Documents[DocumentCount].FiscalStatus := 'cancelada';
      snEncerrado: Result.Documents[DocumentCount].FiscalStatus := 'encerrada';
    end;
    Result.Documents[DocumentCount].TotalAmount := Document.resDFe.vNF;
    Result.Documents[DocumentCount].IsCompleteXml := Document.schema = schprocNFe;
    Result.Documents[DocumentCount].Xml := Document.XML;
    if FAutoRegisterAwareness and not Result.Documents[DocumentCount].IsCompleteXml then
    begin
      AwarenessCStat := RegisterAwareness(ANFe, ACertificate, Result.Documents[DocumentCount].AccessKey);
      Result.Documents[DocumentCount].AwarenessCStat := AwarenessCStat;
      Result.Documents[DocumentCount].AwarenessAccepted :=
        (AwarenessCStat = 135) or (AwarenessCStat = 136) or (AwarenessCStat = 573);
    end;
    Inc(DocumentCount);
  end;
  SetLength(Result.Documents, DocumentCount);
end;

function TAcbrSefazDistributionGateway.Query(const ACompanyId, AUltNsu,
  ANsu, AAccessKey: string): TDistributionResponse;
var
  Certificate: TActiveCertificateMaterial;
  NFe: TACBrNFe;
  Retorno: TRetDistDFeInt;
  ErrorDetail: string;
begin
  Certificate := FCertificateProvider.LoadActive(ACompanyId);
  try
    EnsureOpenSslProviders;
    NFe := TACBrNFe.Create(nil);
    try
      NFe.Configuracoes.Certificados.DadosPFX := BytesToAnsiString(Certificate.Pfx);
      NFe.Configuracoes.Certificados.Senha := BytesToAnsiString(Certificate.Password);
      NFe.Configuracoes.Certificados.VerificarValidade := True;
      NFe.Configuracoes.WebServices.Ambiente := TACBrTipoAmbiente.taProducao;
      NFe.Configuracoes.WebServices.UF := Certificate.State;
      NFe.Configuracoes.WebServices.Visualizar := False;
      NFe.Configuracoes.WebServices.Salvar := False;
      NFe.Configuracoes.Geral.Salvar := False;
      NFe.Configuracoes.Arquivos.Salvar := False;
      NFe.Configuracoes.WebServices.TimeOut := MinimumTimeoutMilliseconds;
      NFe.Configuracoes.Arquivos.PathSchemas := SchemaDirectory;
      NFe.Configuracoes.Geral.SSLCryptLib := cryOpenSSL;
      NFe.Configuracoes.Geral.SSLHttpLib := httpOpenSSL;
      NFe.Configuracoes.Geral.SSLLib := libOpenSSL;
      NFe.Configuracoes.Geral.SSLXmlSignLib := xsLibXml2;

      try
        if AAccessKey <> '' then
          NFe.DistribuicaoDFePorChaveNFe(BrazilianStateCode(Certificate.State), Certificate.Cnpj, AAccessKey)
        else if ANsu <> '' then
          NFe.DistribuicaoDFePorNSU(BrazilianStateCode(Certificate.State),
            Certificate.Cnpj, NormalizeNsu(ANsu))
        else
          NFe.DistribuicaoDFePorUltNSU(BrazilianStateCode(Certificate.State), Certificate.Cnpj,
            NormalizeNsu(AUltNsu));
      except
        on E: Exception do
        begin
          Retorno := NFe.WebServices.DistribuicaoDFe.RetDistDFeInt;
          if (not Assigned(Retorno)) or (Retorno.CStat = 0) then
          begin
            ErrorDetail := Trim(E.Message);
            if ErrorDetail = '' then
              ErrorDetail := E.ClassName
            else
              ErrorDetail := E.ClassName + ': ' + ErrorDetail;
            raise EInvalidOpException.Create(
              'Falha tecnica na consulta de distribuicao ACBr: ' + ErrorDetail);
          end;
        end;
      end;
      Result := ReadResponse(NFe, Certificate);
    finally
      NFe.Free;
    end;
  finally
    ClearActiveCertificateMaterial(Certificate);
  end;
end;

function TAcbrSefazDistributionGateway.QueryDistribution(const ACompanyId,
  ALastNsu: string): TDistributionResponse;
begin
  Result := Query(ACompanyId, ALastNsu, '', '');
end;

function TAcbrSefazDistributionGateway.QueryDistributionByNsu(
  const ACompanyId, ANsu: string): TDistributionResponse;
begin
  Result := Query(ACompanyId, '', ANsu, '');
end;

function TAcbrSefazDistributionGateway.QueryDocument(const ACompanyId, AAccessKey: string): TDistributionResponse;
begin
  Result := Query(ACompanyId, '', '', AAccessKey);
end;

end.
