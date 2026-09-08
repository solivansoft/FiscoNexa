"""Cancelamento repetido e estorno integral de renovacao no Asaas Sandbox."""
import importlib.util
import json
import time
import sys
import uuid
from pathlib import Path

spec = importlib.util.spec_from_file_location('smoke', Path(__file__).with_name('smoke-assinaturas-vps.py'))
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)
state = json.loads((smoke.CREDENTIALS/'fisconexa-sandbox-spike.json').read_text())
h = {'Authorization':'Bearer '+state['token']}
env = dict(l.split('=',1) for l in (smoke.CREDENTIALS/'asaas-sandbox.env').read_text(encoding='utf-8-sig').splitlines() if '=' in l and not l.startswith('#'))
assert env['ASAAS_AMBIENTE']=='sandbox'
checkpoint=Path('build/assinaturas/estorno-vps.json')

def verificar_estorno(remote, original):
    for _ in range(24):
        c=smoke.request(smoke.BASE+'/v1/assinatura',headers=h)
        processed=smoke.sql(f"select count(*) from webhooks_cobranca where pagamento_id='{remote}' and tipo='PAYMENT_REFUNDED' and processado_em is not null;")
        if c['pago_ate']==original and processed!='0':
            assert c['situacao']=='ativa'
            print('OK estorno real sandbox remove apenas renovacao anual e preserva mensalidade anterior',flush=True)
            return
        payment=smoke.request('https://api-sandbox.asaas.com/v3/payments/'+remote,headers={'access_token':env['ASAAS_API_TOKEN']})
        if any(r.get('status')=='AWAITING_CRITICAL_ACTION_AUTHORIZATION' for r in payment.get('refunds',[]) or []):
            print('PENDENTE autorizacao de acao critica no Asaas Sandbox. Apos autorizar, execute com --retomar.',flush=True)
            sys.exit(2)
        time.sleep(5)
    raise RuntimeError('Estorno nao processado no prazo')

if '--retomar' in sys.argv:
    saved=json.loads(checkpoint.read_text())
    verificar_estorno(saved['remote'],saved['original'])
    sys.exit(0)

original = smoke.request(smoke.BASE+'/v1/assinatura',headers=h)['pago_ate']
key='cancelar-'+str(uuid.uuid4())
c=smoke.request(smoke.BASE+'/v1/cobrancas','POST',{'plano_codigo':'anual'},dict(h,**{'Idempotency-Key':key}))
ident=str(uuid.UUID(c['id_cobranca']))
for _ in range(2):
    c=smoke.request(smoke.BASE+'/v1/cobrancas/'+ident,'DELETE',headers=h)
    assert c['situacao']=='cancelada' and c['assinatura']['pago_ate']==original
print('OK cancelar duas vezes preserva periodo pago',flush=True)
key='renovar-'+str(uuid.uuid4())
c=smoke.request(smoke.BASE+'/v1/cobrancas','POST',{'plano_codigo':'anual'},dict(h,**{'Idempotency-Key':key}))
ident=str(uuid.UUID(c['id_cobranca']))
remote=smoke.sql(f"select asaas_id from cobrancas where id='{ident}';")
base='https://api-sandbox.asaas.com/v3'
auth={'access_token':env['ASAAS_API_TOKEN']}
smoke.request(base+'/sandbox/payment/'+remote+'/confirm','POST',{},auth)
for _ in range(24):
    c=smoke.request(smoke.BASE+'/v1/assinatura',headers=h)
    if c['pago_ate']!=original: break
    time.sleep(5)
else: raise RuntimeError('Renovacao nao processada')
print('OK renovacao anual concedida apos callback',flush=True)
smoke.request(base+'/payments/'+remote+'/refund','POST',{},auth)
checkpoint.parent.mkdir(parents=True,exist_ok=True)
checkpoint.write_text(json.dumps({'remote':remote,'original':original}),encoding='utf-8')
verificar_estorno(remote,original)
