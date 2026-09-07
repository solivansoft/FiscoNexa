# Ledger de entrega - FiscoNexa

Este e o inventario autoritativo de execucao. Ele separa o que esta comprovado
do que e somente planejado e define a proxima dependencia elegivel.

## Regras

- Estados permitidos: `PENDENTE`, `EM_CURSO`, `OK`, `BLOQUEADO`, `N/A`.
- Ha no maximo um item `EM_CURSO`.
- Um item `OK` exige evidencia reproduzivel registrada neste arquivo.
- Um item `BLOQUEADO` informa a lacuna e nao pode receber consumidor acima dele.
- Rotas so sao adicionadas ao servidor depois que seu contrato, autorizacao e
  teste negativo existirem. Cada uma prova ausencia de credencial, token
  invalido/expirado/revogado e papel ou escopo insuficiente quando aplicavel.
- Eventos sao fatos de dominio persistidos na outbox; handler nao e evento.
- Dados de um CNPJ so podem ser lidos por grant humano explicito ou token de
  integracao limitado ao proprio CNPJ.
- O gate estrutural e `powershell -ExecutionPolicy Bypass -File
  scripts\validate-ledger.ps1`. Ele valida formato, IDs e estados, mas nao
  substitui os oraculos de cada item.

## Camadas e fronteiras

| Camada | Responsabilidade | Pode depender de | Nao pode depender de |
| --- | --- | --- | --- |
| `core` | tipos, erros e invariantes puros | nenhuma | HTTP, FireDAC, ACBr |
| `domain` | regras de usuario, empresa, acesso e documento | `core` | Horse, banco, storage |
| `application` | casos de uso, transacao, autorizacao e eventos | `core`, `domain` | Horse, detalhes ACBr |
| `persistence` | PostgreSQL, migrations, repositorios e outbox | `core`, `domain` | rotas Horse |
| `api` | HTTP, parse/serializacao e mapeamento de erro | `application` | SQL direto, ACBr |
| `worker` | consumo de comandos fiscais e SEFAZ | `application`, adaptador fiscal | Horse |
| `integrations` | ERP, S3, KMS e ACBr por adaptadores | contratos de `application` | regras de autorizacao HTTP |
| `operations` | configuracao, build, health, logs e deploy | todas por composicao | regra de negocio |

## Gates transversais

| ID | Estado | Contrato observavel | Evidencia / gate |
| --- | --- | --- | --- |
| ENV-001 | OK | Dependencias Win64 sao reproduziveis e pinadas. | `scripts\dependencies.bat win64` concluiu com Horse no commit do lock e `libpq.dll` validada por SHA-256. |
| BUILD-001 | OK | API Win64 gera binario release e DCUs fora de `src`. | `scripts\build-api.bat win64` concluiu; 56 DCUs em `build\win64\dcu` e zero em `src`. |
| DB-001 | OK | O mesmo executavel aplica somente migrations pendentes. | 2026-09-05: `tests/test-release-local.ps1` cria banco isolado, aplica o schema declarativo repetidamente e verifica preservacao dos dados. |
| API-001 | OK | A API responde `GET /health` apos migrar o banco. | `tests\smoke-api.ps1` aprovado. |
| API-ARCH-001 | OK | A API possui fronteiras, ciclo de requisicao e contrato HTTP definidos antes de novas rotas. | [Arquitetura da API](ARQUITETURA_API.md) revisada contra as invariantes de CNPJ. |
| LINUX-001 | OK | API e worker compilam nativamente para Linux64 e executam no Ubuntu com as bibliotecas ACBr declaradas. | 2026-09-07: `scripts\build-api.bat linux64` e `scripts\build-worker.bat linux64` aprovados com `dcclinux64`; API respondeu `/health` no WSL e o worker consultou tres certificados reais, sem bloqueio, incluindo avancos NSU 50->79 e 0->4525. |
| PROD-DATA-001 | OK | A promocao da base piloto preserva integralmente cursores fiscais, documentos e referencias externas; nenhum tenant homologado reinicia do NSU zero. | 2026-09-07: dump/restauracao para `dados.vps` comparou 19 tabelas e invariantes: 8 empresas, 124 documentos, 119 XMLs, 127 comandos e sequencia 375; API aplicou `licencas` sem alterar os dados fiscais. |

## Roteiro por dependencia

| ID | Estado | Camada | Depende de | Contrato observavel | Oraculo / gate |
| --- | --- | --- | --- | --- | --- |
| AUTH-001 | OK | core/domain/application/persistence | DB-001 | `--user-create` cria uma unica vez o primeiro superadmin; senha usa PBKDF2-SHA-256 com salt; sessao possui access token, refresh rotativo, expiracao e revogacao. | 2026-09-05: `scripts\test-unit.bat` e `tests\smoke-auth-admin.ps1` aprovaram criacao unica, refresh reutilizado recusado, troca de senha e logout. |
| AUTH-002 | PENDENTE | api | AUTH-001 | Registro cria usuario sem expor hash e recusa email duplicado. | `POST /autenticacao/cadastro`: 201, 409 e 422. |
| AUTH-003 | OK | api | AUTH-001 | Login emite sessao somente para senha valida e usuario ativo. | 2026-09-05: `tests\smoke-auth-admin.ps1` aprovou access e refresh token; credenciais invalidas sao 401. |
| AUTH-004 | OK | api | AUTH-001 | Renovacao e encerramento de sessao nao permitem reutilizar credencial revogada. | 2026-09-05: `tests\smoke-auth-admin.ps1` aprovou refresh rotativo, rejeicao de replay, troca de senha e logout. |
| ACCESS-001 | PENDENTE | domain/application | AUTH-001 | Checagem de acesso a CNPJ e unica, explicita e reutilizada por todos os casos de uso. | Matriz de grants humano, organizacao e token ERP. |
| COMPANY-001 | PENDENTE | application/persistence | ACCESS-001 | Onboarding cria empresa, primeiro owner e configuracao fiscal em uma transacao. | rollback sem empresa parcial; CNPJ normalizado e unico. |
| COMPANY-002 | PENDENTE | api | COMPANY-001 | Usuario owner compartilha CNPJ com usuario contador. | `POST /empresas/{id_empresa}/acessos/usuarios`; 201, 403 e 404. |
| COMPANY-003 | PENDENTE | api | COMPANY-001 | Usuario owner compartilha CNPJ com organizacao contador, ERP ou revenda. | `POST /empresas/{id_empresa}/acessos/organizacoes`; testes de escopo. |
| ERP-BOOTSTRAP-001 | PENDENTE | domain/application/persistence | DB-001 | Credencial opaca do fornecedor de ERP possui escopo `companies:onboard`, nao pertence a CNPJ e nao pode ler documentos. | token invalido e token de tenant sao recusados; credencial bootstrap nao lista nem le documento. |
| CERT-001 | PENDENTE | integrations/application | ERP-BOOTSTRAP-001, MVP-001 | Certificado A1 e senha sao cifrados por envelope; plaintext nunca entra no log, evento ou banco. | chave KMS separada para certificados; teste de cifra, varredura de logs e recuperacao do certificado pelo worker antes de qualquer rota. |
| MONITOR-001 | PENDENTE | application | COMPANY-001, CERT-001 | Configuracao de monitoramento valida flags de manifestacao automatica por CNPJ. | atualizar e ler configuracao somente com grant admin. |
| MANIFEST-ERP-001 | PENDENTE | api/application/worker | MVP-006, AUDIT-001 | ERP solicita manifestacao conclusiva idempotente por documento, opcionalmente encadeada ao download do XML; confirmacao nunca e inferida apenas pela necessidade contabil. Documentos sem XML recebem estados e alertas aos 60, 75 e 85 dias. | Smoke real cobre confirmacao, desconhecimento e operacao nao realizada, cStat aceito/recusado, download unico ao S3, auditoria, expiracao e isolamento entre tenants. |
| COMMAND-001 | PENDENTE | domain/persistence | MONITOR-001 | Comando fiscal tem chave de idempotencia, estados e lock logico por CNPJ. | tentativa dupla cria um unico comando executavel. |
| WORKER-001 | PENDENTE | worker | COMMAND-001 | Worker simulado reclama e conclui um comando sem duplicar efeito. | dois workers concorrentes, um unico executor. |
| DFE-001 | PENDENTE | integrations/worker | WORKER-001, CERT-001 | Adaptador SEFAZ materializa documentos e cursor/NSU sem pular lacunas. | fixtures do servico atual e homologacao posterior. |
| DOCUMENT-001 | PENDENTE | application/persistence | DFE-001 | Documento e unico por CNPJ + chave; transicoes de status sao validas. | repeticao do mesmo XML nao duplica documento. |
| STORAGE-001 | PENDENTE | integrations/application | DOCUMENT-001 | XML fica no S3 com hash e chave opaca; banco guarda somente metadados. | upload/download, hash igual e acesso negado fora do CNPJ. |
| ERP-001 | PENDENTE | application/api | ACCESS-001, DOCUMENT-001 | Token de ERP possui hash, escopos e um unico CNPJ. | token revogado, escopo ausente e CNPJ diferente retornam 401/403. |
| ERP-002 | PENDENTE | api | ERP-001, STORAGE-001 | ERP lista documentos monitorados por `nsu` proprio crescente e obtem XML de um documento autorizado. | `nsu=0` faz carga inicial; pagina crescente retorna ultimo NSU para retomada idempotente; isolamento de CNPJ. |
| OUTBOX-001 | PENDENTE | domain/persistence | DB-001 | Todo evento publicado existe primeiro na transacao do fato de dominio. | rollback nao deixa evento; reprocessamento nao duplica entrega. |
| AUDIT-001 | PENDENTE | application/persistence | ACCESS-001 | Leitura de XML, alteracao de acesso, manifestacao e uso administrativo geram auditoria. | evento de auditoria com ator, CNPJ e correlacao. |
| OPS-001 | PENDENTE | operations | BUILD-001, OUTBOX-001 | Logs possuem correlacao e nao registram token, senha ou certificado. | teste de redacao de segredo e health de dependencias. |
| PILOT-001 | OK | application/persistence/api | DB-001 | Um token opaco de ERP fica vinculado a um unico tenant/CNPJ e lista somente os documentos desse tenant. | `tests\smoke-erp-documents.ps1` comprovou 401 sem token e leitura de somente um documento do tenant vinculado. |
| PILOT-002 | PENDENTE | worker/persistence | ERP-BOOTSTRAP-001, CERT-001 | Worker persiste cursor NSU, comando e estado de monitoramento sem depender do banco do ERP. | ciclo simulado recupera estado apos reinicio e nao executa dois monitores para o mesmo CNPJ. |
| ERP-ONBOARDING-001 | PENDENTE | application/api | ERP-BOOTSTRAP-001, CERT-001, PILOT-002 | ERP cadastra ou retoma um CNPJ pelo A1, recebe token exclusivo do tenant e grava o primeiro comando de monitoramento na mesma transacao idempotente. | reenvio com a mesma `Idempotency-Key` nao duplica empresa, certificado ou comando; CNPJ extraido do certificado define o tenant. |
| MVP-001 | OK | persistence | DB-001 | Schema declarativo por tabela cria e atualiza nomes finais, campos, indices, constraints e acoes de dados idempotentes. | 2026-09-05: `scripts\test-unit.bat`, `scripts\build-api.bat win64` e `tests\smoke-schema.ps1` aprovados. O smoke recriou o volume Docker, subiu a API duas vezes e conferiu tabelas, constraints e indices finais. |
| MVP-002 | OK | application/persistence | MVP-001 | ERP homologado possui chave exclusiva, hash, escopos e vinculo com organizacao. | 2026-09-05: `tests\unit\Tests.ErpKeys.pas` cobre hash, escopo e recusas; `tests\smoke-erp-keys.ps1` comprovou em PostgreSQL chave valida, token de tenant recusado e chave revogada recusada. |
| MVP-003 | OK | integrations/application | MVP-001, MVP-002 | A1 e senha recebem cifra por envelope com `fisconexa-certificates`; CNPJ e validade sao extraidos. | 2026-09-05: `scripts\test-unit.bat`, `tests\smoke-kms.ps1` e `tests\smoke-certificate.ps1` aprovados. KMS gerou/recuperou a data key AES-256 e a fixture PFX temporaria validou senha, CNPJ e validade sem material versionado. |
| MVP-004 | OK | api/application | MVP-002, MVP-003 | `POST /v1/empresas` ativa empresa, cria vinculo ERP, modulo e comando de monitoramento de modo idempotente. | 2026-09-05: `tests\smoke-company-onboarding.ps1` aprovou duas escritas PostgreSQL iguais sem duplicar certificado, integracao, modulo ou comando; `tests\smoke-erp-companies.ps1` confirmou 401 sem chave ERP; `tests\smoke-erp-companies-validation.ps1` confirmou 422 para A1 ausente com chave ERP valida; `tests\smoke-erp-companies-authenticated.ps1` aprovou A1 temporario, AWS KMS, token inicial e reenvio idempotente por HTTP. |
| MVP-005 | OK | worker/persistence | MVP-004 | Worker reclama CNPJ vencido, persiste cursor NSU, janela SEFAZ, lease e lacunas; respeita cancelamento. | 2026-09-05: `scripts\build-worker.bat win64`, `scripts\test-unit.bat` e `tests\smoke-monitor-leases.ps1` aprovaram worker mockado, duas conexoes concorrentes, `137`/`138`/`656`, cursor/janela/lacuna, prioridade do principal, intervalo de cinco minutos, limite de quinze por hora e cancelamento. `tests\smoke-erp-documents.ps1` comprovou `GET /v1/monitoramento` recuperado apos reinicio da API. |
| MVP-006 | EM_CURSO | integrations/worker | MVP-005 | Fluxo normal: ERP envia A1, senha e UF; worker monitora, registra ciencia automatica para resumo pendente, reconsulta, baixa XML ao S3 e materializa documento com NSU proprio. O ERP lista pelo NSU proprio, baixa XML por documento ou solicita ciencia pontual assincrona quando ainda pendente. Suspensao/cancelamento interrompe novos ciclos. | 2026-09-07: 76 unitarios aprovados e fluxo sintetico KMS/S3/HTTP aprovado. A `rc8` corrigiu a duplicacao do contexto OpenSSL no pacote autocontido; teste ACBr isolado passou no WSL e na VPS. Na janela persistida, o worker real recebeu 137, liberou lease e agendou nova consulta; depois processou os 8 tenants ativos, recebeu inclusive 138, avancou NSUs e ampliou a base de 124/119 para 157 documentos/122 XMLs sem remocao. API e worker recuperaram automaticamente apos reinicio. Falta concluir o oraculo especifico de ciencia, reconsulta e XML real no mesmo fluxo; o monitoramento piloto esta operacional. |
| PILOT-003 | PENDENTE | integrations/worker | PILOT-002 | Adaptador ACBr registra ciencia quando habilitada ou solicitada e obtem XML apos retorno aceito. | homologacao somente com certificado do piloto; evento fiscal nao e simulado como prova. |
| PILOT-004 | PENDENTE | integrations/application/api | PILOT-003 | XML e guardado em storage S3 com hash; banco mantem metadata e SHA-256. | `tests\smoke-s3.ps1` ja aprovou PUT/GET real assinado, TLS valido e SHA-256; falta encadear com ciencia homologada. |
| PILOT-005 | PENDENTE | api | PILOT-001, PILOT-004 | ERP consome documentos prontos sem enviar nem escolher CNPJ. | `tests\smoke-erp-documents.ps1` ja aprovou isolamento por token, NSU crescente, retomada e 401/404 no XML; falta o fluxo fiscal homologado. |
| ERP-INTEGRATION-001 | PENDENTE | operations/integrations | MVP-006 | O ERP proprio consome o contrato fechado do FiscoNexa: ativa CNPJ, guarda token do tenant, sincroniza por NSU e baixa XML para o pre-lancamento local. | ambiente piloto com CNPJ real; carga inicial e retomada apos reinicio sem duplicar lancamento. |
| ERP-SPIKE-001 | OK | operations/integrations | PILOT-001, PILOT-005 | Executavel Delphi de referencia consulta saude, monitoramento, pagina documentos por NSU e baixa XML usando token de tenant. | 2026-09-07: `scripts\build-erp-spike.bat` gerou `FiscoNexa.ErpSpike.exe`; smoke na API de producao recebeu tres HTTP 200 e baixou XML valido de 9.020 bytes. |
| ERP-ADMIN-001 | OK | api/application/persistence | MVP-002, AUTH-001 | Superadmin cadastra ERP, emite/rotaciona sua chave bootstrap e permite revoga-la sem expor hashes. | 2026-09-05: `scripts\test-unit.bat` cobre hash sem segredo; `tests\smoke-auth-admin.ps1` comprovou 401 sem Bearer, 403 para usuario comum, criacao, rotacao e revogacao de chave. |

## Observabilidade operacional

| ID | Estado | Camada | Depende de | Contrato observavel | Oraculo / gate |
| --- | --- | --- | --- | --- | --- |
| LOG-001 | OK | operations/api/worker | API-001, MVP-005 | Logs estruturados de API e worker sao agregados fora da VPS da aplicacao, separados por projeto e sem token, senha, certificado ou XML integral. | 2026-09-07: API/worker escrevem JSON em console e arquivos rotativos; Alloy enviou em ate um segundo para Loki multi-tenant no `loki.vps`; Grafana possui datasource isolado `fisconexa`, com retencao de sete dias. |

## Inventario de rotas

As rotas marcadas como `OK` existem no Horse. As demais sao contratos reservados
e nao devem ser registradas antes de seus itens de dependencia ficarem `OK`.

| Rota | Estado | Caso de uso | Dependencias |
| --- | --- | --- | --- |
| `GET /health` | OK | disponibilidade local da API | API-001 |
| `POST /administracao/erps` | OK | cadastrar ERP homologado e emitir chave | AUTH-001, ERP-ADMIN-001 |
| `POST /administracao/erps/{id_erp}/chaves` | OK | rotacionar chave de ERP | AUTH-001, ERP-ADMIN-001 |
| `DELETE /administracao/erps/{id_erp}/chaves/{id_chave}` | OK | revogar chave de ERP | AUTH-001, ERP-ADMIN-001 |
| `POST /autenticacao/cadastro` | PENDENTE | cadastrar usuario humano | AUTH-001, AUTH-002 |
| `POST /autenticacao/entrar` | OK | iniciar sessao humana | AUTH-001, AUTH-003 |
| `POST /autenticacao/renovar` | OK | renovar sessao | AUTH-001, AUTH-004 |
| `POST /autenticacao/sair` | OK | revogar sessao atual | AUTH-001, AUTH-004 |
| `PUT /autenticacao/senha` | OK | alterar senha e revogar sessoes | AUTH-001, AUTH-004 |
| `POST /autenticacao/recuperar-senha` | PENDENTE | iniciar recuperacao de senha | AUTH-001 |
| `POST /autenticacao/recuperar-senha/confirmar` | PENDENTE | definir nova senha com token valido | AUTH-001 |
| `POST /empresas` | PENDENTE | iniciar empresa/CNPJ | COMPANY-001 |
| `GET /empresas` | PENDENTE | listar CNPJs autorizados | ACCESS-001, COMPANY-001 |
| `POST /empresas/{id_empresa}/acessos/usuarios` | PENDENTE | compartilhar com usuario | COMPANY-002 |
| `POST /empresas/{id_empresa}/acessos/organizacoes` | PENDENTE | compartilhar com contador/ERP/revenda | COMPANY-003 |
| `GET /documentos` | PENDENTE | frontend consulta documentos autorizados | ACCESS-001, DOCUMENT-001 |
| `PUT /empresas/{id_empresa}/configuracao-monitoramento` | PENDENTE | configurar monitor | MONITOR-001 |
| `POST /empresas/{id_empresa}/certificados` | BLOQUEADO | enviar certificado A1 | CERT-001 |
| `POST /empresas/{id_empresa}/comandos-fiscais` | PENDENTE | solicitar monitoramento/manifestacao/download | COMMAND-001 |
| `POST /empresas/{id_empresa}/integracoes-erp` | PENDENTE | criar token ERP | ERP-001 |
| `POST /integracoes-erp/{id_integracao}/rotacionar-token` | PENDENTE | rotacionar token ERP | ERP-001 |
| `DELETE /integracoes-erp/{id_integracao}` | PENDENTE | revogar token ERP | ERP-001 |
| `POST /v1/empresas` | OK | ERP ativa CNPJ por A1 | MVP-004 |
| `GET /v1/monitoramento` | OK | ERP consulta estado recuperado do monitoramento do proprio tenant | MVP-005 |
| `GET /v1/documentos` | OK | ERP lista documentos do tenant do token | PILOT-001 |
| `GET /v1/documentos/{id_documento}/xml` | OK | ERP obtem XML do tenant ou recebe 202 com comando idempotente; smoke HTTP e E2E S3 aprovados | PILOT-001, MVP-005 |

## Inventario de eventos de dominio

| Evento | Estado | Produtor | Consumidor inicial | Dependencias |
| --- | --- | --- | --- | --- |
| `user.registered` | PENDENTE | cadastro de usuario | auditoria | AUTH-002, OUTBOX-001 |
| `company.created` | PENDENTE | onboarding | auditoria | COMPANY-001, OUTBOX-001 |
| `company.access_granted` | PENDENTE | compartilhamento | auditoria | COMPANY-002 ou COMPANY-003, OUTBOX-001 |
| `certificate.registered` | BLOQUEADO | cofre de certificado | agendamento fiscal | CERT-001, OUTBOX-001 |
| `fiscal.command_requested` | PENDENTE | comando fiscal | worker | COMMAND-001, OUTBOX-001 |
| `fiscal.document_located` | PENDENTE | worker SEFAZ | documento/auditoria | DFE-001, OUTBOX-001 |
| `fiscal.awareness_registered` | PENDENTE | worker SEFAZ | documento/auditoria | DFE-001, OUTBOX-001 |
| `fiscal.xml_available` | PENDENTE | storage de XML | ERP/notificacao | STORAGE-001, OUTBOX-001 |
| `erp.document_ready` | PENDENTE | publicador ERP | conector ERP | ERP-002, OUTBOX-001 |

## Decisoes reservadas ao operador

| ID | Decisao | Bloqueia |
| --- | --- | --- |
| DEC-001 | AWS KMS, chave simetrica `fisconexa-certificates`, por envelope; o adaptador usara HTTPS assinado por SigV4, sem dependencia da AWS CLI no processo da API. | Resolvido em 2026-09-05; CERT-001 e DFE-001 real ainda exigem o adaptador e teste de round-trip. |
| DEC-002 | Politica comercial de quem paga e limites por CNPJ/documento. | cobranca, nao o nucleo fiscal. |
| DEC-003 | Politica de conta superadmin, MFA e suporte temporario. | rotas administrativas. |
| DEC-004 | Contrato de pre-lancamento que cada ERP deve receber. | `erp.document_ready` e conector Delphos. |

## Proximo item elegivel

`MVP-006`: adaptador SEFAZ real no worker para localizar documentos, registrar
ciencia automatica e baixar XML aceito ao S3. O superadmin ja pode provisionar
o ERP proprio e emitir sua chave bootstrap.

## MVP de segunda-feira

Condicao de chegada: um cliente do ERP proprio envia A1, senha e UF pelo ERP;
o FiscoNexa valida/persiste CNPJ e UF, vincula a empresa ao ERP, inicia
monitoramento, registra ciencia automatica, baixa XML aceito para o S3 e
devolve documentos paginados por NSU proprio ao ERP pelo token do proprio CNPJ.

Fora do MVP: frontend, login humano, tela do contador, compartilhamento, cobranca no FiscoNexa, cadastro autonomo de ERP parceiro e automacoes de pre-lancamento.

O ERP continua dono de contratacao e cancelamento. Cancelamento interrompe novos ciclos, sem apagar XML ja retido.

## Migracao autorizada de acesso PostgreSQL ? 2026-09-06

| ID | Estado | Camada | Dependencias | Entrega | Evidencia |
| --- | --- | --- | --- | --- | --- |
| DB-FD-001 | OK | persistence | - | Substituir UniDAC por FireDAC na conexao, consultas e builds compartilhados, preservando SQL e variaveis de ambiente. | API e worker DCC Win64 compilados; scripts/test-unit.bat: 69/69; tests/smoke-firedac-fetch.ps1: 24/24, tabela temporaria, 30/101/251 registros, fetch integral/sob demanda, cache, transacoes e pagina SQL. Nao certifica compilacao WMLC nem execucao fiscal ponta a ponta. |
