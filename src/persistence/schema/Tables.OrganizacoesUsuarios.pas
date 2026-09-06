unit Tables.OrganizacoesUsuarios;

interface

uses Schema.Definition;

function OrganizacoesUsuariosTable: TTableSchema;

implementation

function OrganizacoesUsuariosTable: TTableSchema;
begin
  Result := TTableSchema.Create('organizacoes_usuarios');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('organization_id', sftUuid, [sfaNotNull]);
  Result.AddField('user_id', sftUuid, [sfaNotNull]);
  Result.AddField('role', sftText, [sfaNotNull]);
  Result.AddField('created_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddForeignKey('organization_users_organization_fk', 'organization_id',
    'organizacoes', 'id', 'cascade');
  Result.AddForeignKey('organization_users_user_fk', 'user_id', 'usuarios', 'id',
    'cascade');
  Result.AddIndex('organization_users_organization_user_idx',
    'organization_id, user_id', True);
  Result.AddCheck('organization_users_role_check',
    'role in (''owner'', ''admin'', ''member'')');
end;

end.
