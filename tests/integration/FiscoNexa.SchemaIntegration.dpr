program FiscoNexa.SchemaIntegration;
{$APPTYPE CONSOLE}
uses System.SysUtils, Uni, Database.Connection, Schema.Runner, Schema.Postgres,
  Schema.Definition;
procedure Require(Value: Boolean; const Msg: string);
begin if not Value then raise Exception.Create(Msg); end;
var C: TUniConnection; Q: TUniQuery; T: TTableSchema; Rejected: Boolean;
begin
  C := TDatabaseConnection.OpenFromEnvironment;
  try
    TSchemaRunner.Apply(C);
    TSchemaRunner.Apply(C);
    C.ExecSQL('insert into empresas (cnpj,state,legal_name) values (''00000000000001'',''PA'',''Preservar'')');
    TSchemaRunner.Apply(C);
    Q := TUniQuery.Create(nil);
    try
      Q.Connection := C;
      Q.SQL.Text := 'select count(*) as n from empresas where legal_name = ''Preservar'''; Q.Open;
      Require(Q.FieldByName('n').AsInteger = 1, 'Reaplicacao perdeu dados'); Q.Close;
      T := TTableSchema.Create('teste_remocao');
      try
        T.AddField('preservar', sftText);
        TPostgresSchema.Apply(C,T);
        T.RemoveField('preservar');
        Rejected := False;
        try TPostgresSchema.Apply(C,T); except on E: EInvalidOpException do Rejected := True; end;
        Require(Rejected, 'Remocao destrutiva nao foi recusada');
      finally T.Free; end;
    finally Q.Free; end;
    Writeln('Schema aprovado: criacao, reaplicacao, preservacao de dados e recusa de remocao.');
  finally C.Free; end;
end.
