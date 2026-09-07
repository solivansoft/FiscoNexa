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
