# Observabilidade fiscal e de tenants

Problema: o dono do produto nao possuia uma visao consolidada de tenants,
licencas, certificados, monitoramento e documentos; evidencia: o Grafana
consultava apenas logs e metricas das VPS; invariante: a observabilidade nao
acessa senha, certificado cifrado, token, conteudo de XML ou tabelas da
aplicacao; causa: os indicadores de negocio existem somente no PostgreSQL;
solucao: views agregadas no schema `observabilidade` e usuario dedicado com
permissao de leitura apenas nessas views, acessado pelo Grafana via WireGuard;
previsao: o painel reflete o estado persistido em ate 30 segundos; riscos: uma
consulta custosa ou exposicao fiscal excessiva, limitados por timeout de cinco
segundos, poucas conexoes e campos explicitamente permitidos; teste/oraculo:
usuario do Grafana consulta todas as views e recebe negacao ao consultar
`certificados`, `documentos` e `empresas`; gate: datasource saudavel, consultas
do painel sem erro e contagens iguais as obtidas pelo usuario administrativo.
