unit Tables.Organizacoes;

interface

uses Schema.Definition;

function OrganizacoesTable: TTableSchema;

implementation

function OrganizacoesTable: TTableSchema;
begin
  Result := TTableSchema.Create('organizacoes');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('legal_name', sftText, [sfaNotNull]);
  Result.AddField('organization_type', sftText, [sfaNotNull]);
  Result.AddField('created_by_user_id', sftUuid);
  Result.AddField('created_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddForeignKey('organizations_created_by_user_fk', 'created_by_user_id',
    'usuarios', 'id', 'set null');
  Result.AddCheck('organizations_type_check',
    'organization_type in (''accountant'', ''erp'', ''reseller'')');
end;

end.
