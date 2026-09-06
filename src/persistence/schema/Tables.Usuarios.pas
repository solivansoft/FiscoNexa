unit Tables.Usuarios;

interface

uses Schema.Definition;

function UsuariosTable: TTableSchema;

implementation

function UsuariosTable: TTableSchema;
begin
  Result := TTableSchema.Create('usuarios');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('email', sftText, [sfaNotNull, sfaUnique]);
  Result.AddField('display_name', sftText, [sfaNotNull]);
  Result.AddField('password_hash', sftText, [sfaNotNull]);
  Result.AddField('platform_role', sftText, [sfaNotNull], '''user''');
  Result.AddField('created_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddField('disabled_at', sftTimestamp);
  Result.AddCheck('users_platform_role_check',
    'platform_role in (''user'', ''superadmin'')');
end;

end.
