unit Tables.Empresas;

interface

uses Schema.Definition;

function EmpresasTable: TTableSchema;

implementation

function EmpresasTable: TTableSchema;
begin
  Result := TTableSchema.Create('empresas');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('cnpj', sftText, 14, [sfaNotNull, sfaUnique]);
  Result.AddField('state', sftText, 2, [sfaNotNull]);
  Result.AddField('legal_name', sftText, [sfaNotNull]);
  Result.AddField('trade_name', sftText);
  Result.AddField('created_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddField('disabled_at', sftTimestamp);
  Result.AddField('dados_receita', sftJson);
  Result.AddField('receita_consultada_em', sftTimestamp);
end;

end.
