unit Tables.LacunasMonitoramento;

interface

uses Schema.Definition;

function LacunasMonitoramentoTable: TTableSchema;

implementation

function LacunasMonitoramentoTable: TTableSchema;
begin
  Result := TTableSchema.Create('lacunas_monitoramento');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('company_id', sftUuid, [sfaNotNull]);
  Result.AddField('start_nsu', sftText, [sfaNotNull]);
  Result.AddField('end_nsu', sftText, [sfaNotNull]);
  Result.AddField('next_nsu', sftText, [sfaNotNull]);
  Result.AddField('status', sftText, [sfaNotNull], '''pending''');
  Result.AddField('next_attempt_at', sftTimestamp);
  Result.AddField('attempts', sftInteger, [sfaNotNull], '0');
  Result.AddField('recovered_count', sftInteger, [sfaNotNull], '0');
  Result.AddField('last_cstat', sftInteger);
  Result.AddField('last_message', sftText);
  Result.AddField('lease_owner', sftText);
  Result.AddField('lease_until', sftTimestamp);
  Result.AddField('created_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddField('updated_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddField('completed_at', sftTimestamp);
  Result.AddForeignKey('monitor_gaps_company_fk', 'company_id', 'empresas', 'id',
    'cascade');
  Result.AddIndex('monitor_gaps_company_range_idx', 'company_id, start_nsu, end_nsu', True);
  Result.AddIndex('monitor_gaps_due_idx', 'status, next_attempt_at');
  Result.AddCheck('monitor_gaps_status_check',
    'status in (''pending'', ''running'', ''succeeded'', ''failed'')');
  Result.AddCheck('monitor_gaps_attempts_check', 'attempts >= 0');
  Result.AddCheck('monitor_gaps_recovered_count_check', 'recovered_count >= 0');
end;

end.
