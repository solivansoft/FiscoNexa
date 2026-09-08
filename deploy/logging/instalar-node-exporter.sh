#!/usr/bin/env bash
set -euo pipefail
[[ $EUID = 0 ]] || { echo 'Execute como root.' >&2; exit 1; }
endereco=${1:?Uso: instalar-node-exporter.sh IP_WIREGUARD:PORTA}
[[ "$endereco" =~ ^10\.77\.0\.[0-9]{1,3}:[0-9]{2,5}$ ]] || {
  echo 'Informe um endereco da rede WireGuard 10.77.0.0/24.' >&2
  exit 2
}

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y prometheus-node-exporter
printf 'ARGS="--web.listen-address=%s"\n' "$endereco" \
  > /etc/default/prometheus-node-exporter
systemctl enable prometheus-node-exporter.service
systemctl restart prometheus-node-exporter.service
systemctl is-active --quiet prometheus-node-exporter.service
curl -fsS --max-time 3 "http://$endereco/metrics" >/dev/null
echo "Node Exporter ativo em $endereco."

