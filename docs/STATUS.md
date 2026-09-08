# Status

Atualizado em 2026-09-08 (America/Sao_Paulo).

## Deploy das rotas tecnicas - 2026-09-08

Rotas tecnicas renomeadas para `/admin` e `/auth/login`, `/auth/refresh`,
`/auth/password` e `/auth/logout`, com contrato, documentacao e testes ajustados.
Build Windows, 3 testes de contrato, 56 negativas HTTP e 141 verificacoes de
integracao aprovados. API e worker compilados para Linux64 via MSBuild e SDK
Ubuntu 24.04; pacote autocontido preparado no WSL.

Release `2026.09.08-rotas-3a5fe41`, baseada no commit `3a5fe41`, instalada em
producao e sandbox. SHA256 do pacote:
`c0e2511c20d1ee7cd3e0d4e9a96bc7ded5abef276002474f741414af24125294`.
Gates de 56 rejeicoes HTTP passaram nos dois ambientes; repetidos tambem pela
URL HTTPS de producao. API, Caddy e timers ativos, com ultimo ciclo fiscal e
conciliador encerrados com sucesso apos o deploy. Sem alteracao de schema.

Documentacao publicada nos dois ambientes: `/docs/`, `/docs/openapi.json` e
`/docs/interno.html` responderam 200; `/admin/documentacao` sem token respondeu
401; contrato completo estatico e rota administrativa antiga responderam 404.
Assets internos usam o novo prefixo. Relatos de releases abaixo sao historicos.

Backlog do portal registrado em `DECISOES_PENDENTES.md`: contas, organizacoes,
gestao dos proprios ERPs, carteira, certificados, documentos, assinatura do
escritorio, avisos, indicadores e seguranca. Esses fluxos seguem pendentes.

## Portal de integracao e guardrail de autenticacao

Revisao de exposicao: portal publico reduzido a 11 operacoes de integracao.
Contrato completo (21 operacoes) em `docs/openapi-interno.json`, fora da pasta
publica; acesso em `/docs/interno.html` mediante token de sessao superadmin,
validado por `GET /admin/documentacao`. Token em URL nao autentica.
Informacoes comerciais internas e rotas de administracao/webhook nao constam
no JSON publico. Assinatura descrita como servico FiscoNexa pago pelo tenant;
integrador envia plano_codigo e nao define valores ou recebedor.
Gates atuais: 56 negativas HTTP e 141 verificacoes adicionais locais; 3 testes
de contrato/projecao/instrumento. A nova rota responde JSON UTF-8 sem cache.
Release `2026.09.08-docs-privadas-rc1` instalada em producao e sandbox, com
gates HTTP aprovados e timers retomados. SHA256 do pacote:
`2af45f1f6106ab68130e15b5d0784276ffb30496797cd072c98617ccfc1e921b`.
Navegador validou superadmin abrindo o contrato completo, encerramento da
visualizacao e recusa de token invalido. Publicacao tambem exige lista explicita
de assets, para impedir inclusao acidental de arquivos internos na pasta publica.

Publicado em https://api.fisconexa.com.br/docs e
https://sandbox.fisconexa.com.br/docs. Scalar local 1.68.0, interface pt-BR,
OpenAPI com 20 operacoes, exemplos e guias ERP/XML/assinatura. Detalhes de
manutencao e comandos em [PORTAL_API.md](PORTAL_API.md).

Corrigida validacao de usuario desabilitado em sessao existente. Regressao
reproduzida antes da correcao; 86/86 unitarios passaram depois. Builds Windows
e Linux aprovados. 53 negativas HTTP passaram localmente e nos dois ambientes
Linux; 132 verificacoes adicionais passaram com PostgreSQL local dedicado.
Inventario/contrato no build e workflow CI; teste negativo no instalador Linux
antes de aceitar a release. O workflow foi criado, ainda sem execucao remota.

API producao e sandbox atualizadas para `2026.09.08-documentacao-rc2`; API,
timer fiscal e conciliadores ativos apos os gates. Backup pre-deploy em
`D:\Backups\fisconexa-pre-documentacao-20260908.dump`, SHA256
`2d4fb2c7014b85b5b0065f32ab4ba69f1f30158c51dc3d203bccb585d0a2e402`.
Pacote Linux rc2 SHA256:
`30dc15bf88de1681275f5e59cb8ec5261dc513693d931a3097273c0efabd7d6a`.
Sem alteracao de schema ou criacao de cobranca real nesta entrega.

## Frente futura

Proxima frente futura registrada: carteira, assinatura e painel web do contador,
com cadastro pelo certificado A1 e aceite de autorizacao pelo escritorio, sem
exigir operacao do cliente. Ainda nao implementada. Escopo e gates em
[DECISOES_PENDENTES.md](DECISOES_PENDENTES.md#proxima-frente-futura-carteira-e-painel-do-contador).

## Assinaturas e Asaas em homologacao

Deploy em producao concluido em 2026-09-08 07:04 UTC. A release
`2026.09.08-assinaturas-rc2` esta ativa, com API, worker fiscal e conciliador
de cobrancas habilitados no systemd. As credenciais do arquivo local
`D:\Hostinger\credenciais\asaas-production.env` foram validadas no Asaas e
instaladas em `/etc/fisconexa/asaas.env`, permissao 0600.
O webhook FiscoNexa foi corrigido diretamente no Asaas para
`https://api.fisconexa.com.br/webhooks/asaas`, configurado com eventos de cartao
e habilitado depois do smoke. O webhook Delphos/licencas foi preservado.

Backup completo anterior ao deploy validado por catalogo pg_restore e SHA256,
com copia em D:\Backups. A comparacao antes/depois, ainda com worker parado,
comprovou hashes identicos de empresas, certificados, documentos e estado de
monitoramento: 8 tenants, 157 documentos e 122 referencias de XML.
Os 8 trials terminam em `2026-09-23T07:03:26.618997Z` (04:03 BRT).
O worker fiscal foi retomado somente depois dessa verificacao.
O EXE Delphi passou em producao para health, monitoramento, documentos,
assinatura trial e planos. Webhook devolve 401 sem segredo e 422 com segredo
valido e corpo invalido. Nenhuma cobranca real de teste foi criada.

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
do periodo por teste SQL. Credenciais reais configuradas no deploy acima.

As migrations de assinatura foram aplicadas em producao depois que o usuario
forneceu os tokens. A pendencia externa restante deste smoke e a autorizacao
do estorno Pix no sandbox. Pagamento real de cliente sera acompanhado pelo
webhook e conciliador de producao; nao foi simulado pagamento com dinheiro real.
Toda credencial permanece fora do repositorio.

## Producao

A API e o worker Linux estao instalados no `fisconexa.vps` como release
`2026.09.08-assinaturas-rc2`. `https://api.fisconexa.com.br/health` responde
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
