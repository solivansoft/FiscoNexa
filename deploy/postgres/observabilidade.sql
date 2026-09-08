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
