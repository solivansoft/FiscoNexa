unit Tables.Documentos;

interface

uses Schema.Definition;

function DocumentosTable: TTableSchema;

implementation

function DocumentosTable: TTableSchema;
begin
  Result := TTableSchema.Create('documentos');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('company_id', sftUuid, [sfaNotNull]);
  Result.AddField('sync_nsu', sftBigInteger);
  Result.AddField('sefaz_nsu', sftText, 15);
  Result.AddField('access_key', sftText, [sfaNotNull]);
  Result.AddField('document_type', sftText, [sfaNotNull]);
  Result.AddField('issued_at', sftTimestamp);
  Result.AddField('issuer_cnpj', sftText, 14);
  Result.AddField('nome_emitente', sftText);
  Result.AddField('tipo_operacao', sftText);
  Result.AddField('situacao_fiscal', sftText);
  Result.AddField('total_amount', sftDecimal);
  Result.AddField('status', sftText, [sfaNotNull]);
  Result.AddField('xml_object_key', sftText);
  Result.AddField('xml_sha256', sftText);
  Result.AddField('created_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddField('updated_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddField('ciencia_cstat', sftInteger);
  Result.AddForeignKey('documents_company_fk', 'company_id', 'empresas', 'id',
    'cascade');
  Result.AddIndex('documents_company_access_key_idx', 'company_id, access_key', True);
  Result.AddIndex('documents_sync_nsu_idx', 'sync_nsu', True);
  Result.AddIndex('documents_company_status_issued_idx',
    'company_id, status, issued_at desc');
  Result.AddCheck('documents_status_check',
    'status in (''located'', ''awareness_registered'', ''manifested'', ''xml_available'', ''cancelled'')');
  Result.ExecuteData('documentos-nsu-sincronizacao-sequence',
    'create sequence if not exists documentos_sync_nsu_seq');
  Result.ExecuteData('documentos-nsu-sincronizacao-default',
    'alter table documentos alter column sync_nsu set default nextval(''documentos_sync_nsu_seq'')');
  Result.ExecuteData('documentos-nsu-sincronizacao-backfill',
    'update documentos set sync_nsu = nextval(''documentos_sync_nsu_seq'') ' +
    'where sync_nsu is null');
end;

end.
