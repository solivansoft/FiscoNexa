unit Tables.Comandos;

interface

uses Schema.Definition;

function ComandosTable: TTableSchema;

implementation

function ComandosTable: TTableSchema;
begin
  Result := TTableSchema.Create('comandos');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('company_id', sftUuid, [sfaNotNull]);
  Result.AddField('command_type', sftText, [sfaNotNull]);
  Result.AddField('idempotency_key', sftText, [sfaNotNull]);
  Result.AddField('status', sftText, [sfaNotNull], '''pending''');
  Result.AddField('payload', sftJson, [sfaNotNull], '''{}''::jsonb');
  Result.AddField('attempts', sftInteger, [sfaNotNull], '0');
  Result.AddField('run_after', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddField('claimed_at', sftTimestamp);
  Result.AddField('lease_owner', sftText);
  Result.AddField('lease_until', sftTimestamp);
  Result.AddField('last_cstat', sftInteger);
  Result.AddField('last_message', sftText);
  Result.AddField('completed_at', sftTimestamp);
  Result.AddField('created_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddForeignKey('commands_company_fk', 'company_id', 'empresas', 'id',
    'cascade');
  Result.AddIndex('commands_company_type_idempotency_idx',
    'company_id, command_type, idempotency_key', True);
  Result.AddIndex('commands_pending_idx', 'status, run_after');
  Result.AddIndex('commands_lease_idx', 'lease_until');
  Result.AddCheck('commands_status_check',
    'status in (''pending'', ''running'', ''succeeded'', ''failed'', ''cancelled'')');
  Result.AddCheck('commands_attempts_check', 'attempts >= 0');
end;

end.
