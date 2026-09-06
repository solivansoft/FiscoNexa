unit Application.ErpMonitoring;

interface

uses
  Data.DB,
  System.SysUtils;

type
  TErpMonitoringStatus = record
    Status: string;
    IntervalMinutes: Integer;
    LastCheckedAt: string;
    NextCheckAt: string;
    LastCStat: Integer;
    CertificateStatus: string;
    CertificateValidUntil: string;
  end;

  EErpMonitoringNotFound = class(Exception);

function GetErpMonitoringStatus(const ACompanyId: string): TErpMonitoringStatus;

implementation

uses
  Database.Connection,
  Uni;

function GetErpMonitoringStatus(const ACompanyId: string): TErpMonitoringStatus;
var
  Connection: TUniConnection;
  Query: TUniQuery;
begin
  Connection := TDatabaseConnection.OpenFromEnvironment;
  try
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := Connection;
      Query.SQL.Text :=
        'select status.status, status.interval_minutes, ' +
        'to_char(status.last_checked_at at time zone ''UTC'', ''YYYY-MM-DD"T"HH24:MI:SS"Z"'') as last_checked_at, ' +
        'to_char(status.next_check_at at time zone ''UTC'', ''YYYY-MM-DD"T"HH24:MI:SS"Z"'') as next_check_at, ' +
        'status.last_cstat, to_char(certificate.valid_until, ''YYYY-MM-DD'') as valid_until, ' +
        'case when certificate.valid_until is null then ''missing'' ' +
        'when certificate.revoked_at is not null then ''revoked'' ' +
        'when certificate.valid_until < current_date then ''expired'' ' +
        'when certificate.valid_until <= current_date + 30 then ''expiring'' else ''valid'' end as certificate_status ' +
        'from status_monitoramento status left join lateral ( ' +
        '  select valid_until, revoked_at from certificados ' +
        '  where company_id = status.company_id ' +
        '  order by (revoked_at is null) desc, created_at desc limit 1 ' +
        ') certificate on true where status.company_id = cast(:company_id as uuid)';
      Query.ParamByName('company_id').AsString := ACompanyId;
      Query.Open;
      if Query.IsEmpty then
        raise EErpMonitoringNotFound.Create('Monitoramento nao encontrado.');
      Result.Status := Query.FieldByName('status').AsString;
      Result.IntervalMinutes := Query.FieldByName('interval_minutes').AsInteger;
      Result.LastCheckedAt := Query.FieldByName('last_checked_at').AsString;
      Result.NextCheckAt := Query.FieldByName('next_check_at').AsString;
      Result.LastCStat := Query.FieldByName('last_cstat').AsInteger;
      Result.CertificateValidUntil := Query.FieldByName('valid_until').AsString;
      Result.CertificateStatus := Query.FieldByName('certificate_status').AsString;
    finally
      Query.Free;
    end;
  finally
    Connection.Free;
  end;
end;

end.
