"""Escolha na fatura, QR Pix, recusa/aprovacao de cartao ficticio e callback real."""
import importlib.util
import json
import sys
import time
import uuid
from pathlib import Path

spec=importlib.util.spec_from_file_location('smoke',Path(__file__).with_name('smoke-assinaturas-vps.py'))
s=importlib.util.module_from_spec(spec);spec.loader.exec_module(s)
state=json.loads((s.CREDENTIALS/'fisconexa-sandbox-spike.json').read_text())
env=dict(l.split('=',1) for l in (s.CREDENTIALS/'asaas-sandbox.env').read_text(encoding='utf-8-sig').splitlines() if '=' in l and not l.startswith('#'))
assert env['ASAAS_AMBIENTE']=='sandbox'
h={'Authorization':'Bearer '+state['token']}
auth={'access_token':env['ASAAS_API_TOKEN']}
checkpoint=Path('build/assinaturas/cartao-checkpoint.json')
if '--retomar' in sys.argv:
    saved=json.loads(checkpoint.read_text())
    before,key,ident,remote=(saved[k] for k in ['before','key','ident','remote'])
else:
    before=s.request(s.BASE+'/v1/assinatura',headers=h)['pago_ate']
    key='cartao-'+str(uuid.uuid4())
    c=s.request(s.BASE+'/v1/cobrancas','POST',{'plano_codigo':'mensal'},dict(h,**{'Idempotency-Key':key}))
    assert c['forma_pagamento']=='a_escolher' and not c['pagamento_aprovado']
    assert c['url_pagamento'].startswith('https://sandbox.asaas.com/')
    assert c['pix']['imagem_base64'] and c['pix']['copia_cola']
    ident=str(uuid.UUID(c['id_cobranca']))
    remote=s.sql(f"select asaas_id from cobrancas where id='{ident}';")
    checkpoint.write_text(json.dumps({'before':before,'key':key,'ident':ident,'remote':remote}),encoding='utf-8')
    print('OK mesma cobranca oferece URL da fatura e QR Code Pix',flush=True)
    # Dados exclusivamente ficticios. Nao passam pela API do produto nem sao persistidos.
    body={'creditCard':{'holderName':'TESTE FISCONEXA','number':'5184019740373151','expiryMonth':'12','expiryYear':'2030','ccv':'123'},
          'creditCardHolderInfo':{'name':'TESTE FISCONEXA','email':'sandbox@example.invalid','cpfCnpj':'11222333000181',
                                 'postalCode':'01001000','addressNumber':'1','phone':'11999999999'}}
    url='https://api-sandbox.asaas.com/v3/payments/'+remote+'/payWithCreditCard'
    refused=s.request(url,'POST',body,auth,expected=400)
    codes=[e.get('code') for e in refused.get('errors',[])]
    assert any(e.get('code') in ('invalid_creditCard','invalid_action') and
        'n\u00e3o autorizada' in e.get('description','').lower() for e in refused.get('errors',[])), 'Resposta nao comprova recusa do cartao: '+str(codes)
    assert s.request(s.BASE+'/v1/assinatura',headers=h)['pago_ate']==before
    print('OK cartao ficticio recusado nao concede periodo',flush=True)
    body['creditCard']['number']='4444444444444444'
    paid=s.request(url,'POST',body,auth)
    assert paid['billingType']=='CREDIT_CARD' and paid['status'] in ('CONFIRMED','RECEIVED')
    print('OK Asaas Sandbox aprovou cartao: '+paid['status'],flush=True)
for _ in range(24):
    event=s.sql(f"select count(*) from webhooks_cobranca where pagamento_id='{remote}' and tipo in ('PAYMENT_CONFIRMED','PAYMENT_RECEIVED') and processado_em is not null;")
    subscription=s.request(s.BASE+'/v1/assinatura',headers=h)
    if event!='0' and subscription['pago_ate']!=before: break
    time.sleep(5)
else: raise RuntimeError('Callback do cartao nao processado no prazo')
c=s.request(s.BASE+'/v1/cobrancas/'+ident,headers=h)
assert c['pagamento_aprovado'] and c['forma_pagamento']=='cartao_credito' and 'pix' not in c
assert c['situacao'] in ('confirmada','recebida')
repeat=s.request(s.BASE+'/v1/cobrancas','POST',{'plano_codigo':'mensal'},dict(h,**{'Idempotency-Key':key}))
assert repeat['id_cobranca']==ident and repeat['assinatura']['pago_ate']==subscription['pago_ate']
Path('build/assinaturas/cartao-vps.json').write_text(json.dumps(c,indent=2),encoding='utf-8')
print('OK callback real liberou assinatura; ERP recebe pagamento_aprovado=true; replay nao duplica',flush=True)
s.request('https://api-sandbox.asaas.com/v3/payments/'+remote+'/refund','POST',{},auth)
for _ in range(24):
    sub=s.request(s.BASE+'/v1/assinatura',headers=h)
    event=s.sql(f"select count(*) from webhooks_cobranca where pagamento_id='{remote}' and tipo='PAYMENT_REFUNDED' and processado_em is not null;")
    if event!='0' and sub['pago_ate']==before: break
    time.sleep(5)
else: raise RuntimeError('Estorno do cartao ainda nao concluido')
print('OK estorno real do cartao remove apenas este periodo e preserva assinatura anterior',flush=True)
