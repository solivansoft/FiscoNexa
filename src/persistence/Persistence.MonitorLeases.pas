unit Persistence.MonitorLeases;

interface

uses
  Application.MonitorLeases,
  Uni;

type
  TPostgresMonitorLeaseRepository = class(TInterfacedObject,
    IMonitorLeaseRepository)
  private
    FConnection: TUniConnection;
  public
    constructor Create(const AConnection: TUniConnection);
    function ClaimDue(const AWorkerId: string; const ABatchSize,
      ALeaseSeconds: Integer): TArray<TMonitorLease>;
  end;

implementation

uses
  System.SysUtils;

constructor TPostgresMonitorLeaseRepository.Create(
  const AConnection: TUniConnection);
begin
  inherited Create;
  if AConnection = nil then
    raise EArgumentNilException.Create('Conexao PostgreSQL nao informada.');
  FConnection := AConnection;
end;

function TPostgresMonitorLeaseRepository.ClaimDue(const AWorkerId: string;
  const ABatchSize, ALeaseSeconds: Integer): TArray<TMonitorLease>;
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
      '  select status.company_id from status_monitoramento status ' +
      '  where status.status = ''active'' ' +
      '    and (status.next_check_at is null or status.next_check_at <= now()) ' +
      '    and (status.lease_until is null or status.lease_until <= now()) ' +
      '    and exists (select 1 from empresas_modulos module ' +
      '      where module.company_id = status.company_id ' +
      '        and module.code = ''monitoring'' and module.status = ''active'') ' +
      '    and exists (select 1 from certificados certificate ' +
      '      where certificate.company_id = status.company_id ' +
      '        and certificate.revoked_at is null ' +
      '        and certificate.valid_until >= current_date) ' +
      '  order by status.next_check_at nulls first, status.company_id ' +
      '  limit :batch_size for update skip locked ' +
      ') ' +
      'update status_monitoramento status set lease_owner = :worker_id, ' +
      '  lease_until = now() + (:lease_seconds * interval ''1 second''), ' +
      '  updated_at = now() ' +
      'from due where status.company_id = due.company_id ' +
      'returning status.company_id::text as company_id, ' +
      '  (select cnpj from empresas where id = status.company_id) as cnpj, ' +
      '  coalesce(nullif(status.last_nsu, ''''), ''000000000000000'') as last_nsu, ' +
      '  coalesce(status.last_cstat, 0) as last_cstat, ' +
      '  status.blocked_count, status.failure_count';
    Query.ParamByName('batch_size').AsInteger := ABatchSize;
    Query.ParamByName('worker_id').AsString := AWorkerId;
    Query.ParamByName('lease_seconds').AsInteger := ALeaseSeconds;
    Query.Open;
    while not Query.Eof do
    begin
      Result[Count].CompanyId := Query.FieldByName('company_id').AsString;
      Result[Count].Cnpj := Query.FieldByName('cnpj').AsString;
      Result[Count].LastNsu := Query.FieldByName('last_nsu').AsString;
      Result[Count].LastCStat := Query.FieldByName('last_cstat').AsInteger;
      Result[Count].BlockedCount := Query.FieldByName('blocked_count').AsInteger;
      Result[Count].FailureCount := Query.FieldByName('failure_count').AsInteger;
      Inc(Count);
      Query.Next;
    end;
    SetLength(Result, Count);
  finally
    Query.Free;
  end;
end;

end.
