unit Tables.Certificados;

interface

uses Schema.Definition;

function CertificadosTable: TTableSchema;

implementation

function CertificadosTable: TTableSchema;
begin
  Result := TTableSchema.Create('certificados');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('company_id', sftUuid, [sfaNotNull]);
  Result.AddField('uploaded_by_key_id', sftUuid);
  Result.AddField('encryption_key_ref', sftText, [sfaNotNull]);
  Result.AddField('encrypted_data_key', sftBinary, [sfaNotNull]);
  Result.AddField('encrypted_certificate', sftBinary, [sfaNotNull]);
  Result.AddField('certificate_nonce', sftBinary, [sfaNotNull]);
  Result.AddField('certificate_tag', sftBinary, [sfaNotNull]);
  Result.AddField('encrypted_password', sftBinary, [sfaNotNull]);
  Result.AddField('password_nonce', sftBinary, [sfaNotNull]);
  Result.AddField('password_tag', sftBinary, [sfaNotNull]);
  Result.AddField('sha256', sftText, [sfaNotNull, sfaUnique]);
  Result.AddField('subject', sftText);
  Result.AddField('valid_until', sftDate);
  Result.AddField('created_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddField('revoked_at', sftTimestamp);
  Result.AddForeignKey('certificates_company_fk', 'company_id', 'empresas', 'id',
    'cascade');
  Result.AddForeignKey('certificates_uploaded_by_key_fk', 'uploaded_by_key_id',
    'chaves_erp', 'id', 'set null');
end;

end.
