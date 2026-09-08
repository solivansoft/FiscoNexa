"""Smoke HTTPS + Asaas Sandbox + callback real. Banco exclusivo fisconexa_sandbox."""
import json
import secrets
import subprocess
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

BASE = 'https://sandbox.fisconexa.com.br'
CREDENTIALS = Path('D:/Hostinger/credenciais')

def sql(query):
    p = subprocess.run(['ssh', '-o', 'BatchMode=yes', 'dados.vps',
        'sudo -u postgres psql -d fisconexa_sandbox -At -v ON_ERROR_STOP=1'],
        input=query, text=True, capture_output=True)
    if p.returncode:
        raise RuntimeError('Falha SQL no banco exclusivo sandbox')
    return p.stdout.strip().splitlines()[0] if p.stdout.strip() else ''

def request(url, method='GET', body=None, headers=None, expected=200):
    req = urllib.request.Request(url, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers=dict({'Content-Type': 'application/json', 'User-Agent': 'FiscoNexa-SandboxSmoke'}, **(headers or {})))
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            status, raw = r.status, r.read()
    except urllib.error.HTTPError as e:
        status, raw = e.code, e.read()
    if status != expected:
        raise RuntimeError(f'HTTP {status}, esperado {expected}, em {method} {url.split("?")[0]}')
    return json.loads(raw) if raw else {}

def main():
    env = dict(line.split('=', 1) for line in (CREDENTIALS/'asaas-sandbox.env').read_text(encoding='utf-8-sig').splitlines()
        if '=' in line and not line.startswith('#'))
    assert env['ASAAS_AMBIENTE'] == 'sandbox'
    assert request(BASE+'/health')['situacao'] == 'disponivel'
    request(BASE+'/webhooks/asaas', 'POST', {}, expected=401)
    request(BASE+'/webhooks/asaas', 'POST', {}, headers={'asaas-access-token': env['ASAAS_WEBHOOK_TOKEN']}, expected=422)
    print('OK HTTPS publico e autenticacao do webhook', flush=True)
    statefile = CREDENTIALS/'fisconexa-sandbox-spike.json'
    if statefile.exists():
        state = json.loads(statefile.read_text())
    else:
        state = {'token': secrets.token_hex(32), 'chave': 'vps-'+str(uuid.uuid4())}
        statefile.write_text(json.dumps(state), encoding='utf-8')
    token = state['token']
    assert all(c in '0123456789abcdef' for c in token)
    company = sql("insert into empresas(cnpj,state,legal_name) values('11222333000181','PA','FiscoNexa TESTE VPS SANDBOX') on conflict(cnpj) do update set legal_name=excluded.legal_name returning id;")
    sql(f"insert into assinaturas(company_id) values('{company}') on conflict do nothing;")
    sql(f"insert into integracoes(company_id,display_name,api_token_hash) values('{company}','Spike VPS sandbox',encode(digest('{token}','sha256'),'hex')) on conflict(api_token_hash) do nothing;")
    h = {'Authorization': 'Bearer '+token}
    charge = request(BASE+'/v1/cobrancas', 'POST', {'plano_codigo':'mensal'}, dict(h, **{'Idempotency-Key':state['chave']}))
    ident = str(uuid.UUID(charge['id_cobranca']))
    state['id_cobranca'] = ident
    statefile.write_text(json.dumps(state), encoding='utf-8')
    remote = sql(f"select asaas_id from cobrancas where id='{ident}';")
    if charge['situacao'] != 'recebida':
        assert charge['pix']['copia_cola'] and charge['pix']['imagem_base64']
        request('https://api-sandbox.asaas.com/v3/sandbox/payment/'+remote+'/confirm', 'POST', {}, {'access_token':env['ASAAS_API_TOKEN']})
    print('OK cobranca Pix criada pela API Linux e pagamento confirmado no Asaas Sandbox', flush=True)
    # Nao enviar webhook manual nem consultar cobranca: a concessao deve vir do callback/timer.
    for _ in range(24):
        received = sql(f"select count(*) from webhooks_cobranca where pagamento_id='{remote}' and tipo='PAYMENT_RECEIVED' and processado_em is not null;")
        subscription = request(BASE+'/v1/assinatura', headers=h)
        if received != '0' and subscription['situacao'] == 'ativa':
            paid = subscription['pago_ate']
            repeated = request(BASE+'/v1/cobrancas', 'POST', {'plano_codigo':'mensal'}, dict(h, **{'Idempotency-Key':state['chave']}))
            assert repeated['id_cobranca'] == ident and repeated['assinatura']['pago_ate'] == paid
            print('OK callback real Asaas persistido e processado; assinatura ativa; repeticao nao duplica periodo', flush=True)
            return
        time.sleep(5)
    raise RuntimeError('Callback PAYMENT_RECEIVED ainda nao processado no prazo de 120 segundos')

if __name__ == '__main__':
    main()
