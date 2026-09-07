# Operacao Ubuntu

API e worker sao binarios Linux64 Delphi e rodam nativamente pelo systemd. O
PostgreSQL fica na VPS de dados pela WireGuard. Loki, Grafana e o gateway de
logs rodam em Docker Compose na VPS de logs.

O instalador recebe um pacote criado por `scripts/package-linux.sh`, valida
`SHA256SUMS`, cria uma release imutavel em `/opt/fisconexa/releases`, troca o
link `current`, instala as units e espera ate 90 segundos pelo health check. Se
a API nao ficar saudavel, restaura o binario anterior. O estado do timer do
worker e preservado durante o deploy.

O timer inicia uma tarefa do worker dez segundos depois do termino da anterior
e nunca sobrepoe a mesma unit. A execucao consulta primeiro a elegibilidade no
PostgreSQL; `next_check_at`, lease e bloqueio 656 impedem chamada antecipada.

`/etc/fisconexa/fisconexa.env` contem segredos e deve ficar `0600`. A versao e
gerada pelo instalador em `/etc/fisconexa/version.env`. Certificados A1 ficam
cifrados no banco; nenhum PFX e gravado no arquivo de ambiente.

Comandos operacionais:

```bash
systemctl status fisconexa-api fisconexa-worker.timer alloy caddy
journalctl -u fisconexa-api -u fisconexa-worker
curl -fsS http://127.0.0.1:9000/health
```

As configuracoes complementares ficam em `deploy/caddy`, `deploy/alloy`,
`deploy/logging` e `deploy/postgres`.
