# Observabilidade central

Loki, Prometheus, Grafana e Caddy rodam por Docker Compose. O modo inicial fica
restrito a WireGuard: `LOGS_ADDRESS`, `LOGS_PUBLIC_URL` e `LOGS_BIND_IP` usam o
endereco privado da VPS. O firewall nao publica 80, 443, 3000, 9090 ou 3100 na
internet.

Para publicar HTTPS depois, aponte um dominio para a VPS, use o dominio em
`LOGS_ADDRESS`, a URL HTTPS em `LOGS_PUBLIC_URL`, mude `LOGS_BIND_IP` para
`0.0.0.0` e libere somente 80/443 no firewall. Loki nunca e exposto diretamente;
cada projeto recebe um caminho e uma credencial pelo `adicionar-projeto.sh`.

O Grafana usa a mesma entrada do Caddy. No modo privado, acesse
`http://10.77.0.3/` a partir de um computador conectado a WireGuard.

O dashboard `dashboards/fisconexa-operacao.json` acompanha requisicoes e erros
HTTP, latencia P95, trabalho do worker, volume por servico e logs recentes. Ele
usa o datasource provisionado `logs-fisconexa` e pode ser importado pela API ou
pela interface do Grafana.

Os JSONs da pasta `dashboards` tambem sao provisionados automaticamente no
Grafana. A pasta e os dashboards sobrevivem a reinicializacoes e podem ser
recriados junto com o restante da stack.

O Prometheus conserva ate 15 dias ou 5 GB de metricas, o que ocorrer primeiro,
e consulta a cada 15 segundos os Node Exporters ligados somente aos enderecos
WireGuard. O dashboard `dashboards/saude-vps.json` mostra disponibilidade, CPU,
memoria, disco, swap, carga, rede, I/O e uptime das tres VPS.

O dashboard `dashboards/fisconexa-tenants-fiscal.json` apresenta tenants,
licencas, certificados, monitoramento e documentos. O datasource PostgreSQL
usa o usuario `grafana_fisconexa`, que possui acesso somente as views do schema
`observabilidade`. Informe sua senha em
`GRAFANA_FISCONEXA_DB_PASSWORD`; ela nao deve ser versionada.

| VPS | Endpoint privado |
| --- | --- |
| dados | `10.77.0.1:9100` |
| fisconexa | `10.77.0.2:9101` |
| logs | `10.77.0.3:9100` |

Para preparar uma VPS nova, execute `instalar-node-exporter.sh` como root com o
endpoint WireGuard correspondente. Se o UFW estiver ativo, permita essa porta
somente no `wg0` e somente a partir de `10.77.0.3`.
