unit Persistence.Assinaturas;
interface
uses FireDAC.Comp.Client, System.JSON, Integrations.Asaas;
type TAssinaturasService = class
private
  FC: TFDConnection;
  function Query(const ASql: string; const AParams: array of string): TFDQuery;
  function Scalar(const ASql: string; const AParams: array of string): string;
  procedure Lock(const AEmpresa: string);
  procedure Unlock(const AEmpresa: string);
  function Cliente(const AEmpresa: string; const AAsaas: TAsaasClient): string;
  procedure Sincronizar(const AEmpresa, AId, AEvento, ATipo: string; const AAsaas: TAsaasClient);
  function JsonCobranca(const AEmpresa, AId: string; const AAsaas: TAsaasClient): string;
public
  constructor Create(const AConnection: TFDConnection);
  function Assinatura(const AEmpresa: string): string;
  function Planos: string;
  function CriarCobranca(const AEmpresa, APlano, AChave: string): string;
  function ConsultarCobranca(const AEmpresa, AId: string; const ACancelar: Boolean=False): string;
  procedure Webhook(const AEvento, ATipo, APagamento: string);
  procedure ReceberWebhook(const AEvento, ATipo, APagamento: string);
  function Reconciliar: Integer;
end;
implementation
uses System.SysUtils, System.DateUtils, FireDAC.Stan.Param, Application.Assinaturas,
  Operations.StructuredLogs;
constructor TAssinaturasService.Create(const AConnection: TFDConnection);
begin inherited Create; FC:=AConnection; end;
function TAssinaturasService.Query(const ASql: string; const AParams: array of string): TFDQuery;
var I: Integer;
begin
  Result:=TFDQuery.Create(nil);
  try
    Result.Connection:=FC;
    Result.SQL.Text:=ASql;
    I:=0;
    while I<Length(AParams) do begin
      Result.ParamByName(AParams[I]).AsString:=AParams[I+1]; Inc(I,2);
    end;
    Result.Open;
  except Result.Free; raise; end;
end;
function TAssinaturasService.Scalar(const ASql: string; const AParams: array of string): string;
var Q: TFDQuery;
begin Q:=Query(ASql,AParams); try
  if Q.IsEmpty then Exit(''); Result:=Q.Fields[0].AsString;
finally Q.Free; end; end;
procedure TAssinaturasService.Lock(const AEmpresa: string);
begin
  if Scalar('select case when pg_try_advisory_lock(hashtextextended(:empresa,4819)) then 1 else 0 end',['empresa',AEmpresa])<>'1' then
    raise ECobrancaConflito.Create('Cobranca em processamento. Tente novamente em alguns segundos.');
end;
procedure TAssinaturasService.Unlock(const AEmpresa: string);
begin Scalar('select pg_advisory_unlock(hashtextextended(:empresa,4819))',['empresa',AEmpresa]); end;
function TAssinaturasService.Planos: string;
begin
  Result:=Scalar('select jsonb_build_object(''moeda'',''BRL'',''por_tenant'',true,'+
    '''limite_documentos'',null,''renovacao_automatica'',false,''itens'',coalesce(jsonb_agg('+
    'jsonb_build_object(''codigo'',codigo,''nome'',nome,''meses'',meses,''valor_centavos'',valor_centavos,'+
    '''valor_referencia_centavos'',valor_referencia_centavos,''economia_centavos'',valor_referencia_centavos-valor_centavos) order by meses),''[]''::jsonb))::text '+
    'from planos_assinatura where ativo',[]);
end;
function TAssinaturasService.Assinatura(const AEmpresa: string): string;
begin
  Result:=Scalar('select jsonb_build_object(''id_empresa'',company_id,''modalidade'',modalidade,'+
    '''situacao'',case when modalidade=''parceiro'' then ''gerenciada_pelo_parceiro'' '+
    'when not entrega_permitida then ''vencida'' when pago_ate>now() then ''ativa'' else ''trial'' end,'+
    '''trial_iniciado_em'',trial_iniciado_em,''trial_termina_em'',trial_termina_em,''pago_ate'',pago_ate,'+
    '''valido_ate'',valido_ate,''dias_restantes'',greatest(0,ceil(extract(epoch from (valido_ate-now()))/86400)),'+
    '''acesso'',jsonb_build_object(''listar_documentos'',entrega_permitida,''baixar_xml'',entrega_permitida,'+
    '''monitoramento'',monitoramento_permitido,''gerenciar_assinatura'',true),'+
    '''monitoramento_protegido_ate'',monitoramento_protegido_ate,''consultar_novamente_em_segundos'',300,'+
    '''cobranca_pendente'',(select jsonb_build_object(''id_cobranca'',c.id,''plano_codigo'',c.plano_codigo,'+
    '''situacao'',c.situacao,''valor_centavos'',c.valor_centavos,''vence_em'',c.vence_em) '+
    'from cobrancas c where c.company_id=acessos_assinatura.company_id '+
    'and c.situacao in (''criando'',''pendente'',''vencida'') order by c.created_at desc limit 1),'+
    '''avisos'',case when modalidade<>''direta'' or valido_ate>now()+interval ''3 days'' then ''[]''::jsonb else '+
    'jsonb_build_array(jsonb_build_object(''id'',concat(''assinatura:'',company_id,'':'',valido_ate::text,'':'' ,'+
    'case when entrega_permitida then ''vencimento'' else ''vencida'' end),'+
    '''codigo'',case when entrega_permitida then ''assinatura_proxima_vencimento'' else ''assinatura_vencida'' end,'+
    '''nivel'',case when entrega_permitida then ''aviso'' else ''atencao'' end,'+
    '''mensagem'',case when entrega_permitida then ''Seu acesso ao FiscoNexa vence em breve. Escolha um plano para continuar.'' '+
    'else ''Seu acesso ao FiscoNexa venceu. Renove para consultar documentos e baixar XML.'' end,'+
    '''acao'',jsonb_build_object(''tipo'',''assinar'',''rotulo'',''Ver planos'',''rota'',''/v1/planos''))) end)::text '+
    'from acessos_assinatura where company_id=cast(:empresa as uuid)',['empresa',AEmpresa]);
  if Result='' then raise ECobrancaAusente.Create('Assinatura nao encontrada.');
end;
function TAssinaturasService.Cliente(const AEmpresa: string; const AAsaas: TAsaasClient): string;
var J,R: TJSONObject; V: TJSONValue; Arr: TJSONArray; Q: TFDQuery; LocalId: string;
begin
  LocalId:=Scalar('insert into clientes_cobranca(company_id,ambiente) values (cast(:empresa as uuid),:ambiente) '+
    'on conflict(company_id,ambiente) do update set company_id=excluded.company_id returning id::text',
    ['empresa',AEmpresa,'ambiente',AAsaas.Ambiente]);
  Result:=Scalar('select asaas_id from clientes_cobranca where id=cast(:id as uuid)',['id',LocalId]);
  if Result<>'' then Exit;
  R:=AAsaas.Request('GET','/customers?externalReference='+LocalId+'&limit=100');
  try
    V:=R.GetValue('data');
    if not (V is TJSONArray) then raise EAsaasIndisponivel.Create('Lista de clientes invalida.');
    Arr:=TJSONArray(V);
    if Arr.Count>1 then raise ECobrancaConflito.Create('Clientes duplicados no provedor.');
    if Arr.Count=1 then Result:=TextoJson(Arr.Items[0] as TJSONObject,'id');
  finally R.Free; end;
  if Result='' then begin
    Q:=Query('select legal_name,cnpj from empresas where id=cast(:empresa as uuid)',['empresa',AEmpresa]);
    J:=TJSONObject.Create;
    try
      if Q.IsEmpty then raise ECobrancaAusente.Create('Empresa ausente.');
      J.AddPair('name',Q.Fields[0].AsString); J.AddPair('cpfCnpj',Q.Fields[1].AsString);
      J.AddPair('externalReference',LocalId); J.AddPair('notificationDisabled',TJSONBool.Create(True));
      R:=AAsaas.Request('POST','/customers',J);
      try Result:=TextoJson(R,'id'); finally R.Free; end;
    finally J.Free; Q.Free; end;
  end;
  if Result='' then raise EAsaasIndisponivel.Create('Cliente Asaas ausente.');
  Scalar('update clientes_cobranca set asaas_id=:asaas where id=cast(:id as uuid) returning id', ['asaas',Result,'id',LocalId]);
end;
procedure TAssinaturasService.Sincronizar(const AEmpresa,AId,AEvento,ATipo: string; const AAsaas: TAsaasClient);
var Q: TFDQuery; R: TJSONObject; Status,RemoteId,Customer,EventCharge,OldStatus,Forma,Url: string; Value: Int64;
begin
  Q:=Query('select c.asaas_id,cl.asaas_id,c.valor_centavos,c.situacao from cobrancas c '+
    'join clientes_cobranca cl on cl.company_id=c.company_id and cl.ambiente=c.ambiente '+
    'where c.id=cast(:id as uuid) and c.company_id=cast(:empresa as uuid) and c.ambiente=:ambiente',
    ['id',AId,'empresa',AEmpresa,'ambiente',AAsaas.Ambiente]);
  try
    if Q.IsEmpty then raise ECobrancaAusente.Create('Cobranca nao encontrada.');
    RemoteId:=Q.Fields[0].AsString; Customer:=Q.Fields[1].AsString;
    Value:=Q.Fields[2].AsLargeInt; OldStatus:=Q.Fields[3].AsString;
  finally Q.Free; end;
  if RemoteId='' then Exit;
  if AEvento<>'' then begin
    EventCharge:=Scalar('select cobranca_id::text from eventos_cobranca where ambiente=:ambiente and evento_id=:evento',
      ['ambiente',AAsaas.Ambiente,'evento',AEvento]);
    if EventCharge<>'' then begin
      if EventCharge<>AId then raise ECobrancaConflito.Create('Evento divergente.');
      Exit;
    end;
  end;
  R:=AAsaas.Request('GET','/payments/'+RemoteId);
  try
    ValidarPagamento(R,RemoteId,Customer,AId,Value);
    Forma:=TextoJson(R,'billingType');
    Url:=TextoJson(R,'invoiceUrl');
    if TextoJson(R,'deleted')='true' then Status:='cancelada'
    else Status:=SituacaoPagamento(TextoJson(R,'status'),Forma);
    // Estornos parciais nao compram automaticamente um periodo integral.
    if PossuiEstornoConcluido(R) then Status:='estornada';
  finally R.Free; end;
  // Um snapshot pendente atrasado nao revoga um periodo ja confirmado.
  if ((OldStatus='recebida') or (OldStatus='confirmada')) and
    ((Status='pendente') or (Status='vencida')) then Status:=OldStatus;
  if (OldStatus='recebida') and (Status='confirmada') then Status:=OldStatus;
  FC.StartTransaction;
  try
    Scalar('select company_id from assinaturas where company_id=cast(:empresa as uuid) for update',['empresa',AEmpresa]);
    Scalar('update cobrancas set situacao=:situacao,forma_pagamento=:forma,url_pagamento=nullif(:url,''''),'+
      'aprovada_em=case when :situacao in (''recebida'',''confirmada'') then coalesce(aprovada_em,recebida_em,now()) else aprovada_em end,'+
      'recebida_em=case when :situacao=''recebida'' '+
      'then coalesce(recebida_em,now()) else recebida_em end,sincronizada_em=now(),updated_at=now() '+
      'where id=cast(:id as uuid) returning id',['situacao',Status,'forma',Forma,'url',Url,'id',AId]);
    Scalar('select recalcular_assinatura(cast(:empresa as uuid),:ambiente)',['empresa',AEmpresa,'ambiente',AAsaas.Ambiente]);
    if AEvento<>'' then
      Scalar('insert into eventos_cobranca(ambiente,evento_id,cobranca_id,tipo,situacao_observada) '+
        'values (:ambiente,:evento,cast(:id as uuid),:tipo,:situacao) returning id',
        ['ambiente',AAsaas.Ambiente,'evento',AEvento,'id',AId,'tipo',ATipo,'situacao',Status]);
    FC.Commit;
  except FC.Rollback; raise; end;
end;
function TAssinaturasService.JsonCobranca(const AEmpresa,AId: string; const AAsaas: TAsaasClient): string;
var Q: TFDQuery; J,Pix: TJSONObject; V: TJSONValue; RemoteId,Status,Forma: string;
begin
  Q:=Query('select jsonb_build_object(''id_cobranca'',id,''plano_codigo'',plano_codigo,''meses'',meses,'+
    '''valor_centavos'',valor_centavos,''moeda'',''BRL'',''situacao'',situacao,''ambiente'',ambiente,'+
    '''url_pagamento'',url_pagamento,''pagamento_aprovado'',situacao in (''confirmada'',''recebida''),'+
    '''forma_pagamento'',case forma_pagamento when ''UNDEFINED'' then ''a_escolher'' when ''PIX'' then ''pix'' '+
    'when ''CREDIT_CARD'' then ''cartao_credito'' when ''DEBIT_CARD'' then ''cartao_debito'' when ''BOLETO'' then ''boleto'' else null end,'+
    '''aprovada_em'',aprovada_em,''vence_em'',vence_em,''recebida_em'',recebida_em,''consultar_novamente_em_segundos'',10)::text,asaas_id,situacao,forma_pagamento '+
    'from cobrancas where id=cast(:id as uuid) and company_id=cast(:empresa as uuid) and ambiente=:ambiente',
    ['id',AId,'empresa',AEmpresa,'ambiente',AAsaas.Ambiente]);
  try
    if Q.IsEmpty then raise ECobrancaAusente.Create('Cobranca nao encontrada.');
    V:=TJSONObject.ParseJSONValue(Q.Fields[0].AsString); RemoteId:=Q.Fields[1].AsString; Status:=Q.Fields[2].AsString; Forma:=Q.Fields[3].AsString;
  finally Q.Free; end;
  J:=V as TJSONObject;
  try
    if (RemoteId<>'') and ((Status='pendente') or (Status='vencida')) and
      ((Forma='UNDEFINED') or (Forma='PIX') or (Forma='BOLETO')) then begin
      Pix:=AAsaas.Request('GET','/payments/'+RemoteId+'/pixQrCode');
      try
        J.AddPair('pix',TJSONObject.Create
          .AddPair('imagem_base64',TextoJson(Pix,'encodedImage'))
          .AddPair('copia_cola',TextoJson(Pix,'payload'))
          .AddPair('expira_em',TextoJson(Pix,'expirationDate')));
      finally Pix.Free; end;
    end;
    J.AddPair('assinatura',TJSONObject.ParseJSONValue(Assinatura(AEmpresa)));
    Result:=J.ToJSON;
  finally J.Free; end;
end;
function TAssinaturasService.CriarCobranca(const AEmpresa,APlano,AChave: string): string;
var A: TAsaasClient; Q: TFDQuery; Id,ExistingPlan,RemoteId,Customer,Due: string;
  Sent: Boolean; Value: Int64; J,R: TJSONObject; V: TJSONValue; Arr: TJSONArray;
begin
  ValidarChaveCobranca(AChave);
  if not ((APlano='mensal') or (APlano='trimestral') or (APlano='anual')) then
    raise EAssinaturaInvalida.Create('Plano invalido.');
  A:=TAsaasClient.Create;
  try
    Lock(AEmpresa);
    try
      if Scalar('select modalidade from assinaturas where company_id=cast(:empresa as uuid)',['empresa',AEmpresa])<>'direta' then
        raise ECobrancaConflito.Create('Assinatura gerenciada pelo parceiro.');
      if Scalar('update assinaturas set ambiente_pagamentos=coalesce(ambiente_pagamentos,:ambiente) '+
        'where company_id=cast(:empresa as uuid) and (ambiente_pagamentos is null or ambiente_pagamentos=:ambiente) returning company_id',
        ['ambiente',A.Ambiente,'empresa',AEmpresa])='' then
        raise ECobrancaConflito.Create('Assinatura vinculada a outro ambiente financeiro.');
      Id:=Scalar('select id::text from cobrancas where company_id=cast(:empresa as uuid) and ambiente=:ambiente '+
        'and chave_idempotencia=:chave',['empresa',AEmpresa,'ambiente',A.Ambiente,'chave',AChave]);
      if Id='' then Id:=Scalar('select cobranca_id::text from pedidos_cobranca where company_id=cast(:empresa as uuid) '+
        'and ambiente=:ambiente and chave=:chave',['empresa',AEmpresa,'ambiente',A.Ambiente,'chave',AChave]);
      if Id='' then Id:=Scalar('select id::text from cobrancas where company_id=cast(:empresa as uuid) '+
        'and ambiente=:ambiente and situacao in (''criando'',''pendente'',''vencida'')',
        ['empresa',AEmpresa,'ambiente',A.Ambiente]);
      if Id='' then Id:=Scalar('insert into cobrancas(company_id,plano_codigo,ambiente,chave_idempotencia,meses,valor_centavos) '+
        'select cast(:empresa as uuid),codigo,:ambiente,:chave,meses,valor_centavos from planos_assinatura '+
        'where codigo=:plano and ativo returning id::text',
        ['empresa',AEmpresa,'ambiente',A.Ambiente,'chave',AChave,'plano',APlano]);
      if Id='' then raise EAssinaturaInvalida.Create('Plano indisponivel.');
      Q:=Query('select plano_codigo,asaas_id,envio_iniciado,valor_centavos,vence_em::text from cobrancas where id=cast(:id as uuid)', ['id',Id]);
      try ExistingPlan:=Q.Fields[0].AsString; RemoteId:=Q.Fields[1].AsString; Sent:=Q.Fields[2].AsBoolean;
        Value:=Q.Fields[3].AsLargeInt; Due:=Q.Fields[4].AsString;
      finally Q.Free; end;
      if ExistingPlan<>APlano then raise ECobrancaConflito.Create('Existe cobranca para outro plano. Consulte ou cancele antes de trocar.');
      Scalar('insert into pedidos_cobranca(company_id,ambiente,chave,cobranca_id) '+
        'values(cast(:empresa as uuid),:ambiente,:chave,cast(:id as uuid)) on conflict do nothing returning id',
        ['empresa',AEmpresa,'ambiente',A.Ambiente,'chave',AChave,'id',Id]);
      if RemoteId='' then begin
        Customer:=Cliente(AEmpresa,A);
        R:=A.Request('GET','/payments?externalReference='+Id+'&limit=100');
        try
          V:=R.GetValue('data');
          if not (V is TJSONArray) then raise EAsaasIndisponivel.Create('Lista de pagamentos invalida.');
          Arr:=TJSONArray(V);
          if Arr.Count>1 then raise ECobrancaConflito.Create('Pagamentos duplicados no provedor.');
          if Arr.Count=1 then begin
            RemoteId:=TextoJson(Arr.Items[0] as TJSONObject,'id');
            ValidarPagamento(Arr.Items[0] as TJSONObject,RemoteId,Customer,Id,Value);
          end;
        finally R.Free; end;
        if RemoteId='' then begin
          if Sent then raise ECobrancaConflito.Create('Criacao em reconciliacao. Nao foi gerada outra cobranca.');
          Scalar('update cobrancas set envio_iniciado=true where id=cast(:id as uuid) returning id',['id',Id]);
          J:=TJSONObject.Create;
          try
            J.AddPair('customer',Customer); J.AddPair('billingType','UNDEFINED');
            J.AddPair('value',TJSONNumber.Create(Value/100.0)); J.AddPair('dueDate',Due);
            J.AddPair('externalReference',Id); J.AddPair('description','FiscoNexa - '+APlano);
            J.AddPair('interest',TJSONObject.Create.AddPair('value',TJSONNumber.Create(0)));
            J.AddPair('fine',TJSONObject.Create.AddPair('value',TJSONNumber.Create(0)));
            try
              R:=A.Request('POST','/payments',J);
            except
              on E: EAsaasRejeitado do begin
                // Recusa HTTP definitiva: nenhuma cobranca foi criada. Timeout continua ambiguo.
                Scalar('update cobrancas set envio_iniciado=false where id=cast(:id as uuid) returning id',['id',Id]);
                raise;
              end;
            end;
            try
              RemoteId:=TextoJson(R,'id');
              ValidarPagamento(R,RemoteId,Customer,Id,Value);
            finally R.Free; end;
          finally J.Free; end;
        end;
        if RemoteId='' then raise EAsaasIndisponivel.Create('Pagamento Asaas ausente.');
        Scalar('update cobrancas set asaas_id=:asaas,situacao=''pendente'',updated_at=now() '+
          'where id=cast(:id as uuid) returning id',['asaas',RemoteId,'id',Id]);
      end;
      Sincronizar(AEmpresa,Id,'','',A);
      Result:=JsonCobranca(AEmpresa,Id,A);
    finally Unlock(AEmpresa); end;
  finally A.Free; end;
end;
function TAssinaturasService.ConsultarCobranca(const AEmpresa,AId: string; const ACancelar: Boolean): string;
var A: TAsaasClient; RemoteId,Status: string; R: TJSONObject;
begin
  ValidarIdentificador(AId);
  A:=TAsaasClient.Create;
  try
    Lock(AEmpresa);
    try
      if Scalar('select id::text from cobrancas where id=cast(:id as uuid) and company_id=cast(:empresa as uuid) '+
        'and ambiente=:ambiente',['id',AId,'empresa',AEmpresa,'ambiente',A.Ambiente])='' then
        raise ECobrancaAusente.Create('Cobranca nao encontrada.');
      Sincronizar(AEmpresa,AId,'','',A);
      if ACancelar then begin
        Status:=Scalar('select situacao from cobrancas where id=cast(:id as uuid)',['id',AId]);
        if (Status<>'pendente') and (Status<>'vencida') and (Status<>'cancelada') then
          raise ECobrancaConflito.Create('Cobranca nao pode ser cancelada neste estado.');
        if Status<>'cancelada' then begin
          RemoteId:=Scalar('select asaas_id from cobrancas where id=cast(:id as uuid)',['id',AId]);
          R:=A.Request('DELETE','/payments/'+RemoteId);
          try if TextoJson(R,'deleted')<>'true' then raise ECobrancaConflito.Create('Cancelamento nao confirmado.');
          finally R.Free; end;
          Scalar('update cobrancas set situacao=''cancelada'',updated_at=now() where id=cast(:id as uuid) returning id',['id',AId]);
        end;
      end;
      Result:=JsonCobranca(AEmpresa,AId,A);
    finally Unlock(AEmpresa); end;
  finally A.Free; end;
end;
procedure TAssinaturasService.Webhook(const AEvento,ATipo,APagamento: string);
var A: TAsaasClient; Q: TFDQuery; Empresa,Id: string;
begin
  if (AEvento='') or (Length(AEvento)>200) or (Length(ATipo)>120) or (APagamento='') then
    raise EAssinaturaInvalida.Create('Evento invalido.');
  A:=TAsaasClient.Create;
  try
    Q:=Query('select company_id::text,id::text from cobrancas where ambiente=:ambiente and asaas_id=:asaas',
      ['ambiente',A.Ambiente,'asaas',APagamento]);
    try if Q.IsEmpty then Exit; Empresa:=Q.Fields[0].AsString; Id:=Q.Fields[1].AsString; finally Q.Free; end;
    Lock(Empresa);
    try Sincronizar(Empresa,Id,AEvento,ATipo,A); finally Unlock(Empresa); end;
  finally A.Free; end;
end;
procedure TAssinaturasService.ReceberWebhook(const AEvento,ATipo,APagamento: string);
var Ambiente, Existing: string;
begin
  Ambiente:=AmbienteAsaas;
  if (AEvento='') or (Length(AEvento)>200) or (ATipo='') or
    (Length(ATipo)>120) or (APagamento='') or (Length(APagamento)>120) then
    raise EAssinaturaInvalida.Create('Evento invalido.');
  Existing:=Scalar('insert into webhooks_cobranca(ambiente,evento_id,tipo,pagamento_id) '+
    'values(:ambiente,:evento,:tipo,:pagamento) on conflict(ambiente,evento_id) do update '+
    'set evento_id=excluded.evento_id returning pagamento_id',
    ['ambiente',Ambiente,'evento',AEvento,'tipo',ATipo,'pagamento',APagamento]);
  if Existing<>APagamento then raise ECobrancaConflito.Create('Evento divergente.');
end;
function TAssinaturasService.Reconciliar: Integer;
var Q: TFDQuery; Id,Empresa,Plano,Chave,Discard: string;
begin
  Result:=0;
  if GetEnvironmentVariable('ASAAS_API_TOKEN')='' then Exit;
  Lock('reconciliador-asaas');
  try
    Q:=Query('select id::text,evento_id,tipo,pagamento_id from webhooks_cobranca '+
      'where ambiente=:ambiente and processado_em is null and executar_apos<=now() order by created_at limit 20',
      ['ambiente',AmbienteAsaas]);
    try
      while not Q.Eof do begin
        Id:=Q.Fields[0].AsString;
        try
          Webhook(Q.Fields[1].AsString,Q.Fields[2].AsString,Q.Fields[3].AsString);
          Scalar('update webhooks_cobranca set processado_em=now() where id=cast(:id as uuid) returning id',['id',Id]);
          Inc(Result);
        except
          on E: Exception do begin
            RegistrarLog('erro','cobrancas','webhook_reagendado',
              '{"id_webhook":"'+Id+'","classe_erro":"'+E.ClassName+'"}');
            Scalar('update webhooks_cobranca set tentativas=tentativas+1,executar_apos=now()+interval ''60 seconds'' '+
              'where id=cast(:id as uuid) returning id',['id',Id]);
          end;
        end;
        Q.Next;
      end;
    finally Q.Free; end;
    Q:=Query('select id::text,company_id::text,plano_codigo,chave_idempotencia from cobrancas where ambiente=:ambiente '+
      'and ((situacao in (''criando'',''pendente'',''vencida'') and coalesce(sincronizada_em,created_at)<now()-interval ''60 seconds'') '+
      'or (situacao in (''recebida'',''confirmada'',''contestada'') and sincronizada_em<now()-interval ''1 day'')) '+
      'order by sincronizada_em nulls first,created_at limit 20',['ambiente',AmbienteAsaas]);
    try
      while not Q.Eof do begin
        Id:=Q.Fields[0].AsString; Empresa:=Q.Fields[1].AsString; Plano:=Q.Fields[2].AsString; Chave:=Q.Fields[3].AsString;
        try
          Discard:=CriarCobranca(Empresa,Plano,Chave);
          Inc(Result);
        except
          on E: Exception do begin
            RegistrarLog('erro','cobrancas','cobranca_reagendada',
              '{"id_cobranca":"'+Id+'","classe_erro":"'+E.ClassName+'"}');
            Scalar('update cobrancas set sincronizada_em=now() where id=cast(:id as uuid) returning id',['id',Id]);
          end;
        end;
        Q.Next;
      end;
    finally Q.Free; end;
  finally Unlock('reconciliador-asaas'); end;
end;
end.
