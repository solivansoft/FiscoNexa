unit Integration.MonitorPipeline;
interface
uses FireDAC.Stan.Param, FireDAC.Comp.Client;
procedure VerifyMonitorPipeline(const C: TFDConnection; const CompanyId: string);
implementation
uses System.SysUtils, System.DateUtils, System.Hash, Application.MonitorCycle, Application.MonitorGaps,
  Application.MonitorLeases, Application.MonitorCommands, Application.ErpDocuments,
  Persistence.MonitorCycles, Persistence.MonitorGaps, Persistence.MonitorLeases,
  Persistence.MonitorCommands, Integrations.MockSefaz, Worker.Monitoring;
type
  TMemoryStorage = class(TInterfacedObject, IXmlStorage)
  public
    Fail: Boolean;
    function Put(const ACnpj, AKey, AXml: string): TStoredXml;
  end;
function TMemoryStorage.Put(const ACnpj, AKey, AXml: string): TStoredXml;
begin
  if Fail then raise Exception.Create('Falha simulada do storage');
  Result.ObjectKey := ACnpj + '/' + AKey;
  Result.Sha256 := THashSHA2.GetHashString(AXml);
end;
procedure Require(Value: Boolean; const Msg: string);
begin if not Value then raise Exception.Create(Msg); end;
procedure VerifyMonitorPipeline(const C: TFDConnection; const CompanyId: string);
var
  Q: TFDQuery;
  Writer: TPostgresMonitorCycleWriter;
  Docs: TArray<TSefazDocument>;
  Page: TErpDocumentPage;
  Item: TErpDocumentSummary;
  Cursor: Int64;
  XmlAvailable: Boolean;
  R: TDistributionResponse;
  Gateway: IDistributionGateway;
  StorageObject: TMemoryStorage;
  Storage: IXmlStorage;
  GapRepo: IMonitorGapRepository;
  CommandRepo: IMonitorCommandRepository;
  LeaseRepo: IMonitorLeaseRepository;
  GapRecovery: TMonitorGapRecovery;
  Cycle: TMonitorCycle;
  Processor: TMonitorCommandProcessor;
  Worker: TMonitoringWorker;
  Index: Integer;
  procedure ExecuteSql(const Sql: string);
  begin Q.Close; Q.SQL.Text := Sql; Q.Execute; end;
  function Scalar(const Sql: string): string;
  begin Q.Close; Q.SQL.Text := Sql; Q.Open; Result := Q.Fields[0].AsString; Q.Close; end;
  procedure Save;
  begin
    C.StartTransaction;
    try Writer.SaveDocuments(CompanyId,Docs); C.Commit;
    except C.Rollback; raise; end;
  end;
  procedure RunWorker;
  begin
    Gateway := TMockDistributionGateway.Create(R);
    Cycle := TMonitorCycle.Create(Gateway,Writer,Storage);
    try
      GapRecovery := TMonitorGapRecovery.Create(Gateway,GapRepo,Storage);
      try
        Processor := TMonitorCommandProcessor.Create(Gateway as IXmlRetrievalGateway,CommandRepo,Storage);
        try
          Worker := TMonitoringWorker.Create(LeaseRepo,Cycle,GapRepo,GapRecovery,CommandRepo,Processor);
          try Require(Worker.RunOnce('pipeline',1,300) = 1,'Worker nao consumiu a fila esperada');
          finally Worker.Free; end;
        finally Processor.Free; end;
      finally GapRecovery.Free; end;
    finally Cycle.Free; end;
  end;
  procedure AllowPoint;
  begin
    ExecuteSql('update consultas_pontuais set requested_at = now() - interval ''6 minutes''');
    ExecuteSql('update comandos set run_after = now() where company_id = '''+CompanyId+'''');
    ExecuteSql('update lacunas_monitoramento set next_attempt_at = now() where company_id = '''+CompanyId+'''');
  end;
begin
  Q := TFDQuery.Create(nil);
  Writer := TPostgresMonitorCycleWriter.Create(C);
  // Keep the interface alive while cycles also reference this writer.
  var KeepWriter: IMonitorCycleWriter := Writer;
  try
    Q.Connection := C;
    ExecuteSql('delete from lacunas_monitoramento where company_id = '''+CompanyId+'''');
    ExecuteSql('delete from consultas_pontuais where company_id = '''+CompanyId+'''');
    ExecuteSql('update status_monitoramento set last_cstat=137, lease_owner=null, lease_until=null, '+
      'next_check_at=now()+interval ''1 hour'' where company_id='''+CompanyId+'''');
    SetLength(Docs,150);
    for Index := 0 to High(Docs) do
    begin
      Docs[Index].AccessKey := Format('%.44d',[Index+1]);
      Docs[Index].SefazNsu := Format('%.15d',[Index+1]);
      Docs[Index].IssuerCnpj := '12345678000190';
      Docs[Index].IssuerName := 'Emitente de teste';
      Docs[Index].OperationType := 'entrada';
      Docs[Index].FiscalStatus := 'autorizada';
      Docs[Index].IssuedAt := EncodeDateTime(2026,6,5,15,10,9,509);
      Docs[Index].TotalAmount := 10;
    end;
    Save;
    Require(Scalar('select to_char(issued_at at time zone ''UTC'', ''YYYY-MM-DD HH24:MI:SS.MS'') from documentos order by sync_nsu limit 1') =
      FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', TTimeZone.Local.ToUniversalTime(Docs[0].IssuedAt)),
      'Persistencia alterou horario, fuso ou milissegundos da emissao');
    Page := ListErpDocuments(CompanyId,0,500);
    Require(Length(Page.Items)=150,'Paginacao perdeu documentos acima de 100');
    Require((Page.Items[0].IssuerName = 'Emitente de teste') and
      (Page.Items[0].OperationType = 'entrada') and
      (Page.Items[0].FiscalStatus = 'autorizada'),
      'Resumo fiscal do documento nao foi persistido para o ERP');
    for Index := 1 to High(Page.Items) do
      Require(Page.Items[Index].Nsu > Page.Items[Index-1].Nsu,'NSUs fora de ordem');
    Cursor := Page.LastNsu;
    Save;
    Page := ListErpDocuments(CompanyId,Cursor,500);
    Require(Length(Page.Items)=0,'Replay republicou documentos sem alteracao');
    Require(Page.LastNsu=Cursor,'Pagina vazia regrediu cursor');
    Docs[1].AwarenessCStat := 596;
    Docs[2].AwarenessCStat := 655;
    Save;
    Require(Scalar('select count(*) from documentos where ciencia_cstat=596')='1',
      'Rejeicao 596 nao foi preservada por documento');
    Require(Scalar('select count(*) from documentos where ciencia_cstat=655')='1',
      'Rejeicao 655 nao foi preservada por documento');
    Require(Scalar('select count(*) from comandos where command_type=''retrieve_xml''')='0',
      'Rejeicao 596 criou download automatico');
    Page := ListErpDocuments(CompanyId,Cursor,500);
    Require((Length(Page.Items)=2) and (Page.Items[0].AwarenessCStat=596) and
      (Page.Items[1].AwarenessCStat=655), 'ERP perdeu rejeicoes de ciencia');
    Cursor := Page.LastNsu;
    SetLength(Docs,1);
    Docs[0].AwarenessAccepted := True;
    Save;
    Require(Scalar('select count(*) from comandos where command_type=''retrieve_xml'' and status=''pending''')='1','Ciencia nao criou comando');
    Docs[0].IsCompleteXml := True;
    Docs[0].XmlObjectKey := 'xml-ja-retido';
    Docs[0].XmlSha256 := 'hash-ja-retido';
    Save;
    Require(Scalar('select count(*) from comandos where command_type=''retrieve_xml'' and status=''pending''')='0',
      'XML recebido pela distribuicao deixou consulta pontual pendente');
    Require(Scalar('select count(*) from comandos where command_type=''retrieve_xml'' and status=''succeeded''')='1',
      'XML recebido pela distribuicao nao concluiu comando');
    Docs[0].AccessKey := Format('%.44d',[151]);
    Docs[0].SefazNsu := Format('%.15d',[151]);
    Docs[0].IsCompleteXml := False;
    Docs[0].XmlObjectKey := '';
    Docs[0].XmlSha256 := '';
    Docs[0].Xml := '';
    Save;
    Require(Scalar('select count(*) from comandos where command_type=''retrieve_xml'' and status=''pending''')='1',
      'Novo resumo nao criou comando para teste de reconsulta');
    GapRepo := TPostgresMonitorGapRepository.Create(C);
    CommandRepo := TPostgresMonitorCommandRepository.Create(C);
    LeaseRepo := TPostgresMonitorLeaseRepository.Create(C);
    StorageObject := TMemoryStorage.Create; Storage := StorageObject;
    R := Default(TDistributionResponse); R.CStat := 138; R.Documents := Copy(Docs);
    AllowPoint;
    RunWorker;
    Require(Scalar('select status from comandos where command_type=''retrieve_xml'' and payload->>''access_key''='''+
      Docs[0].AccessKey+'''')='pending','Resumo encerrou download');
    Require(Length(CommandRepo.ClaimDue('other',1,300))=0,'Comando ignorou intervalo de consulta');
    R.Documents[0].IsCompleteXml := True; R.Documents[0].Xml := '<nfeProc>teste</nfeProc>';
    AllowPoint; RunWorker;
    Require(Scalar('select status from comandos where command_type=''retrieve_xml'' and payload->>''access_key''='''+
      Docs[0].AccessKey+'''')='succeeded','XML nao concluiu comando');
    Page := ListErpDocuments(CompanyId,Cursor,500);
    XmlAvailable := False;
    for Item in Page.Items do
      if (Item.AccessKey = Docs[0].AccessKey) and Item.XmlAvailable then
        XmlAvailable := True;
    Require(XmlAvailable,'ERP nao recebeu atualizacao do XML');
    Cursor := Page.LastNsu;
    Save; // Old summary cannot erase an already retained XML.
    Page := ListErpDocuments(CompanyId,Cursor,500);
    Require(Length(Page.Items)=0,'Resumo antigo alterou XML retido');
    Require(Scalar('select count(*) from documentos where xml_object_key=''''')='0','Resumo persistiu chave vazia');
    ExecuteSql('insert into lacunas_monitoramento(company_id,start_nsu,end_nsu,next_nsu) '+
      'values('''+CompanyId+''',''200'',''200'',''200'')');
    R.Documents[0].AccessKey := Format('%.44d',[200]); R.Documents[0].SefazNsu := '200';
    R.Documents[0].AwarenessAccepted := False;
    StorageObject.Fail := True;
    AllowPoint; RunWorker;
    Require(Scalar('select next_nsu from lacunas_monitoramento where company_id='''+CompanyId+'''')='200','Falha storage avancou lacuna');
    Require(Scalar('select count(*) from documentos')='151','Falha storage materializou documento');
    Require(Length(GapRepo.ClaimDue('other',1,300))=0,'Falha externa nao foi contada');
    StorageObject.Fail := False;
    AllowPoint; RunWorker;
    Require(Scalar('select status from lacunas_monitoramento where company_id='''+CompanyId+'''')='succeeded','Lacuna nao concluiu');
    Page := ListErpDocuments(CompanyId,Cursor,500);
    Require((Length(Page.Items)=1) and Page.Items[0].XmlAvailable,'Lacuna descartou XML');
    Writeln('Pipeline aprovado: worker, resumo/reconsulta/XML, lacuna com falha, replay e NSU em 150 documentos.');
  finally
    KeepWriter := nil;
    Q.Free;
  end;
end;
end.
