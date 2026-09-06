unit Tables.Auditorias;

interface

uses Schema.Definition;

function AuditoriasTable: TTableSchema;

implementation

function AuditoriasTable: TTableSchema;
begin
  Result := TTableSchema.Create('auditorias');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('company_id', sftUuid);
  Result.AddField('actor_user_id', sftUuid);
  Result.AddField('event_type', sftText, [sfaNotNull]);
  Result.AddField('payload', sftJson, [sfaNotNull], '''{}''::jsonb');
  Result.AddField('created_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddForeignKey('audit_events_company_fk', 'company_id', 'empresas', 'id',
    'set null');
  Result.AddForeignKey('audit_events_actor_user_fk', 'actor_user_id', 'usuarios',
    'id', 'set null');
  Result.AddIndex('audit_events_company_created_idx', 'company_id, created_at desc');
end;

end.
