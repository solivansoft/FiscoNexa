# Metricas de infraestrutura

Problema: os logs mostram o comportamento da aplicacao, mas nao permitem
antecipar saturacao ou indisponibilidade das VPS; evidencia: Loki possui eventos
da API e do worker, enquanto CPU, memoria, disco, rede e uptime nao eram
coletados; invariante: endpoints de metricas nao ficam acessiveis pela internet
e a observabilidade nao consulta dados fiscais; causa: logs e metricas possuem
modelos de consulta e retencao diferentes; solucao: Prometheus `3.14.0` sem
porta publicada na VPS de logs, Node Exporter ligado aos enderecos WireGuard e
Grafana com datasource e dashboard provisionados; previsao: cada VPS produz uma
serie a cada 15 segundos e falhas ou saturacao aparecem no painel em menos de
um minuto; riscos: crescimento do TSDB e indisponibilidade da propria VPS de
logs, limitados por 15 dias, 5 GB, 768 MiB e reinicio automatico; teste/oraculo:
configuracao validada, todas as consultas retornam tres series e `up=1` antes e
depois de reiniciar o Prometheus; gate: portas novas fechadas no IP publico,
servicos habilitados e 12 paineis consultando o datasource provisionado.
