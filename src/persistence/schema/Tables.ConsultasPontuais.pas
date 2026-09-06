unit Tables.ConsultasPontuais;

interface

uses Schema.Definition;

function ConsultasPontuaisTable: TTableSchema;

implementation

function ConsultasPontuaisTable: TTableSchema;
begin
  Result := TTableSchema.Create('consultas_pontuais');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('company_id', sftUuid, [sfaNotNull]);
  Result.AddField('monitor_gap_id', sftUuid);
  Result.AddField('command_id', sftUuid);
  Result.AddField('origin', sftText, [sfaNotNull]);
  Result.AddField('requested_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddField('cstat', sftInteger);
  Result.AddField('message', sftText);
  Result.AddForeignKey('point_queries_company_fk', 'company_id', 'empresas', 'id',
    'cascade');
  Result.AddForeignKey('point_queries_gap_fk', 'monitor_gap_id', 'lacunas_monitoramento',
    'id', 'set null');
  Result.AddForeignKey('point_queries_command_fk', 'command_id', 'comandos', 'id',
    'set null');
  Result.AddIndex('point_queries_company_requested_idx', 'company_id, requested_at');
  Result.AddCheck('point_queries_origin_check',
    'origin in (''gap'', ''command'')');
end;

end.
