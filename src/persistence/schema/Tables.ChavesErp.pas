unit Tables.ChavesErp;

interface

uses Schema.Definition;

function ChavesErpTable: TTableSchema;

implementation

function ChavesErpTable: TTableSchema;
begin
  Result := TTableSchema.Create('chaves_erp');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('organization_id', sftUuid, [sfaNotNull]);
  Result.AddField('label', sftText, [sfaNotNull]);
  Result.AddField('key_hash', sftText, [sfaNotNull, sfaUnique]);
  Result.AddField('scopes', sftJson, [sfaNotNull],
    '''["companies:onboard","modules:write"]''::jsonb');
  Result.AddField('created_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddField('expires_at', sftTimestamp);
  Result.AddField('revoked_at', sftTimestamp);
  Result.AddForeignKey('erp_keys_organization_fk', 'organization_id',
    'organizacoes', 'id', 'cascade');
end;

end.
