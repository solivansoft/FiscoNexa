"""Publica assets locais da documentacao via SSH e recarrega somente Caddy.

Uso: python scripts/deploy-api-docs.py fisconexa.vps
Exige o gate OpenAPI instalado. Preserva os demais sites e salva backup do Caddy.
"""
import hashlib
from pathlib import Path
import re
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    host = sys.argv[1]
    assert re.fullmatch(r'[a-zA-Z0-9.-]+', host), 'Alias SSH invalido'
    subprocess.run([sys.executable, str(ROOT / 'tests/test_api_contract.py')], check=True)
    archive = ROOT / 'build/api-docs.tar.gz'
    with tarfile.open(archive, 'w:gz') as tar:
        for file in sorted((ROOT / 'docs/api').iterdir()):
            tar.add(file, arcname='portal/' + file.name)
        tar.add(ROOT / 'deploy/caddy/docs.Caddyfile', arcname='docs.Caddyfile')
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    remote = '/tmp/fisconexa-docs-' + digest + '.tar.gz'
    subprocess.run(['scp', str(archive), host + ':' + remote], check=True)
    script = r'''
import hashlib, pathlib, tarfile, subprocess, os, time
digest = '__DIGEST__'
archive = pathlib.Path('/tmp/fisconexa-docs-' + digest + '.tar.gz')
assert hashlib.sha256(archive.read_bytes()).hexdigest() == digest
base = pathlib.Path('/var/www/fisconexa-api-docs')
release = base / 'releases' / digest
release.mkdir(parents=True, exist_ok=False)
with tarfile.open(archive) as tar:
    tar.extractall(release, filter='data')
for directory in [base, base / 'releases', release, release / 'portal']:
    directory.chmod(0o755)
for file in (release / 'portal').iterdir():
    file.chmod(0o644)
config = pathlib.Path('/etc/caddy/Caddyfile')
snippet = pathlib.Path('/etc/caddy/fisconexa-docs.caddy')
original = config.read_text()
oldsnippet = snippet.read_bytes() if snippet.exists() else None
current = base / 'current'
previous = os.readlink(current) if current.is_symlink() else None
assert not current.exists() or current.is_symlink()
candidate = original
if 'import /etc/caddy/fisconexa-docs.caddy' not in candidate:
    for port in (9000, 9001):
        needle = '  reverse_proxy 127.0.0.1:' + str(port)
        assert candidate.count(needle) == 1, 'Config Caddy inesperada; revisar manualmente'
        candidate = candidate.replace(needle, '  import /etc/caddy/fisconexa-docs.caddy\n  handle {\n  '+needle+'\n  }')
backup = pathlib.Path('/etc/caddy/Caddyfile.pre-docs-' + str(time.time_ns()))
backup.write_text(original)
backup.chmod(0o600)
try:
    snippet.write_bytes((release / 'docs.Caddyfile').read_bytes())
    snippet.chmod(0o644)
    config.write_text(candidate)
    subprocess.run(['caddy','validate','--config',str(config)], check=True)
    os.symlink(str(release / 'portal'), str(base / 'current.next'))
    os.replace(base / 'current.next', current)
    subprocess.run(['systemctl','reload','caddy'], check=True)
except Exception:
    config.write_text(original)
    if oldsnippet is None:
        snippet.unlink(missing_ok=True)
    else:
        snippet.write_bytes(oldsnippet)
    if previous:
        os.symlink(previous, str(base / 'rollback.next'))
        os.replace(base / 'rollback.next', current)
    elif current.is_symlink():
        current.unlink()
    subprocess.run(['systemctl','reload','caddy'], check=False)
    raise
print('Portal publicado: ' + str(release / 'portal'))
'''.replace('__DIGEST__', digest)
    subprocess.run(['ssh', host, 'python3 -'], input=script, text=True, check=True)


if __name__ == '__main__':
    main()
