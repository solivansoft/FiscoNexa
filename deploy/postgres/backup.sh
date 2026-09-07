#!/usr/bin/env bash
set -euo pipefail
umask 077

destino=${BACKUP_DIR:-/var/backups/postgresql}
retencao=${RETENTION_DAYS:-7}
bancos=${DATABASES:-fisconexa}
[[ "$retencao" =~ ^[1-9][0-9]{0,2}$ ]] || exit 2
install -d -m 0700 -o root -g root "$destino"

instante=$(date -u +%Y%m%dT%H%M%SZ)
for banco in $bancos; do
  [[ "$banco" =~ ^[a-zA-Z0-9_]+$ ]] || exit 2
  temporario="$destino/.${banco}-${instante}.dump.tmp"
  arquivo="$destino/${banco}-${instante}.dump"
  runuser -u postgres -- pg_dump --format=custom --compress=6 "$banco" \
    > "$temporario"
  pg_restore --list "$temporario" >/dev/null
  chown root:root "$temporario"
  chmod 0600 "$temporario"
  mv "$temporario" "$arquivo"
done

find "$destino" -maxdepth 1 -type f -name '*.dump' \
  -mtime "+$retencao" -delete
