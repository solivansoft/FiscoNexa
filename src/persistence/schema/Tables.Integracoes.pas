unit Tables.Integracoes;

interface

uses Schema.Definition;

function IntegracoesTable: TTableSchema;

implementation

function IntegracoesTable: TTableSchema;
begin
  Result := TTableSchema.Create('integracoes');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('company_id', sftUuid, [sfaNotNull]);
  Result.AddField('organization_id', sftUuid);
  Result.AddField('display_name', sftText, [sfaNotNull]);
  Result.AddField('api_token_hash', sftText, [sfaNotNull, sfaUnique]);
  Result.AddField('scopes', sftJson, [sfaNotNull],
    '''["documents:read"]''::jsonb');
  Result.AddField('created_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddField('revoked_at', sftTimestamp);
  Result.AddForeignKey('integrations_company_fk', 'company_id', 'empresas', 'id',
    'cascade');
  Result.AddForeignKey('integrations_organization_fk', 'organization_id',
    'organizacoes', 'id', 'set null');
end;

end.
