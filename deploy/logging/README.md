# Central de logs

Loki, Grafana e Caddy rodam por Docker Compose. O modo inicial fica restrito a
WireGuard: `LOGS_ADDRESS`, `LOGS_PUBLIC_URL` e `LOGS_BIND_IP` usam o endereco
privado da VPS. O firewall nao publica 80, 443, 3000 ou 3100 na internet.

Para publicar HTTPS depois, aponte um dominio para a VPS, use o dominio em
`LOGS_ADDRESS`, a URL HTTPS em `LOGS_PUBLIC_URL`, mude `LOGS_BIND_IP` para
`0.0.0.0` e libere somente 80/443 no firewall. Loki nunca e exposto diretamente;
cada projeto recebe um caminho e uma credencial pelo `adicionar-projeto.sh`.

O Grafana usa a mesma entrada do Caddy. No modo privado, acesse
`http://10.77.0.3/` a partir de um computador conectado a WireGuard.
