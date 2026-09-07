#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
projeto=${1:?Uso: adicionar-projeto.sh nome-do-projeto}
[[ "$projeto" =~ ^[a-z][a-z0-9-]{0,39}$ ]] || exit 2
[[ ! -e "projects/$projeto.caddy" ]] || { echo 'Projeto ja cadastrado.' >&2; exit 1; }
umask 077
mkdir -p projects datasources credenciais
senha=$(openssl rand -hex 32)
hash=$(docker compose run --rm -T --no-deps gateway caddy hash-password --plaintext "$senha")
cat > "projects/$projeto.caddy" <<EOF
@envio_$projeto {
  path /ingest/$projeto
  method POST
}
handle @envio_$projeto {
  basic_auth {
    $projeto $hash
  }
  rewrite * /loki/api/v1/push
  reverse_proxy loki:3100 {
    header_up X-Scope-OrgID $projeto
  }
}
EOF
cat > "datasources/$projeto.yaml" <<EOF
apiVersion: 1
datasources:
  - name: Logs - $projeto
    uid: logs-$projeto
    type: loki
    access: proxy
    url: http://loki:3100
    editable: false
    jsonData:
      httpHeaderName1: X-Scope-OrgID
    secureJsonData:
      httpHeaderValue1: $projeto
EOF
printf 'LOKI_USERNAME=%s\nLOKI_PASSWORD=%s\n' "$projeto" "$senha" > "credenciais/$projeto.env"
# Configuracoes sem senha em plaintext precisam ser legiveis pelos containers.
chmod 644 "projects/$projeto.caddy" "datasources/$projeto.yaml"
docker compose run --rm --no-deps gateway caddy validate --config /etc/caddy/Caddyfile
docker compose up -d
docker compose exec -T gateway caddy reload --config /etc/caddy/Caddyfile
docker compose restart grafana
echo "Credencial criada em credenciais/$projeto.env (nao versionar)."
