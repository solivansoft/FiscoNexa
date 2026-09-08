program FiscoNexa.AssinaturasIntegration;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.JSON, FireDAC.Comp.Client, FireDAC.Stan.Param,
  Database.Connection, Schema.Runner, Persistence.Assinaturas;
var C: TFDConnection; S: TAssinaturasService; CompanyId,Trial,FirstEnd: string;
function Value(const Sql: string): string;
var Q: TFDQuery;
begin
  Q:=TFDQuery.Create(nil);
  try Q.Connection:=C; Q.SQL.Text:=Sql; Q.Open; Result:=Q.Fields[0].AsString;
  finally Q.Free; end;
end;
procedure Require(const Condition: Boolean; const Msg: string);
begin if not Condition then raise Exception.Create(Msg); Writeln('OK ',Msg); end;
begin
  try
    if not GetEnvironmentVariable('FISCONEXA_DB_NAME').StartsWith('fisconexa_assinaturas_teste') then
      raise Exception.Create('Teste exige banco dedicado fisconexa_assinaturas_teste.');
    C:=TDatabaseConnection.OpenFromEnvironment;
    try
      TSchemaRunner.Apply(C);
      CompanyId:=Value('insert into empresas(cnpj,state,legal_name) values(''00000000000401'',''PA'',''Assinaturas teste'') '+
        'on conflict(cnpj) do update set legal_name=excluded.legal_name returning id::text');
      C.ExecSQL('insert into assinaturas(company_id) values('''+CompanyId+''') on conflict do nothing');
      Trial:=Value('select trial_termina_em::text from assinaturas where company_id='''+CompanyId+'''');
      TSchemaRunner.Apply(C);
      Require(Trial=Value('select trial_termina_em::text from assinaturas where company_id='''+CompanyId+''''),'Migration nao reinicia trial');
      Require(Value('select count(*) from planos_assinatura')='3','Tres planos iniciais');
      C.StartTransaction;
      try
        S:=TAssinaturasService.Create(C);
        try Require(Pos('trial',S.Assinatura(CompanyId))>0,'Trial exposto ao ERP'); finally S.Free; end;
        Require(Value('select entrega_permitida::int from acessos_assinatura where company_id='''+CompanyId+'''')='1','Trial libera acesso');
        C.ExecSQL('update assinaturas set trial_iniciado_em=now()-interval ''16 days'',trial_termina_em=now()-interval ''1 day'' where company_id='''+CompanyId+'''');
        Require(Value('select entrega_permitida::int from acessos_assinatura where company_id='''+CompanyId+'''')='0','Vencimento bloqueia entrega');
        Require(Value('select monitoramento_permitido::int from acessos_assinatura where company_id='''+CompanyId+'''')='1','Protecao preserva monitoramento');
        C.ExecSQL('update assinaturas set trial_iniciado_em=now()-interval ''50 days'',trial_termina_em=now()-interval ''31 days'' where company_id='''+CompanyId+'''');
        Require(Value('select monitoramento_permitido::int from acessos_assinatura where company_id='''+CompanyId+'''')='0','Fim da protecao suspende monitoramento');
        C.ExecSQL('update assinaturas set trial_iniciado_em=now(),trial_termina_em=now()+interval ''15 days'' where company_id='''+CompanyId+'''');
        C.ExecSQL('insert into cobrancas(company_id,plano_codigo,ambiente,chave_idempotencia,meses,valor_centavos,situacao,recebida_em) '+
          'values('''+CompanyId+''',''mensal'',''sandbox'',''teste-pago-1'',1,4990,''recebida'',now())');
        Value('select recalcular_assinatura('''+CompanyId+''',''sandbox'')');
        FirstEnd:=Value('select pago_ate::text from assinaturas where company_id='''+CompanyId+'''');
        Require(Value('select (pago_ate=trial_termina_em+interval ''1 month'')::int from assinaturas where company_id='''+CompanyId+'''')='1','Pagamento antecipado preserva trial');
        Value('select recalcular_assinatura('''+CompanyId+''',''sandbox'')');
        Require(FirstEnd=Value('select pago_ate::text from assinaturas where company_id='''+CompanyId+''''),'Replay nao concede periodo duplicado');
        C.ExecSQL('insert into cobrancas(company_id,plano_codigo,ambiente,chave_idempotencia,meses,valor_centavos,situacao,recebida_em) '+
          'values('''+CompanyId+''',''anual'',''sandbox'',''teste-pago-2'',12,49900,''recebida'',now()+interval ''1 second'')');
        Value('select recalcular_assinatura('''+CompanyId+''',''sandbox'')');
        Require(Value('select (pago_ate=trial_termina_em+interval ''1 month''+interval ''12 months'')::int from assinaturas where company_id='''+CompanyId+'''')='1','Renovacao anual acumula periodo restante');
        C.ExecSQL('update cobrancas set situacao=''estornada'' where company_id='''+CompanyId+''' and chave_idempotencia=''teste-pago-2''');
        Value('select recalcular_assinatura('''+CompanyId+''',''sandbox'')');
        Require(FirstEnd=Value('select pago_ate::text from assinaturas where company_id='''+CompanyId+''''),'Estorno remove somente periodo estornado');
        C.ExecSQL('update cobrancas set situacao=''confirmada'',aprovada_em=recebida_em,recebida_em=null where company_id='''+CompanyId+''' and chave_idempotencia=''teste-pago-1''');
        Value('select recalcular_assinatura('''+CompanyId+''',''sandbox'')');
        Require(FirstEnd=Value('select pago_ate::text from assinaturas where company_id='''+CompanyId+''''),'Cartao confirmado libera sem aguardar liquidacao');
        C.ExecSQL('update cobrancas set situacao=''recebida'',recebida_em=now()+interval ''32 days'' where company_id='''+CompanyId+''' and chave_idempotencia=''teste-pago-1''');
        Value('select recalcular_assinatura('''+CompanyId+''',''sandbox'')');
        Require(FirstEnd=Value('select pago_ate::text from assinaturas where company_id='''+CompanyId+''''),'Liquidacao posterior nao estende o periodo novamente');
        C.ExecSQL('insert into licencas(company_id,situacao,referencia,versao_origem) values('''+CompanyId+''',''restrito'',''teste'',1)');
        Require(Value('select entrega_permitida::int from acessos_assinatura where company_id='''+CompanyId+'''')='1','ERP nao bloqueia assinatura direta paga');
        C.ExecSQL('update assinaturas set modalidade=''parceiro'' where company_id='''+CompanyId+'''');
        Require(Value('select entrega_permitida::int from acessos_assinatura where company_id='''+CompanyId+'''')='0','Modalidade parceiro respeita licenca');
      finally C.Rollback; end;
    finally C.Free; end;
    Writeln('Integracao de assinaturas aprovada.');
  except on E: Exception do begin Writeln(E.ClassName,': ',E.Message); ExitCode:=1; end; end;
end.
