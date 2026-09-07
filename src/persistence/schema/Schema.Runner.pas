unit Schema.Runner;

interface

uses FireDAC.Stan.Param, FireDAC.Comp.Client;

type
  TSchemaRunner = class
  public
    class procedure Apply(const AConnection: TFDConnection); static;
  end;

implementation

uses
  Schema.Definition,
  Schema.Postgres,
  Tables.Auditorias,
  Tables.Licencas,
  Tables.Certificados,
  Tables.Comandos,
  Tables.Empresas,
  Tables.EmpresasModulos,
  Tables.EmpresasOrganizacoes,
  Tables.EmpresasUsuarios,
  Tables.Documentos,
  Tables.ChavesErp,
  Tables.Integracoes,
  Tables.ConfiguracoesMonitoramento,
  Tables.StatusMonitoramento,
  Tables.LacunasMonitoramento,
  Tables.Organizacoes,
  Tables.OrganizacoesUsuarios,
  Tables.ConsultasPontuais,
  Tables.Sessoes,
  Tables.Usuarios;

procedure ApplyTable(const AConnection: TFDConnection;
  const ATable: TTableSchema);
begin
  try
    TPostgresSchema.Apply(AConnection, ATable);
  finally
    ATable.Free;
  end;
end;

class procedure TSchemaRunner.Apply(const AConnection: TFDConnection);
begin
  AConnection.StartTransaction;
  try
    AConnection.ExecSQL('create extension if not exists pgcrypto');
    ApplyTable(AConnection, UsuariosTable);
    ApplyTable(AConnection, SessoesTable);
    ApplyTable(AConnection, OrganizacoesTable);
    ApplyTable(AConnection, OrganizacoesUsuariosTable);
    ApplyTable(AConnection, EmpresasTable);
    ApplyTable(AConnection, EmpresasUsuariosTable);
    ApplyTable(AConnection, EmpresasOrganizacoesTable);
    ApplyTable(AConnection, ChavesErpTable);
    ApplyTable(AConnection, CertificadosTable);
    ApplyTable(AConnection, ConfiguracoesMonitoramentoTable);
    ApplyTable(AConnection, EmpresasModulosTable);
    ApplyTable(AConnection, StatusMonitoramentoTable);
    ApplyTable(AConnection, ComandosTable);
    ApplyTable(AConnection, LacunasMonitoramentoTable);
    ApplyTable(AConnection, ConsultasPontuaisTable);
    ApplyTable(AConnection, IntegracoesTable);
    ApplyTable(AConnection, DocumentosTable);
    ApplyTable(AConnection, AuditoriasTable);
    ApplyTable(AConnection, LicencasTable);
    AConnection.Commit;
  except
    AConnection.Rollback;
    raise;
  end;
end;

end.
