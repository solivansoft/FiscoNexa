unit Tables.ConfiguracoesMonitoramento;

interface

uses Schema.Definition;

function ConfiguracoesMonitoramentoTable: TTableSchema;

implementation

function ConfiguracoesMonitoramentoTable: TTableSchema;
begin
  Result := TTableSchema.Create('configuracoes_monitoramento');
  Result.AddField('company_id', sftUuid, [sfaPrimaryKey]);
  Result.AddField('auto_register_awareness', sftBoolean,
    [sfaNotNull], 'true');
  Result.AddField('auto_download_after_manifestation', sftBoolean,
    [sfaNotNull], 'true');
  Result.AddField('updated_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddForeignKey('monitor_settings_company_fk', 'company_id', 'empresas',
    'id', 'cascade');
end;

end.
