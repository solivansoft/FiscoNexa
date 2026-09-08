"""Smoke exclusivamente local + Asaas Sandbox. Nenhum pagamento real."""
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import urllib.request
import urllib.error
import uuid

BASE = 'http://127.0.0.1:9000'
TOKEN = 'assinaturas-integracao-teste-local-001'
OTHER = 'assinaturas-integracao-teste-local-002'
CONTAINER = 'fisconexa-assinaturas-teste'

def sql(query):
    r = subprocess.run(['docker','exec','-i',CONTAINER,'psql','-U','assinaturas_teste',
                        '-d','fisconexa_assinaturas_teste','-At','-v','ON_ERROR_STOP=1'],
                       input=query, text=True, capture_output=True, check=True)
    return r.stdout.strip().splitlines()[0] if r.stdout.strip() else ''

def request(path, method='GET', body=None, token=TOKEN, key=None, expected=200, headers=None):
    h={'Content-Type':'application/json','Authorization':'Bearer '+token}
    if key: h['Idempotency-Key']=key
    if headers: h.update(headers)
    data=None if body is None else json.dumps(body).encode()
    req=urllib.request.Request(BASE+path,data=data,headers=h,method=method)
    try:
        with urllib.request.urlopen(req,timeout=65) as r: status=r.status; text=r.read()
    except urllib.error.HTTPError as e: status=e.code; text=e.read()
    assert status==expected, f'{method} {path}: HTTP {status}: {text[:500]!r}'
    return json.loads(text) if text else {}

def setup():
    # CNPJs sintaticos de fixture, somente no banco dedicado e no sandbox.
    for cnpj,token,name in [('11222333000181',TOKEN,'FiscoNexa TESTE sandbox'),('11444777000161',OTHER,'FiscoNexa OUTRO TESTE')]:
        company=sql(f"insert into empresas(cnpj,state,legal_name) values('{cnpj}','PA','{name}') on conflict(cnpj) do update set legal_name=excluded.legal_name returning id;")
        sql(f"insert into assinaturas(company_id) values('{company}') on conflict do nothing;")
        sql(f"insert into integracoes(company_id,display_name,api_token_hash) values('{company}','Smoke assinatura',encode(digest('{token}','sha256'),'hex')) on conflict(api_token_hash) do nothing;")
    request('/v1/assinatura', token='invalido', expected=401)
    assert request('/v1/assinatura')['situacao'] in ('trial','ativa')
    plans=request('/v1/planos')['itens']
    assert [p['valor_centavos'] for p in plans]==[4990,14970,49900]
    request('/webhooks/asaas','POST',{},expected=401)
    print('OK autenticacao, trial, planos e webhook sem segredo recusado')

def create():
    key='smoke-'+str(uuid.uuid4())
    charge=request('/v1/cobrancas','POST',{'plano_codigo':'mensal'},key=key)
    assert charge['pix']['copia_cola'] and charge['pix']['imagem_base64']
    repeat=request('/v1/cobrancas','POST',{'plano_codigo':'mensal'},key=key)
    alias_key='alias-'+str(uuid.uuid4())
    alias=request('/v1/cobrancas','POST',{'plano_codigo':'mensal'},key=alias_key)
    assert charge['id_cobranca']==repeat['id_cobranca']==alias['id_cobranca']
    request('/v1/cobrancas/'+charge['id_cobranca'],token=OTHER,expected=404)
    request('/v1/cobrancas','POST',{'plano_codigo':'anual'},key=key,expected=409)
    state={'id':charge['id_cobranca'],'key':key,'alias':alias_key,'trial_termina_em':charge['assinatura']['trial_termina_em']}
    Path('build/assinaturas/sandbox-state.json').write_text(json.dumps(state),encoding='utf-8')
    print('OK Pix real sandbox, repeticao, duas chaves reutilizam cobranca, isolamento e conflito de plano')
    return state

def asaas(path):
    env={}
    for line in Path('D:/Hostinger/credenciais/asaas-sandbox.env').read_text(encoding='utf-8-sig').splitlines():
        if '=' in line and not line.startswith('#'):
            k,v=line.split('=',1);env[k.strip()]=v.strip()
    assert env['ASAAS_AMBIENTE']=='sandbox'
    req=urllib.request.Request('https://api-sandbox.asaas.com/v3'+path,data=b'{}',
       headers={'access_token':env['ASAAS_API_TOKEN'],'Content-Type':'application/json','User-Agent':'FiscoNexa-SandboxSmoke'},method='POST')
    try:
        with urllib.request.urlopen(req,timeout=30) as r: return json.load(r)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f'Asaas sandbox HTTP {e.code}: '+e.read().decode()[:500]) from None

def reconcile():
    env=dict(os.environ,FISCONEXA_DB_HOST='127.0.0.1',FISCONEXA_DB_PORT='5438',
      FISCONEXA_DB_NAME='fisconexa_assinaturas_teste',FISCONEXA_DB_USER='assinaturas_teste',
      FISCONEXA_DB_PASSWORD='senha_apenas_teste_local',FISCONEXA_ENVIRONMENT='homologacao')
    for line in Path('D:/Hostinger/credenciais/asaas-sandbox.env').read_text(encoding='utf-8-sig').splitlines():
        if '=' in line and not line.startswith('#'):
            k,v=line.split('=',1);env[k.strip()]=v.strip()
    subprocess.run(['bin/win64/FiscoNexa.Api.exe','--reconciliar-cobrancas'],env=env,check=True,capture_output=True,timeout=180)

def confirm(state):
    remote=sql(f"select asaas_id from cobrancas where id='{state['id']}';")
    asaas('/sandbox/payment/'+remote+'/confirm')
    event={'id':'smoke-event-'+state['id'],'event':'PAYMENT_RECEIVED','payment':{'id':remote}}
    h={'asaas-access-token':'segredo-exclusivo-teste-local-2026-09-08'}
    request('/webhooks/asaas','POST',event,headers=h)
    request('/webhooks/asaas','POST',event,headers=h)
    reconcile()
    subscription=request('/v1/assinatura')
    assert subscription['situacao']=='ativa' and subscription['pago_ate']
    paid=subscription['pago_ate']
    again=request('/v1/cobrancas','POST',{'plano_codigo':'mensal'},key=state['alias'])
    assert again['id_cobranca']==state['id'] and again['assinatura']['pago_ate']==paid
    request('/webhooks/asaas','POST',dict(event,event='PAYMENT_PENDING'),headers=h)
    reconcile()
    assert request('/v1/assinatura')['pago_ate']==paid
    assert sql(f"select count(*) from eventos_cobranca where cobranca_id='{state['id']}';")=='1'
    print('OK confirmacao no Asaas, webhook em fila, conciliacao, acesso ativo e replay sem periodo duplicado')

if __name__=='__main__':
    import sys
    if len(sys.argv)>1 and sys.argv[1]=='confirm':
        confirm(json.loads(Path('build/assinaturas/sandbox-state.json').read_text()))
    else:
        setup();state=create();confirm(state)
