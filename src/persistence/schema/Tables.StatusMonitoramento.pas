unit Tables.StatusMonitoramento;

interface

uses Schema.Definition;

function StatusMonitoramentoTable: TTableSchema;

implementation

function StatusMonitoramentoTable: TTableSchema;
begin
  Result := TTableSchema.Create('status_monitoramento');
  Result.AddField('company_id', sftUuid, [sfaPrimaryKey]);
  Result.AddField('status', sftText, [sfaNotNull], '''pending''');
  Result.AddField('interval_minutes', sftInteger, [sfaNotNull], '60');
  Result.AddField('last_checked_at', sftTimestamp);
  Result.AddField('next_check_at', sftTimestamp);
  Result.AddField('last_nsu', sftText);
  Result.AddField('last_cstat', sftInteger);
  Result.AddField('last_message', sftText);
  Result.AddField('blocked_count', sftInteger, [sfaNotNull], '0');
  Result.AddField('failure_count', sftInteger, [sfaNotNull], '0');
  Result.AddField('lease_owner', sftText);
  Result.AddField('lease_until', sftTimestamp);
  Result.AddField('last_error', sftText);
  Result.AddField('updated_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddForeignKey('monitor_status_company_fk', 'company_id', 'empresas',
    'id', 'cascade');
  Result.AddCheck('monitor_status_status_check',
    'status in (''pending'', ''active'', ''attention'', ''inactive'')');
  Result.AddCheck('monitor_status_interval_check', 'interval_minutes > 0');
  Result.AddCheck('monitor_status_blocked_count_check', 'blocked_count >= 0');
  Result.AddCheck('monitor_status_failure_count_check', 'failure_count >= 0');
  Result.AddIndex('monitor_status_due_idx', 'status, next_check_at');
  Result.AddIndex('monitor_status_lease_idx', 'lease_until');
end;

end.
