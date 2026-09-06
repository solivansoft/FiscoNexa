unit Persistence.MonitorCommands;

interface

uses
  Application.MonitorCommands,
  Application.MonitorCycle,
  System.SysUtils,
  Uni;

type
  EMonitorCommandLeaseLost = class(Exception);

  TPostgresMonitorCommandRepository = class(TInterfacedObject, IMonitorCommandRepository)
  private
    FConnection: TUniConnection;
  public
    constructor Create(const AConnection: TUniConnection);
    function ClaimDue(const AWorkerId: string; const ABatchSize,
      ALeaseSeconds: Integer): TArray<TMonitorCommandLease>;
    procedure CompleteLease(const AWorkerId: string; const ALease: TMonitorCommandLease;
      const AOutcome: TMonitorCommandOutcome;
      const ADocuments: TArray<TSefazDocument>);
    procedure FailLease(const AWorkerId: string; const ALease: TMonitorCommandLease;
      const AMessage: string; const ADelaySeconds: Integer);
  end;

implementation

uses
  Application.MonitorLeases,
  Persistence.MonitorCycles;

constructor TPostgresMonitorCommandRepository.Create(const AConnection: TUniConnection);
begin
  inherited Create;
  if AConnection = nil then
    raise EArgumentNilException.Create('Conexao PostgreSQL nao informada.');
  FConnection := AConnection;
end;

function TPostgresMonitorCommandRepository.ClaimDue(const AWorkerId: string;
  const ABatchSize, ALeaseSeconds: Integer): TArray<TMonitorCommandLease>;
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
      ' cross join lateral (select work.id from comandos work ' +
      '   where work.company_id = status.company_id and work.status in (''pending'',''running'') ' +
      '   and (work.run_after is null or work.run_after <= now()) ' +
      '   and (work.lease_until is null or work.lease_until <= now()) and work.command_type = ''retrieve_xml'' ' +
      '   order by work.run_after nulls first, work.created_at, work.id limit 1) candidate ' +
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
      ' update comandos work set status = ''running'', lease_owner = :worker_id, ' +
      ' lease_until = now() + (:lease_seconds * interval ''1 second'') from due, company_claim ' +
      ' where work.id = due.id and work.company_id = company_claim.company_id returning work.* ' +
      '), counted as ( ' +
      ' insert into consultas_pontuais (company_id, command_id, origin) ' +
      ' select company_id, id, ''command'' from claimed returning id ' +
      ') select work.id::text as command_id, work.company_id::text as company_id, ' +
      ' (select cnpj from empresas where id = work.company_id) as cnpj, work.payload->>''access_key'' as access_key, work.attempts ' +
      ' from claimed work';
    Query.ParamByName('batch_size').AsInteger := ABatchSize;
    Query.ParamByName('worker_id').AsString := AWorkerId;
    Query.ParamByName('lease_seconds').AsInteger := ALeaseSeconds;
    Query.Open;
    while not Query.Eof do
    begin
      Result[Count].CommandId := Query.FieldByName('command_id').AsString;
      Result[Count].CompanyId := Query.FieldByName('company_id').AsString;
      Result[Count].Cnpj := Query.FieldByName('cnpj').AsString;
      Result[Count].AccessKey := Query.FieldByName('access_key').AsString;
      Result[Count].AttemptCount := Query.FieldByName('attempts').AsInteger;
      Inc(Count);
      Query.Next;
    end;
    SetLength(Result, Count);
  finally
    Query.Free;
  end;
end;

procedure TPostgresMonitorCommandRepository.CompleteLease(const AWorkerId: string;
  const ALease: TMonitorCommandLease; const AOutcome: TMonitorCommandOutcome;
  const ADocuments: TArray<TSefazDocument>);
var
  Query: TUniQuery;
  DocumentWriter: TPostgresMonitorCycleWriter;
begin
  FConnection.StartTransaction;
  try
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FConnection;
      Query.SQL.Text :=
        'update comandos set status = :status, attempts = attempts + 1, ' +
        'run_after = now() + (:delay_seconds * interval ''1 second''), ' +
        'last_cstat = :cstat, last_message = :message, completed_at = ' +
        'case when :status in (''succeeded'', ''failed'', ''cancelled'') then now() else null end, ' +
        'lease_owner = null, lease_until = null where id = cast(:command_id as uuid) ' +
        'and lease_owner = :worker_id and lease_until > now()';
      Query.ParamByName('status').AsString := AOutcome.Status;
      Query.ParamByName('delay_seconds').AsInteger := AOutcome.NextAttemptDelaySeconds;
      Query.ParamByName('cstat').AsInteger := AOutcome.CStat;
      Query.ParamByName('message').AsString := Copy(AOutcome.MessageText, 1, 1000);
      Query.ParamByName('command_id').AsString := ALease.CommandId;
      Query.ParamByName('worker_id').AsString := AWorkerId;
      Query.Execute;
      if Query.RowsAffected <> 1 then
        raise EMonitorCommandLeaseLost.Create('Lease do comando nao pertence mais ao worker.');
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
        Query.ParamByName('message').AsString := Copy(AOutcome.MessageText, 1, 1000);
        Query.ParamByName('company_id').AsString := ALease.CompanyId;
        Query.Execute;
      end;
    finally
      Query.Free;
    end;
    DocumentWriter := TPostgresMonitorCycleWriter.Create(FConnection);
    try
      DocumentWriter.SaveDocuments(ALease.CompanyId, ADocuments);
    finally
      DocumentWriter.Free;
    end;
    FConnection.Commit;
  except
    FConnection.Rollback;
    raise;
  end;
end;

procedure TPostgresMonitorCommandRepository.FailLease(const AWorkerId: string;
  const ALease: TMonitorCommandLease; const AMessage: string;
  const ADelaySeconds: Integer);
var
  Query: TUniQuery;
begin
  Query := TUniQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'update comandos set status = ''pending'', attempts = attempts + 1, ' +
      'last_message = :message, run_after = now() + (:delay_seconds * interval ''1 second''), ' +
      'lease_owner = null, lease_until = null where id = cast(:command_id as uuid) ' +
      'and lease_owner = :worker_id and lease_until > now()';
    Query.ParamByName('message').AsString := Copy(AMessage, 1, 1000);
    Query.ParamByName('delay_seconds').AsInteger := ADelaySeconds;
    Query.ParamByName('command_id').AsString := ALease.CommandId;
    Query.ParamByName('worker_id').AsString := AWorkerId;
    Query.Execute;
    if Query.RowsAffected <> 1 then
      raise EMonitorCommandLeaseLost.Create('Lease do comando nao pertence mais ao worker.');
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
