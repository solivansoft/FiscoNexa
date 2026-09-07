unit Persistence.MonitorCycles;

interface

uses
  Application.MonitorCycle,
  Application.MonitorLeases,
  System.SysUtils,
  System.DateUtils,
  FireDAC.Stan.Param, FireDAC.Comp.Client;

type
  EMonitorLeaseLost = class(Exception);

  TPostgresMonitorCycleWriter = class(TInterfacedObject, IMonitorCycleWriter)
  private
    FConnection: TFDConnection;
    procedure SaveGap(const ACompanyId: string; const AOutcome: TMonitorCycleOutcome);
  public
    constructor Create(const AConnection: TFDConnection);
    procedure CompleteLease(const AWorkerId: string; const ALease: TMonitorLease;
      const AOutcome: TMonitorCycleOutcome;
      const ADocuments: TArray<TSefazDocument>);
    procedure FailLease(const AWorkerId: string; const ALease: TMonitorLease;
      const AMessage: string; const ADelaySeconds: Integer);
    procedure SaveDocuments(const ACompanyId: string;
      const ADocuments: TArray<TSefazDocument>);
  end;

implementation

uses
  Persistence.PostgresText;

constructor TPostgresMonitorCycleWriter.Create(const AConnection: TFDConnection);
begin
  inherited Create;
  if AConnection = nil then
    raise EArgumentNilException.Create('Conexao PostgreSQL nao informada.');
  FConnection := AConnection;
end;

procedure TPostgresMonitorCycleWriter.SaveGap(const ACompanyId: string;
  const AOutcome: TMonitorCycleOutcome);
var
  Query: TFDQuery;
begin
  if (AOutcome.GapStartNsu = '') or (AOutcome.GapEndNsu = '') then
    Exit;
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'insert into lacunas_monitoramento (company_id, start_nsu, end_nsu, next_nsu, status, next_attempt_at) ' +
      'values (cast(:company_id as uuid), :start_nsu, :end_nsu, :next_nsu, ''pending'', now()) ' +
      'on conflict (company_id, start_nsu, end_nsu) do nothing';
    Query.ParamByName('company_id').AsString := ACompanyId;
    Query.ParamByName('start_nsu').AsString := AOutcome.GapStartNsu;
    Query.ParamByName('end_nsu').AsString := AOutcome.GapEndNsu;
    Query.ParamByName('next_nsu').AsString := AOutcome.GapStartNsu;
    Query.Execute;
  finally
    Query.Free;
  end;
end;

procedure TPostgresMonitorCycleWriter.SaveDocuments(const ACompanyId: string;
  const ADocuments: TArray<TSefazDocument>);
var
  Query, Command: TFDQuery;
  Document: TSefazDocument;
begin
  if Length(ADocuments) = 0 then Exit;
  if not FConnection.InTransaction then
    raise EInvalidOpException.Create('Documentos exigem transacao do ciclo.');
  Query := TFDQuery.Create(nil);
  Command := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Command.Connection := FConnection;
    // Serializa publicacao por tenant antes de alocar NSU: ordem de commit e cursor.
    Query.SQL.Text := 'select id from empresas where id = cast(:company_id as uuid) for update';
    Query.ParamByName('company_id').AsString := ACompanyId;
    Query.Open;
    if Query.IsEmpty then raise EInvalidOpException.Create('Empresa nao encontrada.');
    Query.Close;
    Query.SQL.Text :=
      'insert into documentos (company_id, sefaz_nsu, access_key, document_type, ' +
      'issued_at, issuer_cnpj, nome_emitente, tipo_operacao, situacao_fiscal, total_amount, status, xml_object_key, xml_sha256, ciencia_cstat) values ' +
      '(cast(:company_id as uuid), :sefaz_nsu, :access_key, ''nfe'', cast(:issued_at as timestamptz), ' +
      ':issuer_cnpj, nullif(:nome_emitente, ''''), nullif(:tipo_operacao, ''''), nullif(:situacao_fiscal, ''''), :total_amount, :status, nullif(:xml_object_key, ''''), nullif(:xml_sha256, ''''), nullif(:ciencia_cstat, 0)) ' +
      'on conflict (company_id, access_key) do update set ' +
      'sync_nsu = nextval(''documentos_sync_nsu_seq''), sefaz_nsu = excluded.sefaz_nsu, ' +
      'issued_at = excluded.issued_at, issuer_cnpj = excluded.issuer_cnpj, ' +
      'nome_emitente = coalesce(excluded.nome_emitente, documentos.nome_emitente), ' +
      'tipo_operacao = coalesce(excluded.tipo_operacao, documentos.tipo_operacao), ' +
      'situacao_fiscal = coalesce(excluded.situacao_fiscal, documentos.situacao_fiscal), ' +
      'total_amount = excluded.total_amount, status = excluded.status, ' +
      'xml_object_key = excluded.xml_object_key, xml_sha256 = excluded.xml_sha256, ' +
      'ciencia_cstat = coalesce(excluded.ciencia_cstat, documentos.ciencia_cstat), updated_at = now() ' +
      'where (documentos.xml_object_key is null or excluded.xml_object_key is not null) ' +
      'and not (documentos.status = ''awareness_registered'' and excluded.status = ''located'') ' +
      'and (documentos.sefaz_nsu, documentos.issued_at, documentos.issuer_cnpj, documentos.nome_emitente, documentos.tipo_operacao, documentos.situacao_fiscal, ' +
      'documentos.total_amount, documentos.status, documentos.xml_object_key, documentos.xml_sha256, documentos.ciencia_cstat) ' +
      'is distinct from (excluded.sefaz_nsu, excluded.issued_at, excluded.issuer_cnpj, coalesce(excluded.nome_emitente, documentos.nome_emitente), coalesce(excluded.tipo_operacao, documentos.tipo_operacao), coalesce(excluded.situacao_fiscal, documentos.situacao_fiscal), ' +
      'excluded.total_amount, excluded.status, excluded.xml_object_key, excluded.xml_sha256, coalesce(excluded.ciencia_cstat, documentos.ciencia_cstat))';
    Command.SQL.Text :=
      'insert into comandos (company_id, command_type, idempotency_key, payload, run_after) ' +
      'values (cast(:company_id as uuid), ''retrieve_xml'', :idempotency_key, ' +
      'jsonb_build_object(''sefaz_nsu'', cast(:sefaz_nsu as text), ''access_key'', cast(:access_key as text)), ' +
      'now() + interval ''5 minutes'') on conflict do nothing';
    for Document in ADocuments do
    begin
      if Trim(Document.AccessKey) = '' then
        raise EInvalidOpException.Create('Documento sem chave de acesso.');
      if Document.IsCompleteXml and ((Document.XmlObjectKey = '') or (Document.XmlSha256 = '')) then
        raise EInvalidOpException.Create('XML completo ainda nao confirmado no storage.');
      Query.ParamByName('company_id').AsString := ACompanyId;
      Query.ParamByName('sefaz_nsu').AsString := Document.SefazNsu;
      Query.ParamByName('access_key').AsString := Document.AccessKey;
      // ISO explicito evita a serializacao invalida de timestamp fracionario do UniDAC.
      Query.ParamByName('issued_at').AsString := DateToISO8601(Document.IssuedAt, False);
      Query.ParamByName('issuer_cnpj').AsString := Document.IssuerCnpj;
      Query.ParamByName('nome_emitente').AsString := Document.IssuerName;
      Query.ParamByName('tipo_operacao').AsString := Document.OperationType;
      Query.ParamByName('situacao_fiscal').AsString := Document.FiscalStatus;
      Query.ParamByName('total_amount').AsCurrency := Document.TotalAmount;
      Query.ParamByName('xml_object_key').AsString := Document.XmlObjectKey;
      Query.ParamByName('xml_sha256').AsString := Document.XmlSha256;
      Query.ParamByName('ciencia_cstat').AsInteger := Document.AwarenessCStat;
      if Document.XmlObjectKey <> '' then
        Query.ParamByName('status').AsString := 'xml_available'
      else if Document.AwarenessAccepted then
        Query.ParamByName('status').AsString := 'awareness_registered'
      else Query.ParamByName('status').AsString := 'located';
      Query.Execute;
      if Document.AwarenessAccepted and (Document.XmlObjectKey = '') and (Document.SefazNsu <> '') then
      begin
        Command.ParamByName('company_id').AsString := ACompanyId;
        Command.ParamByName('idempotency_key').AsString := 'automatic-xml:' + Document.AccessKey;
        Command.ParamByName('sefaz_nsu').AsString := Document.SefazNsu;
        Command.ParamByName('access_key').AsString := Document.AccessKey;
        Command.Execute;
      end;
    end;
    // A distribuicao pode entregar o XML depois de ter criado o comando a
    // partir de um resumo. Fechar somente comandos ainda sem lease evita que
    // o worker refaca uma consulta pontual cujo XML ja esta retido.
    Command.SQL.Text :=
      'update comandos work set status = ''succeeded'', run_after = now(), ' +
      'completed_at = now(), last_message = ''XML ja obtido pelo monitoramento'' ' +
      'where work.company_id = cast(:company_id as uuid) ' +
      'and work.command_type = ''retrieve_xml'' and work.status = ''pending'' ' +
      'and (work.lease_until is null or work.lease_until <= now()) ' +
      'and exists (select 1 from documentos document where document.company_id = work.company_id ' +
      '  and document.access_key = work.payload->>''access_key'' ' +
      '  and document.xml_object_key is not null and document.xml_sha256 is not null)';
    Command.ParamByName('company_id').AsString := ACompanyId;
    Command.Execute;
  finally
    Command.Free;
    Query.Free;
  end;
end;

procedure TPostgresMonitorCycleWriter.CompleteLease(const AWorkerId: string;
  const ALease: TMonitorLease; const AOutcome: TMonitorCycleOutcome;
  const ADocuments: TArray<TSefazDocument>);
var
  Query: TFDQuery;
begin
  ValidateLeaseRequest(AWorkerId, 1, 1);
  FConnection.StartTransaction;
  try
    Query := TFDQuery.Create(nil);
    try
      Query.Connection := FConnection;
      Query.SQL.Text :=
        'update status_monitoramento set last_nsu = :last_nsu, last_cstat = :last_cstat, ' +
        'last_message = :last_message, blocked_count = :blocked_count, ' +
        'failure_count = :failure_count, last_error = null, ' +
        'last_checked_at = now(), next_check_at = now() + ' +
        '(:next_check_delay_seconds * interval ''1 second''), ' +
        'lease_owner = null, lease_until = null, updated_at = now() ' +
        'where company_id = cast(:company_id as uuid) and lease_owner = :worker_id ' +
        'and lease_until > now()';
      Query.ParamByName('last_nsu').AsString := AOutcome.LastNsu;
      Query.ParamByName('last_cstat').AsInteger := AOutcome.LastCStat;
      Query.ParamByName('last_message').AsString := AOutcome.LastMessage;
      Query.ParamByName('blocked_count').AsInteger := AOutcome.BlockedCount;
      Query.ParamByName('failure_count').AsInteger := AOutcome.FailureCount;
      Query.ParamByName('next_check_delay_seconds').AsInteger :=
        AOutcome.NextCheckDelaySeconds;
      Query.ParamByName('company_id').AsString := ALease.CompanyId;
      Query.ParamByName('worker_id').AsString := AWorkerId;
      Query.Execute;
      if Query.RowsAffected <> 1 then
        raise EMonitorLeaseLost.Create('Lease nao pertence mais ao worker.');
    finally
      Query.Free;
    end;
    SaveDocuments(ALease.CompanyId, ADocuments);
    SaveGap(ALease.CompanyId, AOutcome);
    FConnection.Commit;
  except
    FConnection.Rollback;
    raise;
  end;
end;

procedure TPostgresMonitorCycleWriter.FailLease(const AWorkerId: string;
  const ALease: TMonitorLease; const AMessage: string;
  const ADelaySeconds: Integer);
var
  Query: TFDQuery;
begin
  ValidateLeaseRequest(AWorkerId, 1, 1);
  if ADelaySeconds <= 0 then
    raise EArgumentOutOfRangeException.Create('Backoff tecnico deve ser positivo.');
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'update status_monitoramento set failure_count = failure_count + 1, ' +
      'last_error = :last_error, last_message = :last_error, ' +
      'next_check_at = now() + (:delay_seconds * interval ''1 second''), ' +
      'lease_owner = null, lease_until = null, updated_at = now() ' +
      'where company_id = cast(:company_id as uuid) and lease_owner = :worker_id ' +
      'and lease_until > now()';
    Query.ParamByName('last_error').AsString := TextoSeguroPostgres(AMessage);
    Query.ParamByName('delay_seconds').AsInteger := ADelaySeconds;
    Query.ParamByName('company_id').AsString := ALease.CompanyId;
    Query.ParamByName('worker_id').AsString := AWorkerId;
    Query.Execute;
    if Query.RowsAffected <> 1 then
      raise EMonitorLeaseLost.Create('Lease nao pertence mais ao worker.');
  finally
    Query.Free;
  end;
end;

end.
