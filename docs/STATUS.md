# Status

## Estado atual

### Smoke de tenant unico — 2026-09-06 00:29 Brasilia

Por pedido expresso, os modulos sao alternados um por vez nos smokes. Depois
do REI DOS DOCES, QUEIROZ & CORREA LTDA foi ativada e os outros 7 modulos,
incluindo REI DOS DOCES, ficaram suspensos via PUT
/v1/empresas/{id_empresa}/modulos/monitoramento. Tenants, certificados, cursores e
prazos foram preservados. Nao reativar lote automaticamente.

A continuacao das 00:11 ja havia concluido: 138, NSU 7136, 121 documentos,
119 XMLs e duas leituras via token ERP/S3 com SHA-256 confirmado. Na execucao
unica pedida agora, worker processou um comando retrieve_xml, concluido com
sucesso; nao repetiu distribuicao nem alterou sua janela de 01:12:19 Brasilia.
Banco mostra 119 documentos com ciencia aceita e 2 com 596. Os dois foram
emitidos em 25/07/2026, 42 dias antes da tentativa: excedem o prazo de 10 dias
da Ciencia da Emissao, mas nao 90 dias. O 596 nao comprova prazo de 90 dias.

Correcao aplicada e validada: quando a distribuicao persiste XML, encerra na
mesma transacao qualquer comando pendente para a mesma chave, desde que sem
lease ativa. O saneamento do piloto concluiu 118 comandos redundantes, sem
consulta SEFAZ; contagem final: 119 comandos concluidos com XML e zero
pendentes com ou sem XML.
Evidencias locais: build/pilot-single.log e build/pilot-batch-last-state.jsonl.
A continuacao automatica anterior terminou; nao ha worker residente instalado.

Em 2026-09-06 01:25 Brasilia, QUEIROZ & CORREA executou um ciclo elegivel e
recebeu 137, sem documentos, bloqueio ou falha. Cursor permaneceu 0 e a proxima
janela e 02:25:52 Brasilia. Evidencia: build/pilot-single-queiroz.log.

## Criterios de liberacao acordados

1. Fluxo fiscal real (`MVP-006`, em curso): comprovar monitoramento, ciencia,
   reconsulta, XML no S3 e download pelo token ERP, com cursor e prazos persistidos.
2. Ubuntu (`LINUX-001`, bloqueado): compilar e executar API e worker com as
   dependencias reais na plataforma de destino.
3. Operacao 24/7 (pendente): provar inicio automatico e recuperacao apos queda
   e durante bloqueio SEFAZ, sem antecipar consultas nem duplicar trabalho.
4. Contrato ERP (pendente): entregar OpenAPI, exemplos e roteiro validado de
   credenciais, A1, paginacao, XML pendente, erros e idempotencia.
5. Ambiente de producao (pendente): configurar HTTPS, segredos, acessos ao
   PostgreSQL/KMS/S3 e backup com restauracao testada.
6. Visibilidade operacional (`LOG-001`, pendente): logs uteis e alertas de
   indisponibilidade/falha; centralizacao para cluster registrada separadamente
   como evolucao, com capacidade de diagnosticar a primeira VPS.

Prioridade expressa: concluir o item 1 antes de iniciar os demais.

### Cadastro ReceitaWS e lote autorizado

Em 2026-09-06 o responsavel autorizou cadastrar os certificados da pasta de
suporte e consultar os CNPJs elegiveis. `tests/smoke-fiscal-batch.ps1` usa a
rota padrao, senha do ambiente, sessoes DPAPI, deduplicacao por CNPJ e consultas
fiscais pelo executavel real. Certificados invalidos/vencidos sao reportados.
O segundo piloto retornou 656 e NSU 2165, sem falha tecnica no worker.
A espera individual anterior foi encerrada para evitar concorrencia entre
orquestradores; os prazos no banco permanecem intactos. Conferir os arquivos
locais `build/pilot-batch*.log`, `build/pilot-batch-onboarding.json` e
`build/pilot-batch-last-state.jsonl` antes de retomar.

Onboarding agora consulta ReceitaWS e persiste o cadastro em `dados_receita`,
com horario de coleta, razao social e fantasia. Retorna os dados pela mesma
rota; UF informada prevalece, UF ausente vem da consulta. Indisponibilidade
com UF informada permite cadastro e preserva enriquecimento anterior; sem
UF retorna 422 `uf_obrigatoria`. Evidencia: 68 unitarios, suite local isolada
e integracao PostgreSQL de enriquecimento/replay sem perda aprovados.

## Base atual

Atualizacao do lote em 2026-09-06: senhas especificas fornecidas pelo operador
permitiram cadastrar L Carlos Gomes e Edvan via HTTP, ambos enriquecidos pela
ReceitaWS. Total atual: 8 tenants; somente R Santos permanece fora, vencido.
Senhas foram usadas em memoria e cifradas pelo fluxo normal, sem alterar .env.
L Carlos retornou 137, NSU 50; Edvan retornou rejeicao de ciencia 655, com
espera preservada ate 04:05:29 UTC. Adaptador passou a registrar 655 por
documento, sem classificar como ciencia aceita nem abortar o lote.
Comprovacao fiscal dessa correcao aguarda a janela; nenhuma reconsulta forcada.

Resultado do lote: 9 PFX examinados, 6 tenants cadastrados/enriquecidos via HTTP,
2 certificados nao abriram com a senha do ambiente e 1 estava vencido. Nos
quatro CNPJs novos elegiveis: dois retornaram 137 sem documentos, um 656 com
NSU 877 e um teve ciencia recusada com 596. Os dois pilotos anteriores nao
foram consultados antes da janela. Nenhum XML real foi validado neste lote.

596 foi identificado como evento fora do prazo: agora e resultado por documento
(`ciencia_cstat`, exposto com o mesmo nome) e nao aborta a distribuicao.
Falha no gateway tambem preserva pelo menos 3630 segundos, pois pode ocorrer
apos consulta externa. Correcao validada em build Win64 e integracao isolada;
a comprovacao fiscal da correcao permanece pendente. A janela do CNPJ afetado
foi apenas ampliada, nunca reduzida.

A continuacao individual antiga foi substituida por continuacao unica do lote:
`tests/continue-fiscal-batch.ps1`, processo e logs em
`build/pilot-batch-continuation*`. Primeira elegibilidade mantida em
2026-09-06 03:11:07 UTC (00:11:07 Brasilia). Nao iniciar orquestrador duplicado.

FiscoNexa entrega o monitoramento e o consumo de documentos pela integracao ERP.
A base usa Delphi/Horse, PostgreSQL, AWS KMS para o A1 e S3 para XML; API e
worker sao processos separados. O projeto ainda nao roda em nenhum ambiente.
Esta versao usa um unico schema final, sem compatibilidade com nomes legados.

O item em curso e `MVP-006` do [ledger](LEDGER.md). Autenticacao administrativa,
credenciais ERP e onboarding por A1 ja existem; `AUTH-001` nao e o proximo passo.

## Correcoes desta revisao

- Contrato HTTP publico padronizado em portugues do Brasil: `GET /saude`,
  `/autenticacao`, `/administracao`, `/v1/empresas`, `/v1/monitoramento` e
  `/v1/documentos`. Nao existem aliases em ingles. `cnpj`, `nsu`, `cstat`,
  `xml`, `Authorization` e `Idempotency-Key` permanecem como convencoes
  fiscais ou HTTP.
- A lista ERP agora retorna chave de acesso, modelo, serie, numero, emissao,
  CNPJ e nome do emitente, tipo de operacao, situacao fiscal, valor, situacao,
  cStat de ciencia e disponibilidade do XML. Novos documentos persistem nome,
  tipo de operacao e situacao fiscal recebidos da SEFAZ; os documentos ja
  retidos antes desta migracao podem nao possuir esses tres complementos.
- O contrato para integradores esta em `docs/CONTRATO_API.md`; o smoke HTTP
  valida somente as novas rotas, campos e paginacao por `ultimo_nsu`.
- Consultas e testes usam as tabelas declaradas pelas units `Tables.*`.
- Worker consome monitoramento principal, comandos de XML e lacunas. Reclama
  apenas o proximo trabalho, sem deixar um lote de leases envelhecer em memoria.
- Lacunas persistem documentos e referencias ao XML antes de avancar; falha no
  storage conserva o cursor e persiste o retry.
- Comandos de XML consultam pela chave de acesso. Resumo nao conclui download;
  a conclusao exige XML confirmado no storage.
- Consultas pontuais compartilham a lease do CNPJ e contabilizam a tentativa
  antes da chamada externa. `656` impede a fila pontual durante o bloqueio.
- Atualizacao de documento recebe novo NSU; replay identico nao republica e
  resumo antigo nao apaga XML retido. Pagina vazia conserva o cursor enviado.
- XML pendente retorna HTTP 202 e um comando idempotente; outro tenant recebe
  404. Credencial revogada e escopo insuficiente sao recusados.
- A API usa a mesma data do banco para informar validade do certificado.

## Evidencias

Validacao em 2026-09-05, sem chamadas fiscais reais nesta revisao:

- `scripts/test-unit.bat`: 67 metodos aprovados, zero falhas/erros.
- `scripts/build-api.bat win64` e `scripts/build-worker.bat win64`: aprovados.
- `tests/test-release-local.ps1`: banco PostgreSQL isolado, reaplicacao do
  schema, leases, worker simulado, XML/lacunas/retry, NSU em 150 documentos e
  contrato HTTP. Inclui 24 cenarios UniDAC com 30, 101 e 251 itens.
- `tests/smoke-auth-admin.ps1`: autenticacao, rotacao/revogacao e acesso admin.
- `tests/smoke-erp-end-to-end.ps1`: A1 sintetico, KMS e S3 reais, onboarding,
  leitura de XML pelo token ERP e suspensao, usando banco isolado.

## Smoke fiscal autorizado e retomada

O responsavel autorizou monitoramento, ciencia e XML com o A1 de cliente
apontado no ambiente. O onboarding real passou. A primeira tentativa do worker
falhou na persistencia de um timestamp fracionario; o problema foi reproduzido
com data sintetica e corrigido no bind PostgreSQL, sem nova consulta fiscal
durante o diagnostico. A ocorrencia nao prova ausencia de ciencia: eventos
podem ter sido enviados antes da falha transacional.

A espera foi preservada ate 2026-09-06 03:11:07 UTC (00:11:07 em Brasilia).
Uma nova execucao durante a janela processou zero tarefas e confirmou a API
saudavel. A continuacao unica esta agendada por `tests/continue-real-fiscal.ps1`.
Antes de retomar, conferir `build/pilot-continuation-process.json`,
`build/pilot-continuation.log`, `build/pilot-continuation-error.log` e
`build/pilot-last-state.json`; eles sao locais e nao devem ser versionados.
Nao repetir onboarding, zerar cursor nem antecipar `next_check_at`.
O banco e os XMLs reais devem ser preservados. O smoke fiscal ainda nao passou.

## Ubuntu e operacao continua

Destino definido: VPS Ubuntu. Configuracoes de API supervisionada e worker
agendado estao em `deploy/systemd`; nao foram instaladas. A verificacao em WSL
nao pode concluir sem os executaveis Linux em `/opt/fisconexa`.
`LINUX-001` foi revalidado: com os caminhos de units informados, WMLC ainda
rejeita `class destructor` em `Horse.Core.pas(111:11)`. Nao houve alteracao do
compilador, nem deploy na VPS. O pacote de operacao nao libera producao sozinho.

Logs centralizados para operacao em cluster foram registrados em `LOG-001` e
em `REGRAS.MD`; a implementacao permanece pendente.

Proposta para `LOG-001`, registrada como pendencia: API e worker emitem JSON
na saida do processo; journald e Alloy em cada VPS coletam e encaminham para
Loki centralizado, consultado pelo Grafana. Hospedagem propria ou gerenciada,
retencao e alertas ainda serao definidos; preferir destino fora da VPS da API.
Nenhum desses componentes de observabilidade foi instalado nesta revisao.
