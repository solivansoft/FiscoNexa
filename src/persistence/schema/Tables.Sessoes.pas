unit Tables.Sessoes;

interface

uses Schema.Definition;

function SessoesTable: TTableSchema;

implementation

function SessoesTable: TTableSchema;
begin
  Result := TTableSchema.Create('sessoes');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('user_id', sftUuid, [sfaNotNull]);
  Result.AddField('access_token_hash', sftText, [sfaNotNull, sfaUnique]);
  Result.AddField('refresh_token_hash', sftText, [sfaNotNull, sfaUnique]);
  Result.AddField('access_expires_at', sftTimestamp, [sfaNotNull]);
  Result.AddField('refresh_expires_at', sftTimestamp, [sfaNotNull]);
  Result.AddField('revoked_at', sftTimestamp);
  Result.AddField('created_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddForeignKey('sessions_user_fk', 'user_id', 'usuarios', 'id', 'cascade');
  Result.AddIndex('sessions_access_token_active_idx', 'access_token_hash, access_expires_at');
  Result.AddIndex('sessions_refresh_token_active_idx', 'refresh_token_hash, refresh_expires_at');
end;

end.
