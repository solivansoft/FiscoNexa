"""Projecao publica explicita; contrato completo fica fora da pasta publicada."""
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PUBLIC_PATHS = {
    '/health', '/v1/empresas', '/v1/empresas/{id_empresa}/modulos/monitoramento',
    '/v1/monitoramento', '/v1/documentos', '/v1/documentos/{id_documento}/xml',
    '/v1/assinatura', '/v1/planos', '/v1/cobrancas', '/v1/cobrancas/{id_cobranca}',
}


def project(internal):
    result = copy.deepcopy(internal)
    result['paths'] = {path: op for path, op in result['paths'].items() if path in PUBLIC_PATHS}
    tags = {tag for item in result['paths'].values() for op in item.values() for tag in op['tags']}
    result['tags'] = [tag for tag in result['tags'] if tag['name'] in tags]
    schemes = {name for item in result['paths'].values() for op in item.values()
               for security in op['security'] for name in security}
    result['components']['securitySchemes'] = {name: value for name, value in
        result['components']['securitySchemes'].items() if name in schemes}
    needed = set()

    def visit(value):
        if isinstance(value, dict):
            ref = value.get('$ref', '')
            if ref.startswith('#/components/schemas/'):
                name = ref.rsplit('/', 1)[1]
                if name not in needed:
                    needed.add(name)
                    visit(internal['components']['schemas'][name])
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(result['paths'])
    result['components']['schemas'] = {name: value for name, value in
        result['components']['schemas'].items() if name in needed}
    return result


if __name__ == '__main__':
    internal = json.loads((ROOT / 'docs/openapi-interno.json').read_text(encoding='utf-8'))
    (ROOT / 'docs/api/openapi.json').write_text(
        json.dumps(project(internal), ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
