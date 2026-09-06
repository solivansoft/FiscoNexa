program FiscoNexa.MonitorLeasesIntegration;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  Integration.MonitorPipeline,
  System.SysUtils,
  System.SyncObjs,
  Uni,
  Application.MonitorLeases in '..\..\src\application\Application.MonitorLeases.pas',
  Application.MonitorCycle in '..\..\src\application\Application.MonitorCycle.pas',
  Application.MonitorGaps in '..\..\src\application\Application.MonitorGaps.pas',
  Database.Connection in '..\..\src\db\Database.Connection.pas',
  Persistence.MonitorCycles in '..\..\src\persistence\Persistence.MonitorCycles.pas',
  Persistence.MonitorGaps in '..\..\src\persistence\Persistence.MonitorGaps.pas',
  Persistence.MonitorLeases in '..\..\src\persistence\Persistence.MonitorLeases.pas';

procedure Require(const ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise EInvalidOpException.Create(AMessage);
end;

type
  TLeaseClaimer = class(TThread)
  private
    FStartGate: TEvent;
    FWorkerId: string;
    FLeases: TArray<TMonitorLease>;
    FFailureMessage: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const AStartGate: TEvent; const AWorkerId: string);
    property FailureMessage: string read FFailureMessage;
    property Leases: TArray<TMonitorLease> read FLeases;
  end;

constructor TLeaseClaimer.Create(const AStartGate: TEvent;
  const AWorkerId: string);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FStartGate := AStartGate;
  FWorkerId := AWorkerId;
end;

procedure TLeaseClaimer.Execute;
var
  Connection: TUniConnection;
  Repository: IMonitorLeaseRepository;
begin
  try
    FStartGate.WaitFor(INFINITE);
    Connection := TDatabaseConnection.OpenFromEnvironment;
    try
      Repository := TPostgresMonitorLeaseRepository.Create(Connection);
      FLeases := Repository.ClaimDue(FWorkerId, 1, 300);
    finally
      Connection.Free;
    end;
  except
    on E: Exception do
      FFailureMessage := E.ClassName + ': ' + E.Message;
  end;
end;

procedure CreateFixture(const AConnection: TUniConnection; out AOrganizationId,
  AFirstCompanyId, ASecondCompanyId: string);
var
  Query: TUniQuery;
  CnpjPrefix: string;
begin
  CnpjPrefix := FormatDateTime('yymmddhhnnss', Now);
  Query := TUniQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text :=
      'insert into organizacoes (legal_name, organization_type) ' +
      'values (:legal_name, ''erp'') returning id::text as id';
    Query.ParamByName('legal_name').AsString := 'Smoke monitor leases';
    Query.Open;
    AOrganizationId := Query.FieldByName('id').AsString;

    Query.Close;
    Query.SQL.Text :=
      'insert into empresas (cnpj, state, legal_name) values (:cnpj, ''PA'', :legal_name) ' +
      'returning id::text as id';
    Query.ParamByName('cnpj').AsString := CnpjPrefix + '01';
    Query.ParamByName('legal_name').AsString := 'Empresa lease um';
    Query.Open;
    AFirstCompanyId := Query.FieldByName('id').AsString;

    Query.Close;
    Query.ParamByName('cnpj').AsString := CnpjPrefix + '02';
    Query.ParamByName('legal_name').AsString := 'Empresa lease dois';
    Query.Open;
    ASecondCompanyId := Query.FieldByName('id').AsString;

    Query.Close;
    Query.SQL.Text :=
      'insert into empresas_modulos (company_id, organization_id, code, status) ' +
      'values (:company_id::uuid, :organization_id::uuid, ''monitoring'', ''active'')';
    Query.ParamByName('organization_id').AsString := AOrganizationId;
    Query.ParamByName('company_id').AsString := AFirstCompanyId;
    Query.Execute;
    Query.ParamByName('company_id').AsString := ASecondCompanyId;
    Query.Execute;

    Query.SQL.Text :=
      'insert into status_monitoramento (company_id, status, next_check_at, last_nsu) ' +
      'values (:company_id::uuid, ''active'', now() - interval ''1 minute'', :last_nsu)';
    Query.ParamByName('company_id').AsString := AFirstCompanyId;
    Query.ParamByName('last_nsu').AsString := '000000000000001';
    Query.Execute;
    Query.ParamByName('company_id').AsString := ASecondCompanyId;
    Query.ParamByName('last_nsu').AsString := '000000000000002';
    Query.Execute;

    Query.SQL.Text :=
      'insert into certificados (company_id, encryption_key_ref, encrypted_data_key, ' +
      'encrypted_certificate, certificate_nonce, certificate_tag, encrypted_password, ' +
      'password_nonce, password_tag, sha256, valid_until) values ' +
      '(cast(:company_id as uuid), ''kms-smoke'', decode(''01'', ''hex''), ' +
      'decode(''02'', ''hex''), decode(''03'', ''hex''), decode(''04'', ''hex''), ' +
      'decode(''05'', ''hex''), decode(''06'', ''hex''), decode(''07'', ''hex''), ' +
      ':sha256, current_date + 30)';
    Query.ParamByName('company_id').AsString := AFirstCompanyId;
    Query.ParamByName('sha256').AsString := 'smoke-cert-' + AFirstCompanyId;
    Query.Execute;
    Query.ParamByName('company_id').AsString := ASecondCompanyId;
    Query.ParamByName('sha256').AsString := 'smoke-cert-' + ASecondCompanyId;
    Query.Execute;
  finally
    Query.Free;
  end;
end;

procedure DeleteFixture(const AConnection: TUniConnection; const AOrganizationId,
  AFirstCompanyId, ASecondCompanyId: string);
var
  Query: TUniQuery;
begin
  Query := TUniQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text := 'delete from empresas where id::text in (:first_id, :second_id)';
    Query.ParamByName('first_id').AsString := AFirstCompanyId;
    Query.ParamByName('second_id').AsString := ASecondCompanyId;
    Query.Execute;
    Query.SQL.Text := 'delete from organizacoes where id::text = :organization_id';
    Query.ParamByName('organization_id').AsString := AOrganizationId;
    Query.Execute;
  finally
    Query.Free;
  end;
end;

var
  FirstConnection: TUniConnection;
  StartGate: TEvent;
  FirstWorker: TLeaseClaimer;
  SecondWorker: TLeaseClaimer;
  CycleWriter: IMonitorCycleWriter;
  Response: TDistributionResponse;
  Outcome: TMonitorCycleOutcome;
  Query: TUniQuery;
  GapRepository: IMonitorGapRepository;
  GapLeases: TArray<TMonitorGapLease>;
  GapResponse: TDistributionResponse;
  GapOutcome: TMonitorGapOutcome;
  RecoveredGapId: string;
  CancelledLeaseRepository: IMonitorLeaseRepository;
  OrganizationId: string;
  FirstCompanyId: string;
  SecondCompanyId: string;
begin
  OrganizationId := '';
  FirstCompanyId := '';
  SecondCompanyId := '';
  StartGate := nil;
  FirstWorker := nil;
  SecondWorker := nil;
  FirstConnection := TDatabaseConnection.OpenFromEnvironment;
  try
    CreateFixture(FirstConnection, OrganizationId, FirstCompanyId, SecondCompanyId);
    StartGate := TEvent.Create(nil, True, False, '');
    FirstWorker := TLeaseClaimer.Create(StartGate, 'worker-one');
    SecondWorker := TLeaseClaimer.Create(StartGate, 'worker-two');
    FirstWorker.Start;
    SecondWorker.Start;
    StartGate.SetEvent;
    FirstWorker.WaitFor;
    SecondWorker.WaitFor;
    Require(FirstWorker.FailureMessage = '', FirstWorker.FailureMessage);
    Require(SecondWorker.FailureMessage = '', SecondWorker.FailureMessage);
    Require(Length(FirstWorker.Leases) = 1, 'Primeiro worker nao recebeu exatamente um CNPJ.');
    Require(Length(SecondWorker.Leases) = 1, 'Segundo worker nao recebeu exatamente um CNPJ.');
    Require(FirstWorker.Leases[0].CompanyId <> SecondWorker.Leases[0].CompanyId,
      'Dois workers receberam o mesmo CNPJ.');
    Require(((FirstWorker.Leases[0].CompanyId = FirstCompanyId) and
      (SecondWorker.Leases[0].CompanyId = SecondCompanyId)) or
      ((FirstWorker.Leases[0].CompanyId = SecondCompanyId) and
      (SecondWorker.Leases[0].CompanyId = FirstCompanyId)),
      'Worker recebeu CNPJ fora do fixture.');
    Response.CStat := 656;
    Response.ReturnedNsu := '000000000000100';
    Response.MaxNsu := '';
    Response.MessageText := 'Consumo indevido simulado';
    Outcome := BuildMonitorCycleOutcome(FirstWorker.Leases[0], Response, Now);
    CycleWriter := TPostgresMonitorCycleWriter.Create(FirstConnection);
    CycleWriter.CompleteLease('worker-one', FirstWorker.Leases[0], Outcome, []);
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FirstConnection;
      Query.SQL.Text :=
        'select status.last_nsu, status.last_cstat, status.lease_owner, ' +
        '(select count(*) from lacunas_monitoramento gap where gap.company_id = status.company_id) as gap_count ' +
        'from status_monitoramento status where status.company_id = cast(:company_id as uuid)';
      Query.ParamByName('company_id').AsString := FirstWorker.Leases[0].CompanyId;
      Query.Open;
      Require(Query.FieldByName('last_nsu').AsString = '000000000000100',
        'Ciclo nao persistiu o cursor retornado.');
      Require(Query.FieldByName('last_cstat').AsInteger = 656,
        'Ciclo nao persistiu cStat 656.');
      Require(Query.FieldByName('lease_owner').IsNull,
        'Ciclo nao liberou a lease.');
      Require(Query.FieldByName('gap_count').AsInteger = 1,
        'Ciclo nao persistiu a lacuna NSU.');
    finally
      Query.Free;
    end;
    GapRepository := TPostgresMonitorGapRepository.Create(FirstConnection);
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FirstConnection;
      Query.SQL.Text :=
        'update status_monitoramento set next_check_at = now() where company_id = cast(:company_id as uuid)';
      Query.ParamByName('company_id').AsString := FirstWorker.Leases[0].CompanyId;
      Query.Execute;
    finally
      Query.Free;
    end;
    GapLeases := GapRepository.ClaimDue('gap-worker', 1, 300);
    Require(Length(GapLeases) = 0,
      'Lacuna concorreu com monitoramento principal vencido.');
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FirstConnection;
      Query.SQL.Text :=
        'update status_monitoramento set last_cstat = 137, next_check_at = now() + interval ''1 hour'' ' +
        'where company_id = cast(:company_id as uuid)';
      Query.ParamByName('company_id').AsString := FirstWorker.Leases[0].CompanyId;
      Query.Execute;
    finally
      Query.Free;
    end;
    GapLeases := GapRepository.ClaimDue('gap-worker', 1, 300);
    Require(Length(GapLeases) = 1, 'Lacuna elegivel nao foi reclamada.');
    RecoveredGapId := GapLeases[0].GapId;
    GapResponse.CStat := 137;
    GapResponse.ReturnedNsu := '';
    GapResponse.MaxNsu := '';
    GapResponse.MessageText := 'Sem documento pontual';
    GapOutcome := BuildMonitorGapOutcome(GapLeases[0], GapResponse);
    GapRepository.CompleteLease('gap-worker', GapLeases[0], GapOutcome, []);
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FirstConnection;
      Query.SQL.Text :=
        'select gap.status, (select count(*) from consultas_pontuais point ' +
        'where point.monitor_gap_id = gap.id) as point_count ' +
        'from lacunas_monitoramento gap where gap.id = cast(:gap_id as uuid)';
      Query.ParamByName('gap_id').AsString := RecoveredGapId;
      Query.Open;
      Require(Query.FieldByName('point_count').AsInteger = 1,
        'Recuperacao nao registrou consulta pontual.');
      Require((Query.FieldByName('status').AsString = 'pending') or
        (Query.FieldByName('status').AsString = 'succeeded'),
        'Recuperacao deixou lacuna em estado invalido.');
    finally
      Query.Free;
    end;
    GapLeases := GapRepository.ClaimDue('gap-worker-two', 1, 300);
    Require(Length(GapLeases) = 0,
      'Lacuna ignorou intervalo minimo entre consultas pontuais.');
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FirstConnection;
      Query.SQL.Text :=
        'update consultas_pontuais set requested_at = now() - interval ''6 minutes'' ' +
        'where monitor_gap_id = cast(:gap_id as uuid)';
      Query.ParamByName('gap_id').AsString := RecoveredGapId;
      Query.Execute;
      Query.SQL.Text :=
        'insert into consultas_pontuais (company_id, monitor_gap_id, origin, requested_at) ' +
        'select cast(:company_id as uuid), cast(:gap_id as uuid), ''gap'', now() - interval ''10 minutes'' ' +
        'from generate_series(1, 14)';
      Query.ParamByName('company_id').AsString := FirstWorker.Leases[0].CompanyId;
      Query.ParamByName('gap_id').AsString := RecoveredGapId;
      Query.Execute;
    finally
      Query.Free;
    end;
    GapLeases := GapRepository.ClaimDue('gap-worker-three', 1, 300);
    Require(Length(GapLeases) = 0,
      'Lacuna ignorou limite de quinze consultas pontuais por hora.');
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FirstConnection;
      Query.SQL.Text :=
        'update empresas_modulos set status = ''cancelled'' ' +
        'where company_id = cast(:company_id as uuid) and code = ''monitoring''';
      Query.ParamByName('company_id').AsString := SecondWorker.Leases[0].CompanyId;
      Query.Execute;
      Query.SQL.Text :=
        'update status_monitoramento set lease_owner = null, lease_until = null, next_check_at = now() ' +
        'where company_id = cast(:company_id as uuid)';
      Query.ParamByName('company_id').AsString := SecondWorker.Leases[0].CompanyId;
      Query.Execute;
    finally
      Query.Free;
    end;
    CancelledLeaseRepository := TPostgresMonitorLeaseRepository.Create(FirstConnection);
    Require(Length(CancelledLeaseRepository.ClaimDue('cancelled-worker', 10, 300)) = 0,
      'Modulo cancelado voltou para a fila de monitoramento.');
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FirstConnection;
      Query.SQL.Text :=
        'update empresas_modulos set status = ''active'' ' +
        'where company_id = cast(:company_id as uuid) and code = ''monitoring''';
      Query.ParamByName('company_id').AsString := SecondWorker.Leases[0].CompanyId;
      Query.Execute;
      Query.SQL.Text :=
        'update certificados set valid_until = current_date - 1 ' +
        'where company_id = cast(:company_id as uuid)';
      Query.ParamByName('company_id').AsString := SecondWorker.Leases[0].CompanyId;
      Query.Execute;
    finally
      Query.Free;
    end;
    Require(Length(CancelledLeaseRepository.ClaimDue('expired-cert-worker', 10, 300)) = 0,
      'Certificado vencido voltou para a fila de monitoramento.');
    VerifyMonitorPipeline(FirstConnection, FirstWorker.Leases[0].CompanyId);
    Writeln('Smoke lease aprovado: concorrencia, ciclo, lacuna, limites, cancelamento e certificado vencido validados.');
  finally
    SecondWorker.Free;
    FirstWorker.Free;
    StartGate.Free;
    if (OrganizationId <> '') and (FirstCompanyId <> '') and (SecondCompanyId <> '') then
      DeleteFixture(FirstConnection, OrganizationId, FirstCompanyId, SecondCompanyId);
    FirstConnection.Free;
  end;
end.
