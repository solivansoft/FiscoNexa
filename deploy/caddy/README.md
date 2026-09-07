# Borda HTTPS

O Caddy roda nativamente pelo systemd na VPS da aplicacao. A API publica em
`api.fisconexa.com.br` e encaminha para a porta local 9000.

A landing page fica em `/var/www/fisconexa`. Quando os registros DNS do dominio
raiz e de `www` apontarem para a VPS, acrescente o conteudo de
`landing.Caddyfile.example` ao Caddyfile ativo. Manter esse bloco fora da
configuracao antes da troca de DNS evita tentativas ACME que nunca podem ser
validadas.

Valide antes de recarregar:

```bash
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy
```
