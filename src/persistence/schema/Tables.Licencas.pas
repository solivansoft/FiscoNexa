unit Tables.Licencas;

interface

uses Schema.Definition;

function LicencasTable: TTableSchema;

implementation

function LicencasTable: TTableSchema;
begin
  Result := TTableSchema.Create('licencas');
  Result.AddField('company_id', sftUuid, [sfaPrimaryKey]);
  Result.AddField('situacao', sftText, [sfaNotNull], '''liberado''');
  Result.AddField('acesso_liberado_ate', sftTimestamp);
  Result.AddField('proteger_monitoramento_ate', sftTimestamp);
  Result.AddField('referencia', sftText, [sfaNotNull]);
  Result.AddField('versao_origem', sftBigInteger, [sfaNotNull]);
  Result.AddField('updated_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddForeignKey('licenses_company_fk', 'company_id', 'empresas',
    'id', 'cascade');
  Result.AddCheck('licenses_status_check',
    'situacao in (''liberado'', ''restrito'')');
  Result.AddCheck('licenses_version_check', 'versao_origem >= 0');
  Result.AddIndex('licenses_protection_idx',
    'situacao, proteger_monitoramento_ate');
end;

end.
