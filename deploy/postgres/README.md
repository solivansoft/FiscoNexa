# Backup PostgreSQL

Instale `backup.sh` como `/usr/local/sbin/fisconexa-postgres-backup`, copie as
units para `/etc/systemd/system` e configure `/etc/default/fisconexa-backup`:

```text
DATABASES="fisconexa academy"
BACKUP_DIR=/var/backups/postgresql
RETENTION_DAYS=7
```

O timer gera dumps custom atomicamente, valida o catalogo com `pg_restore` e
remove arquivos antigos. Os arquivos ficam `0600`, acessiveis somente por root.
Uma copia externa ou snapshot do provedor continua necessaria para perda total
da VPS.
# Views de observabilidade

O Grafana consulta somente as views seguras do schema `observabilidade`. Na VPS
de dados, copie `observabilidade.sql` e `configurar-observabilidade.sh` para o
mesmo diretorio e execute:

```bash
sudo GRAFANA_FISCONEXA_DB_PASSWORD='senha-forte' \
  ./configurar-observabilidade.sh
```

O script cria ou atualiza as views, configura o usuario `grafana_fisconexa` e
restringe sua autenticacao ao endereco WireGuard `10.77.0.3`. A senha tambem
deve ser configurada na stack de logs, sem ser adicionada ao Git.
