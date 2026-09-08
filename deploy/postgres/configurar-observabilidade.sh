#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Execute como root." >&2
  exit 1
fi

: "${GRAFANA_FISCONEXA_DB_PASSWORD:?Defina GRAFANA_FISCONEXA_DB_PASSWORD}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATABASE="${FISCONEXA_DB_NAME:-fisconexa}"
RULE="host ${DATABASE} grafana_fisconexa 10.77.0.3/32 scram-sha-256"

sudo -u postgres psql -v ON_ERROR_STOP=1 -d "${DATABASE}" \
  -f "${SCRIPT_DIR}/observabilidade.sql"

sudo -u postgres psql -v ON_ERROR_STOP=1 -v \
  password="${GRAFANA_FISCONEXA_DB_PASSWORD}" -d postgres <<'SQL'
alter role grafana_fisconexa login password :'password';
SQL

HBA_FILE="$(sudo -u postgres psql -Atd postgres -c 'show hba_file')"
grep -Fqx "${RULE}" "${HBA_FILE}" || printf '%s\n' "${RULE}" >> "${HBA_FILE}"
systemctl reload postgresql

echo "Observabilidade fiscal configurada para acesso somente pela VPS de logs."
