unit Persistence.MonitorGaps;

interface

uses
  Application.MonitorGaps,
  Application.MonitorCycle,
  System.SysUtils,
  Uni;

type
  EMonitorGapLeaseLost = class(Exception);

  TPostgresMonitorGapRepository = class(TInterfacedObject, IMonitorGapRepository)
  private
    FConnection: TUniConnection;
  public
    constructor Create(const AConnection: TUniConnection);
    function ClaimDue(const AWorkerId: string; const ABatchSize,
      ALeaseSeconds: Integer): TArray<TMonitorGapLease>;
    procedure CompleteLease(const AWorkerId: string; const ALease: TMonitorGapLease;
      const AOutcome: TMonitorGapOutcome; const ADocuments: TArray<TSefazDocument>);
    procedure FailLease(const AWorkerId: string; const ALease: TMonitorGapLease;
      const AMessage: string; const ADelaySeconds: Integer);
  end;

implementation

uses Application.MonitorLeases, Persistence.MonitorCycles;

constructor TPostgresMonitorGapRepository.Create(const AConnection: TUniConnection);
begin
  inherited Create;
  if AConnection = nil then
    raise EArgumentNilException.Create('Conexao PostgreSQL nao informada.');
  FConnection := AConnection;
end;

function TPostgresMonitorGapRepository.ClaimDue(const AWorkerId: string;
  const ABatchSize, ALeaseSeconds: Integer): TArray<TMonitorGapLease>;
var
  Query: TUniQuery;
  Count: Integer;
begin
  ValidateLeaseRequest(AWorkerId, ABatchSize, ALeaseSeconds);
  SetLength(Result, ABatchSize);
  Count := 0;
  Query := TUniQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'with due as ( ' +
      ' select status.company_id, candidate.id from status_monitoramento status ' +
      ' cross join lateral (select work.id from lacunas_monitoramento work ' +
      '   where work.company_id = status.company_id and work.status in (''pending'',''running'') ' +
      '   and (work.next_attempt_at is null or work.next_attempt_at <= now()) ' +
      '   and (work.lease_until is null or work.lease_until <= now())  ' +
      '   order by work.next_attempt_at nulls first, work.created_at, work.id limit 1) candidate ' +
      ' where status.status = ''active'' and status.next_check_at > now() ' +
      ' and coalesce(status.last_cstat,0) <> 656 ' +
      ' and (status.lease_until is null or status.lease_until <= now()) ' +
      ' and exists (select 1 from empresas_modulos module where module.company_id = status.company_id ' +
      '   and module.code = ''monitoring'' and module.status = ''active'') ' +
      ' and exists (select 1 from certificados certificate where certificate.company_id = status.company_id ' +
      '   and certificate.revoked_at is null and certificate.valid_until >= current_date) ' +
      ' and not exists (select 1 from consultas_pontuais point where point.company_id = status.company_id ' +
      '   and point.requested_at > now() - interval ''5 minutes'') ' +
      ' and (select count(*) from consultas_pontuais point where point.company_id = status.company_id ' +
      '   and point.requested_at > now() - interval ''1 hour'') < 15 ' +
      ' order by status.company_id limit :batch_size for update of status skip locked ' +
      '), company_claim as ( ' +
      ' update status_monitoramento status set lease_owner = :worker_id, ' +
      ' lease_until = now() + (:lease_seconds * interval ''1 second'') from due ' +
      ' where status.company_id = due.company_id returning status.company_id ' +
      '), claimed as ( ' +
      ' update lacunas_monitoramento work set status = ''running'', lease_owner = :worker_id, ' +
      ' lease_until = now() + (:lease_seconds * interval ''1 second'') from due, company_claim ' +
      ' where work.id = due.id and work.company_id = company_claim.company_id returning work.* ' +
      '), counted as ( ' +
      ' insert into consultas_pontuais (company_id, monitor_gap_id, origin) ' +
      ' select company_id, id, ''gap'' from claimed returning id ' +
      ') select work.id::text as gap_id, work.company_id::text as company_id, ' +
      ' (select cnpj from empresas where id = work.company_id) as cnpj, work.next_nsu, work.end_nsu ' +
      ' from claimed work';
    Query.ParamByName('batch_size').AsInteger := ABatchSize;
    Query.ParamByName('worker_id').AsString := AWorkerId;
    Query.ParamByName('lease_seconds').AsInteger := ALeaseSeconds;
    Query.Open;
    while not Query.Eof do
    begin
      Result[Count].GapId := Query.FieldByName('gap_id').AsString;
      Result[Count].CompanyId := Query.FieldByName('company_id').AsString;
      Result[Count].Cnpj := Query.FieldByName('cnpj').AsString;
      Result[Count].NextNsu := Query.FieldByName('next_nsu').AsString;
      Result[Count].EndNsu := Query.FieldByName('end_nsu').AsString;
      Inc(Count);
      Query.Next;
    end;
    SetLength(Result, Count);
  finally
    Query.Free;
  end;
end;

procedure TPostgresMonitorGapRepository.CompleteLease(const AWorkerId: string;
  const ALease: TMonitorGapLease; const AOutcome: TMonitorGapOutcome; const ADocuments: TArray<TSefazDocument>);
var
  Query: TUniQuery;
begin
  ValidateLeaseRequest(AWorkerId, 1, 1);
  FConnection.StartTransaction;
  try
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FConnection;
      Query.SQL.Text :=
        'update lacunas_monitoramento set next_nsu = :next_nsu, status = :status, ' +
        'next_attempt_at = now() + (:delay_seconds * interval ''1 second''), ' +
        'attempts = attempts + 1, last_cstat = :cstat, last_message = :message, ' +
        'lease_owner = null, lease_until = null, updated_at = now(), ' +
        'completed_at = case when :status = ''succeeded'' then now() else null end ' +
        'where id = cast(:gap_id as uuid) and lease_owner = :worker_id and lease_until > now()';
      Query.ParamByName('next_nsu').AsString := AOutcome.NextNsu;
      Query.ParamByName('status').AsString := AOutcome.Status;
      Query.ParamByName('delay_seconds').AsInteger := AOutcome.NextAttemptDelaySeconds;
      Query.ParamByName('cstat').AsInteger := AOutcome.CStat;
      Query.ParamByName('message').AsString := AOutcome.MessageText;
      Query.ParamByName('gap_id').AsString := ALease.GapId;
      Query.ParamByName('worker_id').AsString := AWorkerId;
      Query.Execute;
      if Query.RowsAffected <> 1 then
        raise EMonitorGapLeaseLost.Create('Lease da lacuna nao pertence mais ao worker.');
      Query.SQL.Text := 'update status_monitoramento set lease_owner = null, lease_until = null ' +
        'where company_id = cast(:company_id as uuid) and lease_owner = :worker_id and lease_until > now()';
      Query.ParamByName('company_id').AsString := ALease.CompanyId;
      Query.ParamByName('worker_id').AsString := AWorkerId;
      Query.Execute;
      if Query.RowsAffected <> 1 then
        raise EInvalidOpException.Create('Lease compartilhada perdida.');
      if AOutcome.BlocksPrimaryMonitor then
      begin
        Query.SQL.Text :=
          'update status_monitoramento set last_cstat = :cstat, last_message = :message, ' +
          'next_check_at = now() + interval ''3630 seconds'', updated_at = now() ' +
          'where company_id = cast(:company_id as uuid)';
        Query.ParamByName('cstat').AsInteger := AOutcome.CStat;
        Query.ParamByName('message').AsString := AOutcome.MessageText;
        Query.ParamByName('company_id').AsString := ALease.CompanyId;
        Query.Execute;
      end;
    finally
      Query.Free;
    end;
    var Writer := TPostgresMonitorCycleWriter.Create(FConnection);
    try
      Writer.SaveDocuments(ALease.CompanyId, ADocuments);
    finally Writer.Free; end;
    FConnection.Commit;
  except
    FConnection.Rollback;
    raise;
  end;
end;

procedure TPostgresMonitorGapRepository.FailLease(const AWorkerId: string;
  const ALease: TMonitorGapLease; const AMessage: string;
  const ADelaySeconds: Integer);
var
  Query: TUniQuery;
begin
  ValidateLeaseRequest(AWorkerId, 1, 1);
  if ADelaySeconds <= 0 then
    raise EArgumentOutOfRangeException.Create('Backoff tecnico deve ser positivo.');
  Query := TUniQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'update lacunas_monitoramento set status = ''pending'', attempts = attempts + 1, ' +
      'last_message = :message, next_attempt_at = now() + ' +
      '(:delay_seconds * interval ''1 second''), lease_owner = null, lease_until = null, ' +
      'updated_at = now() where id = cast(:gap_id as uuid) and lease_owner = :worker_id ' +
      'and lease_until > now()';
    Query.ParamByName('message').AsString := Copy(AMessage, 1, 1000);
    Query.ParamByName('delay_seconds').AsInteger := ADelaySeconds;
    Query.ParamByName('gap_id').AsString := ALease.GapId;
    Query.ParamByName('worker_id').AsString := AWorkerId;
    Query.Execute;
    if Query.RowsAffected <> 1 then
      raise EMonitorGapLeaseLost.Create('Lease da lacuna nao pertence mais ao worker.');
    Query.SQL.Text := 'update status_monitoramento set lease_owner = null, lease_until = null ' +
      'where company_id = cast(:company_id as uuid) and lease_owner = :worker_id and lease_until > now()';
    Query.ParamByName('company_id').AsString := ALease.CompanyId;
    Query.ParamByName('worker_id').AsString := AWorkerId;
    Query.Execute;
  finally
    Query.Free;
  end;
end;

end.
