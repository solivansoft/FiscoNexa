unit Tables.EmpresasModulos;

interface

uses Schema.Definition;

function EmpresasModulosTable: TTableSchema;

implementation

function EmpresasModulosTable: TTableSchema;
begin
  Result := TTableSchema.Create('empresas_modulos');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('company_id', sftUuid, [sfaNotNull]);
  Result.AddField('organization_id', sftUuid, [sfaNotNull]);
  Result.AddField('code', sftText, [sfaNotNull]);
  Result.AddField('status', sftText, [sfaNotNull]);
  Result.AddField('external_id', sftText);
  Result.AddField('updated_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddForeignKey('company_modules_company_fk', 'company_id', 'empresas',
    'id', 'cascade');
  Result.AddForeignKey('company_modules_organization_fk', 'organization_id',
    'organizacoes', 'id', 'cascade');
  Result.AddIndex('company_modules_company_organization_code_idx',
    'company_id, organization_id, code', True);
  Result.AddCheck('company_modules_status_check',
    'status in (''active'', ''suspended'', ''cancelled'')');
end;

end.
