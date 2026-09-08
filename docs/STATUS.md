# Status

Atualizado em 2026-09-08 (America/Sao_Paulo).

## Assinaturas e Asaas em homologacao

Implementadas migrations de planos, trial de 15 dias, assinatura direta/parceiro,
cobrancas com escolha na fatura Asaas e QR Pix, pedidos idempotentes e inbox de webhooks. Contrato do ERP em
[ASSINATURAS_ERP.md](ASSINATURAS_ERP.md). Mensal R$49,90, trimestral R$149,70,
anual R$499,00. Avisos iniciam tres dias antes do vencimento. A entrega expira
com a assinatura; monitoramento permanece protegido por mais 30 dias.

Sandbox publico em `https://sandbox.fisconexa.com.br`, API Linux nativa com
usuario, diretorio e banco separados. Porta 9001 ligada somente em localhost;
Caddy fornece HTTPS. `fisconexa-sandbox-api.service` reinicia em falhas;
`fisconexa-sandbox-cobrancas.timer` concilia a cada dez segundos apos termino.
Nenhum worker fiscal ou certificado de cliente foi colocado no sandbox.

Webhook cadastrado pelo usuario no Asaas Sandbox, API v3. Recebimento real de
PAYMENT_CREATED e PAYMENT_RECEIVED comprovado por inbox persistida e processada,
com zero retentativas nesse smoke. Pix gerado pela API Linux, confirmacao feita
no Asaas Sandbox, assinatura ativada e repeticao sem duplicar periodo. Tambem
passaram cancelamento repetido e renovacao anual com callback real.

85 testes unitarios aprovados; 15 cenarios SQL de assinaturas aprovados;
regressao de lease e pipeline com 150 documentos aprovada em banco local
exclusivo. Builds API Windows/Linux e spike Delphi aprovados. O EXE Windows
consultou assinatura, planos e cobranca pela API HTTPS Linux.
O EXE tambem criou Pix trimestral, gravou PNG valido, retomou a cobranca pelo
status da assinatura, repetiu a chave sem duplicar e cancelou a cobranca.
Sandbox instalado na release `2026.09.08-sandbox4`. A API cria billingType
UNDEFINED e retorna url_pagamento, forma_pagamento, pagamento_aprovado e
aprovada_em, mantendo QR Pix. Cartao CONFIRMED concede acesso e permanece
distinto de RECEIVED; a liquidacao posterior nao estende o periodo novamente.
Recusa/aprovacao de cartao ficticio e estorno do cartao por callback real foram
comprovados. Teste: `python tests/smoke-assinaturas-cartao-vps.py`.

Pacote Linux final: `D:\Hostinger\artefatos\fisconexa\empacotamento\dist\fisconexa-2026.09.08-assinaturas-rc2.tar.gz`.
SHA256: `be4fbb66ca3685f70ffa2f3c591bf22d578ab9d3e0505b81e5da212592ca8a8f`.
Empacotado em D porque G ficou sem espaco. Os diretorios intermediarios rc1 e
rc2 incompleto foram arquivados em D:\Hostinger\artefatos\fisconexa. Nao usar
o diretorio rc2 incompleto como release; o pacote valido esta em empacotamento/dist.

Pendente externo: estorno sandbox de `pay_ien12mhyr1r3hys7` aguarda
AWAITING_CRITICAL_ACTION_AUTHORIZATION no painel Asaas. O teste retomavel e
`python tests/smoke-assinaturas-estorno-vps.py --retomar`. Nao considerar
esse estorno Pix concluido ate receber PAYMENT_REFUNDED e conferir o prazo final.
O estorno de cartao foi concluido e validado separadamente no provedor real sandbox.
A regra de estorno concluido/parcial e coberta por teste unitario e a remocao
do periodo por teste SQL. Credenciais reais ainda nao fornecidas.

As migrations de assinatura ainda NAO foram aplicadas em producao. A producao
segue na rc9 abaixo; os trials dos tenants reais iniciarao no deploy desta
funcionalidade. Usuario pediu para aguardar os tokens de producao antes do deploy.
Gate pendente: autorizacao do estorno Pix de teste e configurar/validar o
Asaas producao antes de habilitar cobrancas reais. Nao apontar token
sandbox para o banco real. Toda credencial permanece fora do repositorio.

## Producao

A API e o worker Linux estao instalados no `fisconexa.vps` como release
`2026.09.07-rc9`. `https://api.fisconexa.com.br/health` responde
`{"situacao":"disponivel"}`. API, timer do worker, Caddy, Alloy, WireGuard e
fail2ban estao habilitados e ativos no systemd. Uma reinicializacao controlada
comprovou que os servicos retornam sem intervencao.

O PostgreSQL 16 roda nativamente no `dados.vps`, escutando apenas em
`127.0.0.1` e `10.77.0.1`. A base piloto preservou os 8 tenants, cursores,
certificados cifrados e sequencia de sincronizacao. A rodada fiscal da `rc8`
elevou a base de 124 para 157 documentos e de 119 para 122 referencias de XML;
nenhum registro ou XML foi removido. Somente a VPS da aplicacao acessa o papel
e a base `fisconexa` pela VPN.

O timer de backup logico esta ativo na VPS de dados. Ele gera diariamente dumps
custom de `fisconexa` e `academy`, valida o catalogo com `pg_restore` e conserva
sete dias com permissao `0600`. Os dumps iniciais dos dois bancos passaram no
oraculo. Existe tambem o dump externo da migracao em `D:\Backups`. Uma
reinicializacao controlada comprovou o retorno do PostgreSQL, WireGuard e timer.

## Worker fiscal

Os 8 tenants e seus 8 modulos de monitoramento estao ativos. O timer executa
uma unidade oneshot a cada dez segundos, mas somente chama a SEFAZ quando o
PostgreSQL devolve trabalho elegivel. Lote unitario, lease persistida,
`next_check_at`, limite de consultas pontuais e bloqueio 656 continuam sendo os
gates de execucao. Nenhuma lease permaneceu presa depois da rodada.

A falha `error:0308010C ... unsupported` foi reproduzida fora da SEFAZ. O pacote
Linux continha arquivos distintos para `libcrypto.so` e seu SONAME, e o ACBr
abria uma segunda instancia do OpenSSL com outro contexto de providers. A
`rc8` empacota uma unica biblioteca e cria hardlinks para os nomes sem versao;
o carregamento ACBr do A1 passou no WSL, na VPS com o pacote instalado e no
worker real.

Em 2026-09-07 22:20:44 UTC o worker consultou a SEFAZ na janela persistida,
recebeu `cStat 137`, zerou a falha, liberou a lease e agendou a proxima consulta
para 23:21:14 UTC. Esse resultado liberou de forma transacional os demais
tenants. A fila processou os vencidos, inclusive um lote `cStat 138`, avancou o
NSU e aplicou novas janelas de aproximadamente uma hora. O tenant que ainda
guardava um erro da release anterior foi processado pelo proprio worker as
22:46:59 UTC, recebeu `cStat 138` e nova janela para 23:47:29 UTC. A ciencia
automatica global permanece desligada.

## Integracao ERP

O exemplo [FiscoNexa.ErpSpike.dpr](../examples/erp-delphi/FiscoNexa.ErpSpike.dpr)
compila para `bin/examples/win64/FiscoNexa.ErpSpike.exe`. Depois da ativacao dos
tenants, o executavel voltou a comprovar HTTP 200 para saude, monitoramento e
documentos na API de producao. Em prova anterior, o comando `xml` baixou pela
API um XML real valido de 9.020 bytes. O smoke padrao e somente leitura; o
comando `xml` cria uma solicitacao assincrona quando o documento ainda nao esta
retido.

A credencial exclusiva do spike fica fora do repositorio, em
`D:\Hostinger\credenciais\fisconexa-erp-spike.env`. O banco guarda somente o
SHA-256 e identifica a integracao como `ERP spike`.

## Logs

API e worker escrevem JSON no terminal/journald e em arquivos rotativos de
10 MiB. Alloy acompanha os arquivos e envia lotes ao Loki central no
`loki.vps`; uma consulta posterior a rodada encontrou streams recentes dos
servicos `api` e `worker`. Grafana consulta o tenant `fisconexa`. Loki exige
`X-Scope-OrgID`, e cada projeto recebe rota, usuario, senha e datasource
separados. A retencao atual e de sete dias. Docker, WireGuard, Loki, Grafana e o
gateway retornaram automaticamente em reinicializacao controlada.

O dashboard `FiscoNexa - Operacao`, na pasta `FiscoNexa`, possui 11 paineis
para requisicoes e status HTTP, erros 5xx, latencia P95, tarefas fiscais,
eventos por servico, rotas mais acessadas e logs recentes. Todas as consultas
foram validadas pela API do Loki antes da publicacao.

O Prometheus `3.14.0` roda no mesmo Compose, sem porta publicada, e conserva
ate 15 dias ou 5 GB de series. Os Node Exporters instalados para esse painel
estao habilitados nas tres VPS e ouvem somente nos enderecos WireGuard usados
pelo coletor. O dashboard `Saude das VPS` possui 12 paineis para
disponibilidade, CPU, memoria, disco, carga, rede, I/O, uptime e swap. Os tres
alvos retornaram `up=1` antes e depois da reinicializacao controlada do
Prometheus.

## Pendencias comerciais

- Criar alertas de indisponibilidade e erro recorrente no Grafana.
- Configurar uma copia de backup fora da VPS de dados ou snapshot automatico do
  provedor para perda total do host.
- Implementar manifestacao conclusiva solicitada pelo ERP e alertas de XML aos
  60, 75 e 85 dias, conforme `docs/DECISOES_PENDENTES.md`.

## Evidencias atuais

- `scripts\test-unit.bat`: 76/76 metodos aprovados.
- `scripts\build-api.bat linux64` e `scripts\build-worker.bat linux64`:
  compilacao Linux64 aprovada.
- Pacote implantado: `fisconexa-2026.09.07-rc9.tar.gz`, SHA-256
  `d92a32b0998f5b7f9b79f5d386b0d88e4ca7df1baaee49540b0e542972780386`.
- Teste de certificado ACBr sem chamada SEFAZ aprovado no WSL e na VPS com as
  bibliotecas autocontidas da `rc8`.
- `scripts\build-erp-spike.bat`: `.dpr` e `.exe` Win64 recompilados; smoke real
  aprovado contra `https://api.fisconexa.com.br` pela rota `/health` na `rc9`.
