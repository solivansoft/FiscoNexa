unit Tables.Assinaturas;
interface
uses Schema.Definition;
function PlanosTable: TTableSchema;
function AssinaturasTable: TTableSchema;
function ClientesCobrancaTable: TTableSchema;
function CobrancasTable: TTableSchema;
function EventosCobrancaTable: TTableSchema;
function WebhooksCobrancaTable: TTableSchema;
function PedidosCobrancaTable: TTableSchema;
implementation
function PlanosTable: TTableSchema;
begin
  Result := TTableSchema.Create('planos_assinatura');
  Result.AddField('codigo', sftText, [sfaPrimaryKey]);
  Result.AddField('nome', sftText, [sfaNotNull]);
  Result.AddField('meses', sftInteger, [sfaNotNull]);
  Result.AddField('valor_centavos', sftBigInteger, [sfaNotNull]);
  Result.AddField('valor_referencia_centavos', sftBigInteger, [sfaNotNull]);
  Result.AddField('ativo', sftBoolean, [sfaNotNull], 'true');
  Result.AddField('created_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddCheck('planos_valores_check', 'meses in (1,3,12) and valor_centavos > 0 and valor_referencia_centavos >= valor_centavos');
  Result.ExecuteData('planos-iniciais-v1',
    'insert into planos_assinatura(codigo,nome,meses,valor_centavos,valor_referencia_centavos) values ' +
    '(''mensal'',''Mensal'',1,4990,4990),(''trimestral'',''Trimestral'',3,14970,14970),(''anual'',''Anual'',12,49900,59880) ' +
    'on conflict do nothing ');
end;
function AssinaturasTable: TTableSchema;
begin
  Result := TTableSchema.Create('assinaturas');
  Result.AddField('company_id', sftUuid, [sfaPrimaryKey]);
  Result.AddField('modalidade', sftText, [sfaNotNull], '''direta''');
  Result.AddField('trial_iniciado_em', sftTimestamp, [sfaNotNull], 'now()');
  Result.AddField('trial_termina_em', sftTimestamp, [sfaNotNull], 'now()+interval ''15 days''');
  Result.AddField('pago_ate', sftTimestamp, []);
  Result.AddField('ambiente_pagamentos', sftText, []);
  Result.AddField('protecao_dias', sftInteger, [sfaNotNull], '30');
  Result.AddField('created_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddField('updated_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddForeignKey('assinaturas_empresa_fk','company_id','empresas','id','restrict');
  Result.AddCheck('assinaturas_politica_check', 'modalidade in (''direta'',''parceiro'') and protecao_dias between 0 and 90 and trial_termina_em >= trial_iniciado_em');
  Result.ExecuteData('trial-tenants-existentes-v1',
    'insert into assinaturas(company_id) select id from empresas on conflict do nothing ');
end;
function ClientesCobrancaTable: TTableSchema;
begin
  Result := TTableSchema.Create('clientes_cobranca');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('company_id', sftUuid, [sfaNotNull]);
  Result.AddField('ambiente', sftText, [sfaNotNull]);
  Result.AddField('asaas_id', sftText, []);
  Result.AddForeignKey('clientes_cobranca_empresa_fk','company_id','empresas','id','restrict');
  Result.AddIndex('clientes_cobranca_empresa_ambiente','company_id,ambiente',True);
  Result.AddIndex('clientes_cobranca_asaas_ambiente','asaas_id,ambiente',True);
  Result.AddCheck('clientes_cobranca_ambiente_check','ambiente in (''sandbox'',''producao'')');
end;
function CobrancasTable: TTableSchema;
begin
  Result := TTableSchema.Create('cobrancas');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('company_id', sftUuid, [sfaNotNull]);
  Result.AddField('plano_codigo', sftText, [sfaNotNull]);
  Result.AddField('ambiente', sftText, [sfaNotNull]);
  Result.AddField('chave_idempotencia', sftText, [sfaNotNull]);
  Result.AddField('meses', sftInteger, [sfaNotNull]);
  Result.AddField('valor_centavos', sftBigInteger, [sfaNotNull]);
  Result.AddField('situacao', sftText, [sfaNotNull], '''criando''');
  Result.AddField('forma_pagamento', sftText, []);
  Result.AddField('url_pagamento', sftText, []);
  Result.AddField('aprovada_em', sftTimestamp, []);
  Result.AddField('asaas_id', sftText, []);
  Result.AddField('envio_iniciado', sftBoolean, [sfaNotNull], 'false');
  Result.AddField('vence_em', sftDate, [sfaNotNull], 'current_date + 1');
  Result.AddField('recebida_em', sftTimestamp, []);
  Result.AddField('sincronizada_em', sftTimestamp, []);
  Result.AddField('created_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddField('updated_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddForeignKey('cobrancas_empresa_fk','company_id','assinaturas','company_id','restrict');
  Result.AddForeignKey('cobrancas_plano_fk','plano_codigo','planos_assinatura','codigo','restrict');
  Result.AddIndex('cobrancas_idempotencia_idx','company_id,ambiente,chave_idempotencia',True);
  Result.AddIndex('cobrancas_asaas_idx','ambiente,asaas_id',True);
  Result.AddCheck('cobrancas_valores_check','valor_centavos > 0 and meses in (1,3,12)');
  Result.AddCheck('cobrancas_ambiente_check','ambiente in (''sandbox'',''producao'')');
  Result.AddCheck('cobrancas_situacao_v2_check','situacao in (''criando'',''pendente'',''vencida'',''confirmada'',''recebida'',''cancelada'',''estornada'',''contestada'')');
  Result.ExecuteData('cobrancas-situacao-v2',
    'alter table cobrancas drop constraint if exists cobrancas_situacao_check');
  Result.ExecuteData('cobranca-aberta-unica-v1',
    'create unique index cobrancas_aberta_idx on cobrancas(company_id,ambiente) where situacao in (''criando'',''pendente'',''vencida'') ');
  Result.ExecuteData('recalcular-assinatura-v2',
    'create or replace function recalcular_assinatura(p_empresa uuid,p_ambiente text) returns void ' +
    'language plpgsql as $f$ ' +
    'declare limite timestamptz; item record; quantidade integer := 0; ' +
    'begin ' +
    ' select trial_termina_em into limite from assinaturas where company_id=p_empresa for update; ' +
    ' for item in select coalesce(aprovada_em,recebida_em) as inicio,meses from cobrancas where company_id=p_empresa and ambiente=p_ambiente ' +
    '   and situacao in (''recebida'',''confirmada'') and coalesce(aprovada_em,recebida_em) is not null order by inicio,id loop ' +
    '   limite := greatest(limite,item.inicio) + make_interval(months => item.meses); ' +
    '   quantidade := quantidade+1; ' +
    ' end loop; ' +
    ' update assinaturas set pago_ate=case when quantidade>0 then limite else null end, updated_at=now() where company_id=p_empresa; ' +
    'end $f$ ');
  Result.ExecuteData('acessos-assinatura-v1',
    'create or replace view acessos_assinatura as ' +
    'select a.company_id,a.modalidade,a.trial_iniciado_em,a.trial_termina_em,a.pago_ate, ' +
    ' greatest(a.trial_termina_em,a.pago_ate) as valido_ate, ' +
    ' greatest(a.trial_termina_em,a.pago_ate)+make_interval(days=>a.protecao_dias) as monitoramento_protegido_ate, ' +
    ' case when a.modalidade=''direta'' then greatest(a.trial_termina_em,a.pago_ate)>now() ' +
    ' else (l.company_id is null or l.situacao=''liberado'' or coalesce(l.acesso_liberado_ate>now(),false)) end as entrega_permitida, ' +
    ' case when a.modalidade=''direta'' then greatest(a.trial_termina_em,a.pago_ate)+make_interval(days=>a.protecao_dias)>now() ' +
    ' else (l.company_id is null or l.situacao=''liberado'' or coalesce(l.acesso_liberado_ate>now(),false) ' +
    ' or coalesce(l.proteger_monitoramento_ate>now(),false)) end as monitoramento_permitido ' +
    'from assinaturas a left join licencas l on l.company_id=a.company_id ');
end;
function EventosCobrancaTable: TTableSchema;
begin
  Result := TTableSchema.Create('eventos_cobranca');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('ambiente', sftText, [sfaNotNull]);
  Result.AddField('evento_id', sftText, [sfaNotNull]);
  Result.AddField('cobranca_id', sftUuid, [sfaNotNull]);
  Result.AddField('tipo', sftText, [sfaNotNull]);
  Result.AddField('situacao_observada', sftText, [sfaNotNull]);
  Result.AddField('created_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddForeignKey('eventos_cobranca_fk','cobranca_id','cobrancas','id','restrict');
  Result.AddIndex('eventos_cobranca_id_idx','ambiente,evento_id',True);
end;
function WebhooksCobrancaTable: TTableSchema;
begin
  Result := TTableSchema.Create('webhooks_cobranca');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('ambiente', sftText, [sfaNotNull]);
  Result.AddField('evento_id', sftText, [sfaNotNull]);
  Result.AddField('tipo', sftText, [sfaNotNull]);
  Result.AddField('pagamento_id', sftText, [sfaNotNull]);
  Result.AddField('processado_em', sftTimestamp, []);
  Result.AddField('tentativas', sftInteger, [sfaNotNull], '0');
  Result.AddField('executar_apos', sftTimestamp, [sfaNotNull], 'now()');
  Result.AddField('created_at', sftTimestamp, [sfaNotNull, sfaDefaultNow]);
  Result.AddIndex('webhooks_cobranca_evento_idx','ambiente,evento_id',True);
  Result.AddIndex('webhooks_cobranca_fila_idx','processado_em,executar_apos');
end;
function PedidosCobrancaTable: TTableSchema;
begin
  Result := TTableSchema.Create('pedidos_cobranca');
  Result.AddField('id', sftUuid, [sfaPrimaryKey, sfaDefaultUuid]);
  Result.AddField('company_id', sftUuid, [sfaNotNull]);
  Result.AddField('ambiente', sftText, [sfaNotNull]);
  Result.AddField('chave', sftText, [sfaNotNull]);
  Result.AddField('cobranca_id', sftUuid, [sfaNotNull]);
  Result.AddForeignKey('pedidos_cobranca_fk','cobranca_id','cobrancas','id','restrict');
  Result.AddIndex('pedidos_cobranca_chave_idx','company_id,ambiente,chave',True);
end;
end.
