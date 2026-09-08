"""Gate independente: inventario Horse, OpenAPI e autenticacao HTTP negativa.

Sem --url: validacao estatica (CI/build). Com --url: todas as rotas protegidas
recebem corpos de fixture, sem credencial e com credenciais invalidas.
Nunca le credenciais reais nem segue redirecionamentos.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import unittest
from unittest.mock import patch
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
PUBLIC = {('GET', '/health'), ('POST', '/auth/login'),
          ('POST', '/auth/refresh')}
METHODS = {'get', 'post', 'put', 'delete', 'patch', 'head', 'options'}


def inventory():
    result = set()
    for file in (ROOT / 'src/api').glob('*.pas'):
        source = file.read_text(encoding='utf-8-sig')
        # Comentarios nao contam como registro; manter declaracoes literais.
        source = re.sub(r'\(\*.*?\*\)|\{.*?\}|//[^\n]*', '', source, flags=re.S)
        calls = re.findall(r'\bTHorse\.(Get|Post|Put|Delete|Patch|Head|Options)\s*\(', source, re.I)
        routes = re.findall(r"\bTHorse\.(Get|Post|Put|Delete|Patch|Head|Options)\s*\(\s*'([^']+)'", source, re.I)
        assert len(calls) == len(routes), f'{file.name}: registro dinamico sem cobertura'
        assert not re.search(r'\bTHorse\.(Group|Route|All)\s*\(', source, re.I), 'Novo formato de roteamento exige adaptar o inventario'
        for method, path in routes:
            key = (method.upper(), re.sub(r':(\w+)', r'{\1}', path))
            assert key not in result, f'Rota duplicada: {key}'
            result.add(key)
    assert result, 'Nenhuma rota encontrada: instrumento invalido'
    return result


def contract():
    from public_api_spec import project
    spec = json.loads((ROOT / 'docs/openapi-interno.json').read_text(encoding='utf-8'))
    public = json.loads((ROOT / 'docs/api/openapi.json').read_text(encoding='utf-8'))
    assert public == project(spec), 'Contrato publico divergente; execute scripts/public_api_spec.py'
    assert not any(path.startswith(('/admin', '/auth', '/webhooks')) for path in public['paths'])
    assert not (ROOT / 'docs/api/openapi-interno.json').exists(), 'Contrato interno dentro da pasta publica'
    assets = {'index.html', 'openapi.json', 'iniciar.js', 'portal.css', 'scalar.js',
              'scalar-LICENSE.txt', 'scalar-version.json', 'interno.html', 'interno.js'}
    assert {p.name for p in (ROOT / 'docs/api').iterdir()} == assets, 'Arquivo publico novo exige revisao da publicacao'
    from openapi_spec_validator import validate
    validate(public)
    policy = json.loads((ROOT / 'tests/api-access-policy.json').read_text(encoding='utf-8'))
    ops = {(method.upper(), path): op for path, item in spec['paths'].items()
           for method, op in item.items() if method in METHODS}
    keys = {tuple(k.split(' ', 1)) for k in policy}
    actual = inventory()
    assert actual == set(ops) == keys, f'Inventarios divergentes: Horse/OpenAPI={actual ^ set(ops)}; Horse/politica={actual ^ keys}'
    ids = []
    for key, op in ops.items():
        security = policy[' '.join(key)]['security']
        expected = [{security: []}] if security else []
        assert op.get('security') == expected, f'{key}: politica divergente'
        assert (not security) == (key in PUBLIC), f'{key}: exposicao publica nao autorizada'
        if security:
            assert security in spec['components']['securitySchemes']
            assert '401' in op['responses'], f'{key}: falta documentar 401'
        assert op.get('summary') and op.get('responses'), f'{key}: contrato incompleto'
        ids.append(op['operationId'])
        names = set(re.findall(r'\{(\w+)\}', key[1]))
        params = {p['name'] for p in op.get('parameters', []) if p['in'] == 'path' and p.get('required')}
        assert names == params, f'{key}: parametros de caminho divergentes'
    assert len(ids) == len(set(ids)), 'operationId duplicado'
    version = json.loads((ROOT / 'docs/api/scalar-version.json').read_text())
    assert hashlib.sha256((ROOT / 'docs/api/scalar.js').read_bytes()).hexdigest() == version['sha256'], 'Asset Scalar divergente'
    init = (ROOT / 'docs/api/iniciar.js').read_text(encoding='utf-8')
    assert 'persistAuth: false' in init and 'proxyUrl' not in init, 'Portal nao deve persistir tokens nem usar proxy externo'
    return spec, policy


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def request(base, method, path, body=None, headers=None):
    path = re.sub(r'\{\w+\}', '00000000-0000-4000-8000-000000000000', path)
    hdr = {'Content-Type': 'application/json', 'Idempotency-Key': 'guardrail-negativo-0001'}
    hdr.update(headers or {})
    req = urllib.request.Request(base.rstrip('/') + path,
        data=None if body is None else json.dumps(body).encode(), headers=hdr, method=method)
    try:
        with urllib.request.build_opener(NoRedirect).open(req, timeout=20) as res:
            return res.status, res.read()
    except urllib.error.HTTPError as res:
        return res.code, res.read()


def negative_http(base, policy):
    count = 0
    for route, entry in policy.items():
        method, path = route.split(' ', 1)
        security = entry['security']
        if not security:
            continue
        for label, hdr in [
            ('ausente', {}),
            ('invalida', {'Authorization': 'Bearer guardrail-invalido', 'asaas-access-token': 'guardrail-invalido'}),
            ('esquema-incorreto', {'Authorization': 'Basic guardrail-invalido'}),
        ]:
            code, _ = request(base, method, path, entry['body'], hdr)
            assert code == 401, f'{route} ({label}): esperado 401; recebido {code}'
            count += 1
    for path, body in [('/auth/login', {'email': 'inexistente-guardrail@example.invalid', 'senha': 'invalida'}),
                       ('/auth/refresh', {'token_renovacao': 'invalido'})]:
        code, _ = request(base, 'POST', path, body)
        assert code == 401, f'{path}: credencial no corpo aceita ({code})'
        count += 1
    code, data = request(base, 'GET', '/health')
    assert code == 200 and json.loads(data)['situacao'] == 'disponivel'
    print(f'OK HTTP: {count} rejeicoes de autenticacao e health publico')


class ContractTests(unittest.TestCase):
    def test_rotas_contrato_e_politica(self):
        spec, _ = contract()
        from openapi_spec_validator import validate
        validate(spec)

    def test_gate_recusa_rota_exposta_ou_ausente(self):
        policy = {'GET /v1/documentos': {'security': 'TokenTenant', 'body': None}}
        for status in (200, 202, 402, 404, 500):
            with self.subTest(status=status), patch(__name__ + '.request', return_value=(status, b'')):
                with self.assertRaises(AssertionError):
                    negative_http('http://127.0.0.1', policy)

    def test_projecao_nao_publica_rota_administrativa_nova(self):
        from public_api_spec import project
        spec, _ = contract()
        spec['paths']['/admin/nova-rota'] = {'get': {'tags': ['Administração'], 'security': [{'Superadmin': []}]}}
        assert '/admin/nova-rota' not in project(spec)['paths']


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--url', help='API em execucao; testes sem credenciais reais')
    parser.add_argument('--release-policy', type=Path, help='Matriz empacotada; executa somente HTTP sem dependencias externas')
    args = parser.parse_args()
    if args.release_policy:
        assert args.url, '--release-policy exige --url'
        negative_http(args.url, json.loads(args.release_policy.read_text(encoding='utf-8')))
        raise SystemExit(0)
    spec, policy = contract()
    from openapi_spec_validator import validate
    validate(spec)
    print(f'OK OpenAPI, integridade Scalar e politica: {len(policy)} operacoes')
    if args.url:
        negative_http(args.url, policy)
