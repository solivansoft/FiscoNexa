unit Tables.EmpresasUsuarios;

interface

uses Schema.Definition;

function EmpresasUsuariosTable: TTableSchema;

implementation

function EmpresasUsuariosTable: TTableSchema;
begin
  Result := TTableSchema.Create('empresas_usuarios');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('company_id', sftUuid, [sfaNotNull]);
  Result.AddField('user_id', sftUuid, [sfaNotNull]);
  Result.AddField('role', sftText, [sfaNotNull]);
  Result.AddField('granted_by_user_id', sftUuid);
  Result.AddField('created_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddField('revoked_at', sftTimestamp);
  Result.AddForeignKey('company_users_company_fk', 'company_id', 'empresas', 'id',
    'cascade');
  Result.AddForeignKey('company_users_user_fk', 'user_id', 'usuarios', 'id', 'cascade');
  Result.AddForeignKey('company_users_granted_by_user_fk', 'granted_by_user_id',
    'usuarios', 'id', 'set null');
  Result.AddIndex('company_users_company_user_idx', 'company_id, user_id', True);
  Result.AddCheck('company_users_role_check',
    'role in (''owner'', ''admin'', ''viewer'')');
end;

end.
