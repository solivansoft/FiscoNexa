unit Tables.EmpresasOrganizacoes;

interface

uses Schema.Definition;

function EmpresasOrganizacoesTable: TTableSchema;

implementation

function EmpresasOrganizacoesTable: TTableSchema;
begin
  Result := TTableSchema.Create('empresas_organizacoes');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('company_id', sftUuid, [sfaNotNull]);
  Result.AddField('organization_id', sftUuid, [sfaNotNull]);
  Result.AddField('relationship_type', sftText, [sfaNotNull]);
  Result.AddField('access_role', sftText, [sfaNotNull], '''admin''');
  Result.AddField('granted_by_user_id', sftUuid);
  Result.AddField('created_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddField('revoked_at', sftTimestamp);
  Result.AddForeignKey('company_organizations_company_fk', 'company_id',
    'empresas', 'id', 'cascade');
  Result.AddForeignKey('company_organizations_organization_fk', 'organization_id',
    'organizacoes', 'id', 'cascade');
  Result.AddForeignKey('company_organizations_granted_by_user_fk',
    'granted_by_user_id', 'usuarios', 'id', 'set null');
  Result.AddIndex('company_organizations_company_organization_idx',
    'company_id, organization_id', True);
  Result.AddCheck('company_organizations_relationship_check',
    'relationship_type in (''accountant'', ''erp'', ''reseller'')');
  Result.AddCheck('company_organizations_access_role_check',
    'access_role in (''admin'', ''viewer'')');
end;

end.
