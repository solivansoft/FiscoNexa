begin;

create schema if not exists observabilidade;
revoke all on schema observabilidade from public;

create or replace view observabilidade.tenants_resumo
with (security_barrier = true) as
select
  company.id as id_empresa,
  company.cnpj,
  coalesce(nullif(company.trade_name, ''), company.legal_name) as empresa,
  company.legal_name as razao_social,
  company.state as uf,
  case when company.disabled_at is null then 'ativa' else 'inativa' end as situacao_empresa,
  case coalesce(monitor.status, 'pending')
    when 'active' then 'ativo'
    when 'attention' then 'atencao'
    when 'inactive' then 'inativo'
    else 'pendente'
  end as situacao_monitoramento,
  coalesce(license.situacao, 'liberado') as situacao_licenca,
  license.acesso_liberado_ate,
  license.proteger_monitoramento_ate,
  certificate.valid_until as certificado_valido_ate,
  case
    when certificate.valid_until is null then 'sem_certificado'
    when certificate.valid_until < current_date then 'vencido'
    when certificate.valid_until <= current_date + 30 then 'vence_em_30_dias'
    else 'valido'
  end as situacao_certificado,
  certificate.valid_until - current_date as dias_para_vencimento,
  monitor.interval_minutes as intervalo_minutos,
  monitor.last_checked_at as ultima_consulta,
  monitor.next_check_at as proxima_consulta,
  monitor.last_nsu as ultimo_nsu,
  monitor.last_cstat as ultimo_cstat,
  coalesce(monitor.failure_count, 0) as falhas,
  coalesce(monitor.blocked_count, 0) as bloqueios_sefaz,
  monitor.last_error is not null as possui_erro,
  coalesce(monitor.status = 'active' and monitor.next_check_at < now(), false) as monitoramento_atrasado,
  coalesce(doc.documents_total, 0) as documentos_monitorados,
  coalesce(doc.xml_total, 0) as xml_baixados,
  coalesce(doc.documents_without_xml, 0) as documentos_sem_xml,
  coalesce(doc.documents_24h, 0) as documentos_24h,
  coalesce(doc.documents_7d, 0) as documentos_7d,
  coalesce(doc.documents_30d, 0) as documentos_30d,
  coalesce(doc.total_amount, 0)::numeric(18,2) as valor_total_documentos,
  case when coalesce(doc.documents_total, 0) = 0 then 0
       else round(100.0 * doc.xml_total / doc.documents_total, 1)
  end as cobertura_xml_percentual
from empresas company
left join status_monitoramento monitor on monitor.company_id = company.id
left join licencas license on license.company_id = company.id
left join lateral (
  select c.valid_until
    from certificados c
   where c.company_id = company.id and c.revoked_at is null
   order by c.created_at desc
   limit 1
) certificate on true
left join lateral (
  select
    count(*)::bigint as documents_total,
    count(*) filter (where d.xml_object_key is not null and d.xml_sha256 is not null)::bigint as xml_total,
    count(*) filter (where d.status <> 'cancelled' and
      (d.xml_object_key is null or d.xml_sha256 is null))::bigint as documents_without_xml,
    count(*) filter (where d.created_at >= now() - interval '24 hours')::bigint as documents_24h,
    count(*) filter (where d.created_at >= now() - interval '7 days')::bigint as documents_7d,
    count(*) filter (where d.created_at >= now() - interval '30 days')::bigint as documents_30d,
    coalesce(sum(d.total_amount), 0) as total_amount
  from documentos d
  where d.company_id = company.id
) doc on true;

create or replace view observabilidade.kpis_gerais
with (security_barrier = true) as
select
  count(*)::bigint as tenants_total,
  count(*) filter (where situacao_empresa = 'ativa')::bigint as tenants_ativos,
  count(*) filter (where situacao_empresa = 'inativa')::bigint as tenants_inativos,
  count(*) filter (where situacao_monitoramento = 'atencao')::bigint as tenants_em_atencao,
  count(*) filter (where situacao_licenca = 'restrito')::bigint as licencas_restritas,
  count(*) filter (where situacao_certificado = 'valido')::bigint as certificados_validos,
  count(*) filter (where situacao_certificado = 'vence_em_30_dias')::bigint as certificados_vencendo_30_dias,
  count(*) filter (where situacao_certificado = 'vencido')::bigint as certificados_vencidos,
  count(*) filter (where situacao_certificado = 'sem_certificado')::bigint as tenants_sem_certificado,
  count(*) filter (where monitoramento_atrasado)::bigint as monitoramentos_atrasados,
  coalesce(sum(documentos_monitorados), 0)::bigint as documentos_monitorados,
  coalesce(sum(xml_baixados), 0)::bigint as xml_baixados,
  coalesce(sum(documentos_sem_xml), 0)::bigint as documentos_sem_xml,
  coalesce(sum(documentos_24h), 0)::bigint as documentos_24h,
  coalesce(sum(documentos_7d), 0)::bigint as documentos_7d,
  coalesce(sum(documentos_30d), 0)::bigint as documentos_30d,
  coalesce(sum(valor_total_documentos), 0)::numeric(18,2) as valor_total_documentos,
  case when coalesce(sum(documentos_monitorados), 0) = 0 then 0
       else round(100.0 * sum(xml_baixados) / sum(documentos_monitorados), 1)
  end as cobertura_xml_percentual
from observabilidade.tenants_resumo;

create or replace view observabilidade.documentos_por_dia
with (security_barrier = true) as
select
  date_trunc('day', d.created_at) as dia,
  count(*)::bigint as documentos_monitorados,
  count(*) filter (where d.xml_object_key is not null and d.xml_sha256 is not null)::bigint as xml_baixados,
  coalesce(sum(d.total_amount), 0)::numeric(18,2) as valor_total
from documentos d
group by date_trunc('day', d.created_at);

create or replace view observabilidade.documentos_por_situacao
with (security_barrier = true) as
select
  case d.status
    when 'located' then 'localizado'
    when 'awareness_registered' then 'ciencia_registrada'
    when 'manifested' then 'manifestado'
    when 'xml_available' then 'xml_disponivel'
    when 'cancelled' then 'cancelado'
    else d.status
  end as situacao,
  count(*)::bigint as quantidade
from documentos d
group by d.status;

create or replace view observabilidade.documentos_recentes
with (security_barrier = true) as
select
  d.id as id_documento,
  coalesce(nullif(company.trade_name, ''), company.legal_name) as empresa,
  company.cnpj as cnpj_destinatario,
  d.access_key as chave_acesso,
  d.issued_at as emitida_em,
  d.created_at as monitorada_em,
  d.issuer_cnpj as cnpj_emitente,
  d.nome_emitente,
  d.document_type as tipo_documento,
  d.tipo_operacao,
  d.situacao_fiscal,
  case d.status
    when 'located' then 'localizado'
    when 'awareness_registered' then 'ciencia_registrada'
    when 'manifested' then 'manifestado'
    when 'xml_available' then 'xml_disponivel'
    when 'cancelled' then 'cancelado'
    else d.status
  end as situacao,
  (d.xml_object_key is not null and d.xml_sha256 is not null) as xml_baixado,
  d.total_amount::numeric(18,2) as valor_total
from documentos d
join empresas company on company.id = d.company_id;

create or replace view observabilidade.operacao_geral
with (security_barrier = true) as
select
  (select count(*) from status_monitoramento where status = 'active')::bigint as monitores_ativos,
  (select count(*) from status_monitoramento
    where status = 'active' and next_check_at < now()
      and coalesce(lease_until, '-infinity'::timestamptz) <= now())::bigint as janelas_atrasadas,
  (select case when count(*) = 0 then 100
          else round(100.0 * count(*) filter (where next_check_at >= now()
            or coalesce(lease_until, '-infinity'::timestamptz) > now()) / count(*), 1) end
    from status_monitoramento where status = 'active') as janelas_em_dia_percentual,
  (select count(*) from status_monitoramento where last_error is not null)::bigint as tenants_com_erro,
  (select count(*) from observabilidade.tenants_resumo
    where documentos_30d = 0)::bigint as tenants_sem_movimento_30d,
  (select count(*) from comandos where command_type = 'retrieve_xml'
    and status = 'pending' and run_after <= now())::bigint as comandos_pendentes,
  (select count(*) from comandos where command_type = 'retrieve_xml'
    and status = 'running')::bigint as comandos_processando,
  (select count(*) from comandos where command_type = 'retrieve_xml'
    and status = 'failed')::bigint as comandos_com_falha,
  (select coalesce(round(avg(extract(epoch from (completed_at - created_at))), 1), 0)
    from comandos where command_type = 'retrieve_xml' and status = 'succeeded'
      and completed_at is not null) as tempo_medio_comando_segundos,
  (select count(*) from lacunas_monitoramento where status in ('pending', 'running'))::bigint as lacunas_abertas,
  (select count(*) from lacunas_monitoramento where status = 'failed')::bigint as lacunas_com_falha,
  (select coalesce(sum(recovered_count), 0) from lacunas_monitoramento)::bigint as nsus_recuperados,
  (select count(*) from integracoes where revoked_at is null)::bigint as integracoes_ativas,
  (select count(*) from integracoes where revoked_at is not null)::bigint as integracoes_revogadas,
  (select count(*) from documentos where status <> 'cancelled'
    and (xml_object_key is null or xml_sha256 is null)
    and created_at < now() - interval '90 days')::bigint as sem_xml_mais_90_dias,
  (select coalesce(round(avg(extract(epoch from (updated_at - created_at)) / 3600.0), 2), 0)
    from documentos where xml_object_key is not null and xml_sha256 is not null) as tempo_estimado_ate_xml_horas,
  pg_database_size(current_database())::bigint as banco_bytes;

create or replace view observabilidade.documentos_sem_xml_por_idade
with (security_barrier = true) as
select faixa, ordem, count(*)::bigint as quantidade
from (
  select
    case
      when created_at >= now() - interval '24 hours' then 'ate_24_horas'
      when created_at >= now() - interval '7 days' then 'de_1_a_7_dias'
      when created_at >= now() - interval '30 days' then 'de_8_a_30_dias'
      when created_at >= now() - interval '90 days' then 'de_31_a_90_dias'
      else 'mais_de_90_dias'
    end as faixa,
    case
      when created_at >= now() - interval '24 hours' then 1
      when created_at >= now() - interval '7 days' then 2
      when created_at >= now() - interval '30 days' then 3
      when created_at >= now() - interval '90 days' then 4
      else 5
    end as ordem
  from documentos
  where status <> 'cancelled' and (xml_object_key is null or xml_sha256 is null)
) pending
group by faixa, ordem;

create or replace view observabilidade.tempo_xml_por_tenant
with (security_barrier = true) as
select
  coalesce(nullif(company.trade_name, ''), company.legal_name) as empresa,
  count(*)::bigint as xml_baixados,
  round(avg(extract(epoch from (document.updated_at - document.created_at)) / 3600.0), 2)
    as tempo_estimado_medio_horas,
  round(max(extract(epoch from (document.updated_at - document.created_at)) / 3600.0), 2)
    as maior_tempo_estimado_horas
from documentos document
join empresas company on company.id = document.company_id
where document.xml_object_key is not null and document.xml_sha256 is not null
group by company.id, company.trade_name, company.legal_name;

create or replace view observabilidade.comandos_por_situacao
with (security_barrier = true) as
select
  case status
    when 'pending' then 'pendente'
    when 'running' then 'processando'
    when 'succeeded' then 'concluido'
    when 'failed' then 'falhou'
    when 'cancelled' then 'cancelado'
    else status
  end as situacao,
  count(*)::bigint as quantidade
from comandos
where command_type = 'retrieve_xml'
group by status;

create or replace view observabilidade.comandos_recentes
with (security_barrier = true) as
select
  coalesce(nullif(company.trade_name, ''), company.legal_name) as empresa,
  command.created_at as solicitado_em,
  command.run_after as executar_apos,
  command.completed_at as concluido_em,
  case command.status
    when 'pending' then 'pendente'
    when 'running' then 'processando'
    when 'succeeded' then 'concluido'
    when 'failed' then 'falhou'
    when 'cancelled' then 'cancelado'
    else command.status
  end as situacao,
  command.attempts as tentativas,
  command.last_cstat as cstat,
  case when command.completed_at is null then null
       else round(extract(epoch from (command.completed_at - command.created_at))::numeric, 1)
  end as duracao_segundos
from comandos command
join empresas company on company.id = command.company_id
where command.command_type = 'retrieve_xml';

create or replace view observabilidade.lacunas_por_situacao
with (security_barrier = true) as
select
  case status
    when 'pending' then 'pendente'
    when 'running' then 'processando'
    when 'succeeded' then 'recuperada'
    when 'failed' then 'falhou'
    else status
  end as situacao,
  count(*)::bigint as quantidade,
  coalesce(sum(recovered_count), 0)::bigint as nsus_recuperados
from lacunas_monitoramento
group by status;

create or replace view observabilidade.lacunas_recentes
with (security_barrier = true) as
select
  coalesce(nullif(company.trade_name, ''), company.legal_name) as empresa,
  gap.start_nsu as nsu_inicial,
  gap.end_nsu as nsu_final,
  gap.next_nsu as proximo_nsu,
  case gap.status
    when 'pending' then 'pendente'
    when 'running' then 'processando'
    when 'succeeded' then 'recuperada'
    when 'failed' then 'falhou'
    else gap.status
  end as situacao,
  gap.attempts as tentativas,
  gap.recovered_count as recuperados,
  gap.last_cstat as cstat,
  gap.next_attempt_at as proxima_tentativa,
  gap.updated_at as atualizada_em
from lacunas_monitoramento gap
join empresas company on company.id = gap.company_id;

create or replace view observabilidade.consultas_pontuais_por_dia
with (security_barrier = true) as
select
  date_trunc('day', requested_at) as dia,
  count(*) filter (where origin = 'command')::bigint as solicitacoes_erp,
  count(*) filter (where origin = 'gap')::bigint as recuperacoes_lacuna
from consultas_pontuais
group by date_trunc('day', requested_at);

create or replace view observabilidade.cstat_sefaz
with (security_barrier = true) as
select origem, cstat, quantidade
from (
  select 'ultima_consulta_tenant'::text as origem, last_cstat as cstat,
    count(*)::bigint as quantidade
  from status_monitoramento where last_cstat is not null group by last_cstat
  union all
  select 'consulta_pontual'::text, cstat, count(*)::bigint
  from consultas_pontuais where cstat is not null group by cstat
  union all
  select 'ciencia'::text, ciencia_cstat, count(*)::bigint
  from documentos where ciencia_cstat is not null group by ciencia_cstat
) status;

create or replace view observabilidade.manifestacoes_resumo
with (security_barrier = true) as
select
  case
    when ciencia_cstat in (135, 136, 573) then 'ciencia_aceita'
    when ciencia_cstat = 655 then 'manifestacao_final_existente'
    when ciencia_cstat = 596 then 'prazo_encerrado'
    when ciencia_cstat is null then 'sem_tentativa'
    else 'outra_resposta'
  end as resultado,
  count(*)::bigint as quantidade
from documentos
group by 1;

create or replace view observabilidade.qualidade_documentos
with (security_barrier = true) as
select indicador, quantidade
from (
  select 1 as ordem, 'chave_invalida'::text as indicador,
    count(*) filter (where length(access_key) <> 44)::bigint as quantidade from documentos
  union all select 2, 'sem_data_emissao', count(*) filter (where issued_at is null)::bigint from documentos
  union all select 3, 'sem_cnpj_emitente', count(*) filter (where issuer_cnpj is null or issuer_cnpj = '')::bigint from documentos
  union all select 4, 'sem_nome_emitente', count(*) filter (where nome_emitente is null or nome_emitente = '')::bigint from documentos
  union all select 5, 'sem_valor_total', count(*) filter (where total_amount is null)::bigint from documentos
  union all select 6, 'xml_sem_hash', count(*) filter (where xml_object_key is not null and xml_sha256 is null)::bigint from documentos
) quality
order by ordem;

create or replace view observabilidade.integracoes_por_tenant
with (security_barrier = true) as
select
  coalesce(nullif(company.trade_name, ''), company.legal_name) as empresa,
  count(integration.id)::bigint as integracoes_total,
  count(integration.id) filter (where integration.revoked_at is null)::bigint as integracoes_ativas,
  count(integration.id) filter (where integration.revoked_at is not null)::bigint as integracoes_revogadas,
  max(integration.created_at) filter (where integration.revoked_at is null) as integracao_mais_recente
from empresas company
left join integracoes integration on integration.company_id = company.id
group by company.id, company.trade_name, company.legal_name;

create or replace view observabilidade.licencas_resumo
with (security_barrier = true) as
select
  coalesce(nullif(company.trade_name, ''), company.legal_name) as empresa,
  company.cnpj,
  coalesce(license.situacao, 'liberado') as situacao,
  license.acesso_liberado_ate,
  license.proteger_monitoramento_ate,
  case
    when license.situacao = 'restrito' and license.acesso_liberado_ate > now() then 'periodo_de_confianca'
    when license.situacao = 'restrito' then 'entrega_bloqueada'
    else 'liberada'
  end as estado_comercial,
  case when license.acesso_liberado_ate is null then null
       else floor(extract(epoch from (license.acesso_liberado_ate - now())) / 86400)::integer
  end as dias_ate_bloqueio
from empresas company
left join licencas license on license.company_id = company.id;

create or replace view observabilidade.saude_executiva
with (security_barrier = true) as
select
  greatest(0, 100
    - case when operation.janelas_atrasadas > 0 then 25 else 0 end
    - case when kpi.certificados_vencidos > 0 then 25 else 0 end
    - case when operation.comandos_com_falha > 0 then 15 else 0 end
    - case when operation.lacunas_com_falha > 0 then 15 else 0 end
    - case when kpi.tenants_em_atencao > 0 or operation.tenants_com_erro > 0 then 10 else 0 end
    - case when kpi.licencas_restritas > 0 then 10 else 0 end
    - case when kpi.certificados_vencendo_30_dias > 0 then 5 else 0 end
  )::integer as indice_saude,
  case
    when operation.janelas_atrasadas > 0 or kpi.certificados_vencidos > 0
      or operation.comandos_com_falha > 0 or operation.lacunas_com_falha > 0 then 'critica'
    when kpi.tenants_em_atencao > 0 or operation.tenants_com_erro > 0
      or kpi.licencas_restritas > 0 or kpi.certificados_vencendo_30_dias > 0 then 'atencao'
    else 'saudavel'
  end as situacao
from observabilidade.operacao_geral operation
cross join observabilidade.kpis_gerais kpi;

revoke all on all tables in schema observabilidade from public;

do $role$
begin
  if not exists (select 1 from pg_roles where rolname = 'grafana_fisconexa') then
    create role grafana_fisconexa nologin nosuperuser nocreatedb nocreaterole noreplication;
  end if;
end
$role$;

grant usage on schema observabilidade to grafana_fisconexa;
grant select on all tables in schema observabilidade to grafana_fisconexa;
alter default privileges in schema observabilidade grant select on tables to grafana_fisconexa;

alter role grafana_fisconexa set default_transaction_read_only = on;
alter role grafana_fisconexa set statement_timeout = '5s';
alter role grafana_fisconexa set idle_in_transaction_session_timeout = '10s';
alter role grafana_fisconexa set search_path = observabilidade, pg_catalog;

commit;
