# Visao 360 do produto

Problema: os paineis especializados nao ofereciam ao dono uma leitura unica de
operacao fiscal, uso, comercial, qualidade e capacidade; evidencia: os dados
estavam divididos entre PostgreSQL, Loki e Prometheus; invariante: cada KPI
deve distinguir estado atual, historico exato e estimativa, sem ampliar o
acesso do Grafana as tabelas da aplicacao; causa: cada fonte responde uma parte
do comportamento do produto; solucao: dashboard executivo com 36 paineis e
views seguras para filas, lacunas, manifestacoes, qualidade, integracoes,
licencas e capacidade em 40 paineis, mantendo logs e infraestrutura em seus datasources;
previsao: o estado persistido aparece em ate 30 segundos e eventos acompanham a
retencao de suas fontes; riscos: interpretar `updated_at - created_at` como
instante exato da obtencao do XML ou a janela atual como SLA historico; esses
campos sao rotulados como estimativa e estado atual; teste/oraculo: todas as 40
consultas retornam HTTP 200 pelo Grafana e as tabelas de origem continuam
negadas ao usuario de observabilidade; gate: dashboard provisionado, contagens
conferidas com PostgreSQL e servicos de aplicacao preservados.
