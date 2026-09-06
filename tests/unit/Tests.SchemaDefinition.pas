unit Tests.SchemaDefinition;

interface

uses TestFramework;

type
  TSchemaDefinitionTests = class(TTestCase)
  public
    procedure TestEmpresasTableDeclaresRequiredFields;
    procedure TestMonitorTablesDeclareLeaseAndGapState;
    procedure TestSchemaRegistersRenameAndDataActions;
  end;

implementation

uses
  Schema.Definition,
  Tables.Empresas,
  Tables.LacunasMonitoramento,
  Tables.StatusMonitoramento,
  Tables.ConsultasPontuais;

procedure TSchemaDefinitionTests.TestEmpresasTableDeclaresRequiredFields;
var Table: TTableSchema;
begin
  Table := EmpresasTable;
  try
    AssertEquals('empresas', Table.Name);
    AssertEquals(9, Table.Fields.Count);
    AssertEquals('cnpj', Table.Fields[1].Name);
    AssertEquals('state', Table.Fields[2].Name);
  finally Table.Free; end;
end;

procedure TSchemaDefinitionTests.TestMonitorTablesDeclareLeaseAndGapState;
var
  StatusTable: TTableSchema;
  GapTable: TTableSchema;
  QueryTable: TTableSchema;
begin
  StatusTable := StatusMonitoramentoTable;
  GapTable := LacunasMonitoramentoTable;
  QueryTable := ConsultasPontuaisTable;
  try
    AssertEquals('lease_owner', StatusTable.Fields[10].Name);
    AssertEquals('lease_until', StatusTable.Fields[11].Name);
    AssertEquals('lacunas_monitoramento', GapTable.Name);
    AssertEquals('next_nsu', GapTable.Fields[4].Name);
    AssertEquals('consultas_pontuais', QueryTable.Name);
    AssertEquals('monitor_gap_id', QueryTable.Fields[2].Name);
  finally
    QueryTable.Free;
    GapTable.Free;
    StatusTable.Free;
  end;
end;

procedure TSchemaDefinitionTests.TestSchemaRegistersRenameAndDataActions;
var Table: TTableSchema;
begin
  Table := TTableSchema.Create('empresas');
  try
    Table.RenameField('name', 'legal_name');
    Table.RemoveField('legacy_name');
    Table.AddIndex('companies_cnpj_idx', 'cnpj', True);
    Table.AddForeignKey('companies_owner_fk', 'owner_id', 'usuarios', 'id', 'set null');
    Table.ExecuteData('fill-legal-name', 'update empresas set legal_name = name');
    AssertEquals(3, Table.Actions.Count);
    AssertEquals('rename:name:legal_name', Table.Actions[0].Id);
    AssertEquals('remove:legacy_name', Table.Actions[1].Id);
    AssertEquals('fill-legal-name', Table.Actions[2].Id);
    AssertEquals(1, Table.Indexes.Count);
    AssertTrue(Table.Indexes[0].Unique);
    AssertEquals(1, Table.ForeignKeys.Count);
    AssertEquals('set null', Table.ForeignKeys[0].OnDelete);
  finally Table.Free; end;
end;

initialization

TTestHelper.RegisterTest(TSchemaDefinitionTests.Create);

end.
