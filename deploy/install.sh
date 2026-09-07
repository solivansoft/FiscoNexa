#!/usr/bin/env bash
set -euo pipefail
[[ $EUID = 0 ]] || { echo 'Execute como root.' >&2; exit 1; }
origem=$(cd -- "$(dirname -- "$0")/.." && pwd)
versao=$(cat "$origem/VERSION")
[[ "$versao" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,60}$ ]] || exit 2
(cd "$origem" && sha256sum -c SHA256SUMS >/dev/null)
test -s /etc/fisconexa/fisconexa.env || { echo 'Configure /etc/fisconexa/fisconexa.env primeiro.' >&2; exit 1; }
destino="/opt/fisconexa/releases/$versao"
test ! -e "$destino" || { echo 'Release ja instalada.' >&2; exit 1; }
id fisconexa >/dev/null 2>&1 || useradd --system --home /opt/fisconexa --shell /usr/sbin/nologin fisconexa
install -d -m 0750 -o fisconexa -g fisconexa /var/log/fisconexa
if id alloy >/dev/null 2>&1; then
  usermod -aG fisconexa alloy
fi
install -d -m 0755 /opt/fisconexa/releases
chmod 600 /etc/fisconexa/fisconexa.env
printf 'FISCONEXA_VERSION=%s\n' "$versao" > /etc/fisconexa/version.env
chown root:root /etc/fisconexa/version.env
chmod 0644 /etc/fisconexa/version.env
cp -a "$origem" "$destino"
chown -R root:root "$destino"
chmod -R go-w "$destino"
anterior=''
if [[ -L /opt/fisconexa/current ]]; then
  candidato=$(readlink -f /opt/fisconexa/current || true)
  if [[ -n "$candidato" && "$candidato" != /opt/fisconexa/current && -d "$candidato" ]]; then
    anterior=$candidato
  fi
fi
worker_timer_ativo=false
if systemctl is-active --quiet fisconexa-worker.timer; then
  worker_timer_ativo=true
fi
systemctl stop fisconexa-worker.timer fisconexa-worker.service fisconexa-api.service 2>/dev/null || true
ln -s "$destino" /opt/fisconexa/current.next
mv -Tf /opt/fisconexa/current.next /opt/fisconexa/current
install -m 0644 "$destino"/deploy/systemd/* /etc/systemd/system/
systemctl daemon-reload
systemctl enable fisconexa-api.service fisconexa-worker.timer
systemctl restart fisconexa-api.service
saudavel=false
for tentativa in $(seq 1 90); do
  if curl -fsS http://127.0.0.1:9000/saude >/dev/null; then saudavel=true; break; fi
  sleep 1
done
if [[ "$saudavel" != true ]]; then
  systemctl stop fisconexa-api.service
  if [[ -n "$anterior" && -d "$anterior" ]]; then
    ln -s "$anterior" /opt/fisconexa/current.next
    mv -Tf /opt/fisconexa/current.next /opt/fisconexa/current
    systemctl start fisconexa-api.service
    if [[ "$worker_timer_ativo" = true ]]; then
      systemctl start fisconexa-worker.timer
    fi
  else
    rm -f /opt/fisconexa/current
  fi
  echo 'Nova API falhou. Verifique logs; rollback de binario nao desfaz schema.' >&2
  exit 1
fi
if [[ "$worker_timer_ativo" = true ]]; then
  systemctl start fisconexa-worker.timer
fi
# A ativacao fiscal e separada: validar restauracao antes de iniciar o timer.
echo 'API instalada. Apos validar a base: systemctl start fisconexa-worker.timer'
