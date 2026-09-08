"""Integração HTTP/PG sem SEFAZ, certificados ou credenciais de produção.

Requer container local fisconexa-assinaturas-teste (5438) e API compilada.
Cria banco exclusivo fisconexa_api_guardrail. Inicia/encerra apenas seu processo.
"""
import hashlib
import json
import os
import re
from pathlib import Path
import socket
import subprocess
import time
import uuid
from openapi_schema_validator import OAS30Validator

from test_api_contract import ROOT, contract, negative_http, request

DB = 'fisconexa_api_guardrail'
BASE = 'http://127.0.0.1:19009'
CONTAINER = 'fisconexa-assinaturas-teste'


def sql(query, database=DB):
    assert database in (DB, 'postgres')
    res = subprocess.run(['docker', 'exec', '-i', CONTAINER, 'psql', '-U',
        'assinaturas_teste', '-d', database, '-At', '-v', 'ON_ERROR_STOP=1'],
        input=query, text=True, capture_output=True, check=True)
    return res.stdout.strip().splitlines()[0] if res.stdout.strip() else ''


def sha(token):
    return hashlib.sha256(token.encode()).hexdigest()


def run():
    spec, policy = contract()
    # Porta ocupada nunca pode fazer o teste atingir outra API.
    probe = socket.socket()
    probe.bind(('127.0.0.1', 19009))
    probe.close()
    if sql(f"select 1 from pg_database where datname='{DB}'", 'postgres') != '1':
        sql(f'create database {DB}', 'postgres')
    nonce = uuid.uuid4().hex
    tokens = {k: f'guardrail-{k}-{nonce}' for k in
              ['tenant', 'outro', 'revogado', 'sem_escopo', 'erp', 'erp_expirado',
               'erp_revogado', 'erp_sem_escopo', 'admin', 'usuario', 'desabilitado',
               'sessao_expirada', 'sessao_revogada', 'licenca', 'webhook']}
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('FISCONEXA_', 'ASAAS_', 'AWS_'))}
    env.update(FISCONEXA_DB_HOST='127.0.0.1', FISCONEXA_DB_PORT='5438',
        FISCONEXA_DB_NAME=DB, FISCONEXA_DB_USER='assinaturas_teste',
        FISCONEXA_DB_PASSWORD='senha_apenas_teste_local',
        FISCONEXA_HTTP_HOST='127.0.0.1', FISCONEXA_HTTP_PORT='19009',
        FISCONEXA_ENVIRONMENT='homologacao', ASAAS_AMBIENTE='sandbox',
        ASAAS_API_TOKEN='invalido-teste-sem-chamadas-externas',
        ASAAS_WEBHOOK_TOKEN=tokens['webhook'],
        FISCONEXA_LICENSE_TOKEN_SHA256=sha(tokens['licenca']))
    logdir = ROOT / 'build/api-guardrail'
    logdir.mkdir(parents=True, exist_ok=True)
    count = 0

    def check(method, path, body, token, expected, webhook=False):
        nonlocal count
        hdr = {'asaas-access-token': tokens[token]} if webhook else {'Authorization': 'Bearer ' + tokens[token]}
        code, data = request(BASE, method, path, body, hdr)
        assert code == expected, f'{method} {path} ({token}): esperado {expected}, recebido {code}'
        count += 1
        parsed = json.loads(data) if data else None
        if parsed is not None and code in (200, 201):
            for template, operations in spec['paths'].items():
                pattern = re.sub(r'\{\w+\}', '[^/]+', template)
                if re.fullmatch(pattern, path):
                    schema = operations[method.lower()]['responses'][str(code)]['content']['application/json']['schema']
                    OAS30Validator(dict(schema, components=spec['components'])).validate(parsed)
                    break
        return parsed

    with (logdir / 'api.log').open('wb') as log:
        process = subprocess.Popen([str(ROOT / 'bin/win64/FiscoNexa.Api.exe')], env=env, stdout=log, stderr=log)
        try:
            for _ in range(80):
                if process.poll() is not None:
                    raise RuntimeError('API encerrou; confira build/api-guardrail/api.log')
                try:
                    if request(BASE, 'GET', '/health')[0] == 200:
                        break
                except OSError:
                    pass
                time.sleep(.25)
            else:
                raise RuntimeError('API nao ficou pronta')
            negative_http(BASE, policy)
            companies = []
            for cnpj in ['11222333000181', '11444777000161']:
                cid = sql(f"insert into empresas(cnpj,state,legal_name) values('{cnpj}','PA','Fixture guardrail') on conflict(cnpj) do update set state=excluded.state returning id")
                sql(f"insert into assinaturas(company_id) values('{cid}') on conflict do nothing")
                companies.append(cid)
            for name in ['tenant', 'outro', 'revogado', 'sem_escopo']:
                cid = companies[name == 'outro']
                scopes = '[]' if name == 'sem_escopo' else '["documents:read"]'
                revoked = 'now()' if name == 'revogado' else 'null'
                sql(f"insert into integracoes(company_id,display_name,api_token_hash,scopes,revoked_at) values('{cid}','Fixture','{sha(tokens[name])}','{scopes}',{revoked})")
            org = sql("insert into organizacoes(legal_name,organization_type) values('Fixture guardrail','erp') returning id")
            for name in ['erp', 'erp_expirado', 'erp_revogado', 'erp_sem_escopo']:
                scopes = '[]' if name == 'erp_sem_escopo' else '["companies:onboard","modules:write"]'
                expiry = "now()-interval '1 minute'" if name == 'erp_expirado' else 'null'
                revoke = 'now()' if name == 'erp_revogado' else 'null'
                sql(f"insert into chaves_erp(organization_id,label,key_hash,scopes,expires_at,revoked_at) values('{org}','Fixture','{sha(tokens[name])}','{scopes}',{expiry},{revoke})")
            for name in ['admin', 'usuario', 'desabilitado', 'sessao_expirada', 'sessao_revogada']:
                role = 'user' if name == 'usuario' else 'superadmin'
                disabled = 'now()' if name == 'desabilitado' else 'null'
                uid = sql(f"insert into usuarios(email,display_name,password_hash,platform_role,disabled_at) values('{name}-{nonce}@example.invalid','Fixture','invalido','{role}',{disabled}) returning id")
                expiry = "now()-interval '1 minute'" if name == 'sessao_expirada' else "now()+interval '1 hour'"
                revoked = 'now()' if name == 'sessao_revogada' else 'null'
                sql(f"insert into sessoes(user_id,access_token_hash,refresh_token_hash,access_expires_at,refresh_expires_at,revoked_at) values('{uid}','{sha(tokens[name])}','{sha('refresh-'+tokens[name])}',{expiry},now()+interval '1 day',{revoked})")
            # Credenciais validas de outra classe nao podem autenticar a rota.
            classes = {'TokenTenant':'tenant', 'ChaveERP':'erp', 'Superadmin':'admin',
                       'Sessao':'usuario', 'Licencas':'licenca', 'WebhookAsaas':'webhook'}
            for route, item in policy.items():
                sec = item['security']
                if not sec:
                    continue
                method, path = route.split(' ', 1)
                for kind, token in classes.items():
                    if kind == sec or {kind, sec} == {'Superadmin', 'Sessao'}:
                        continue
                    check(method, path, item['body'], token, 401)
                if sec == 'TokenTenant':
                    check(method, path, item['body'], 'revogado', 401)
                    check(method, path, item['body'], 'sem_escopo', 403)
                if sec == 'ChaveERP':
                    for token in ['erp_expirado', 'erp_revogado', 'erp_sem_escopo']:
                        check(method, path, item['body'], token, 401)
                if sec in ('Superadmin', 'Sessao'):
                    for token in ['desabilitado', 'sessao_expirada', 'sessao_revogada']:
                        check(method, path, item['body'], token, 401)
                if sec == 'Superadmin':
                    check(method, path, item['body'], 'usuario', 403)
            # Controle positivo: validacao nao pode simplesmente negar tudo.
            internal = check('GET', '/admin/documentacao', None, 'admin', 200)
            assert '/admin/erps' in internal['paths']
            code, _ = request(BASE, 'GET', '/admin/documentacao?token='+tokens['admin'])
            assert code == 401, 'Token em parametro concedeu acesso ao contrato interno'
            assert check('GET', '/v1/assinatura', None, 'tenant', 200)['id_empresa'] == companies[0]
            assert check('GET', '/v1/assinatura', None, 'outro', 200)['id_empresa'] == companies[1]
            assert check('GET', '/v1/planos', None, 'tenant', 200)['itens']
            check('POST', '/admin/erps', {'razao_social': 'Fixture '+nonce, 'rotulo_chave':'Fixture'}, 'admin', 201)
            # Controle positivo do bootstrap via modulo: onboarding precisa KMS/A1,
            # recursos externos que este teste isolado deliberadamente nao usa.
            check('PUT', '/v1/empresas/00000000-0000-4000-8000-000000000000/modulos/monitoramento',
                  {'situacao':'suspenso'}, 'erp', 404)
            check('POST', '/webhooks/asaas', {}, 'webhook', 422, webhook=True)
            check('PUT', '/admin/licencas/empresas/00000000-0000-4000-8000-000000000000',
                  {'situacao':'restrito','versao':1,'referencia':'fixture'}, 'licenca', 404)
            doc = sql(f"insert into documentos(company_id,access_key,document_type,status) values('{companies[0]}','{uuid.uuid4().int % (10**44):044d}','NFe','located') returning id")
            check('GET', '/v1/documentos/'+doc+'/xml', None, 'outro', 404)
            assert all(d['id_documento'] != doc for d in check('GET', '/v1/documentos', None, 'outro', 200)['itens'])
            assert any(d['id_documento'] == doc for d in check('GET', '/v1/documentos', None, 'tenant', 200)['itens'])
            charge = sql(f"insert into cobrancas(company_id,plano_codigo,ambiente,chave_idempotencia,meses,valor_centavos,situacao) values('{companies[0]}','mensal','sandbox','{nonce}',1,4990,'cancelada') returning id")
            check('GET', '/v1/cobrancas/'+charge, None, 'outro', 404)
            check('DELETE', '/v1/cobrancas/'+charge, None, 'outro', 404)
            print(f'OK integracao: {count} verificacoes de classe, escopo, revogacao, expiracao, usuario desabilitado e isolamento')
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)


if __name__ == '__main__':
    run()
