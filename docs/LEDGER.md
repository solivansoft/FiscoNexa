# Ledger de entrega - FiscoNexa

Este e o inventario autoritativo de execucao. Ele separa o que esta comprovado
do que e somente planejado e define a proxima dependencia elegivel.

## Regras

- Estados permitidos: `PENDENTE`, `EM_CURSO`, `OK`, `BLOQUEADO`, `N/A`.
- Ha no maximo um item `EM_CURSO`.
- Um item `OK` exige evidencia reproduzivel registrada neste arquivo.
- Um item `BLOQUEADO` informa a lacuna e nao pode receber consumidor acima dele.
- Rotas so sao adicionadas ao servidor depois que seu contrato, autorizacao e
  teste negativo existirem.
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
| DB-001 | OK | O mesmo executavel aplica somente migrations pendentes. | Banco vazio: 1 migration e 12 tabelas; segunda subida: permanece 1 migration. |
| API-001 | OK | A API responde `GET /health` apos migrar o banco. | `tests\smoke-api.ps1` aprovado. |
| API-ARCH-001 | OK | A API possui fronteiras, ciclo de requisicao e contrato HTTP definidos antes de novas rotas. | [Arquitetura da API](ARQUITETURA_API.md) revisada contra as invariantes de CNPJ. |
| LINUX-001 | BLOQUEADO | API Horse compila para Linux pelo WMLC. | WMLC atual rejeita `class destructor` usado pelo Horse 3.3.0; nao integrar caminho Linux antes de o compilador suportar o recurso. |

## Roteiro por dependencia

| ID | Estado | Camada | Depende de | Contrato observavel | Oraculo / gate |
| --- | --- | --- | --- | --- | --- |
| AUTH-001 | EM_CURSO | core/domain/application | DB-001 | Credencial humana e sessao possuem contrato, expiracao, revogacao e hash de senha verificavel. | Testes de senha correta/incorreta, token expirado e sessao revogada. |
| AUTH-002 | PENDENTE | api | AUTH-001 | Registro cria usuario sem expor hash e recusa email duplicado. | `POST /auth/register`: 201, 409 e 422. |
| AUTH-003 | PENDENTE | api | AUTH-001 | Login emite sessao somente para senha valida e usuario ativo. | `POST /auth/login`: 200, 401 e 403. |
| AUTH-004 | PENDENTE | api | AUTH-001 | Renovacao e encerramento de sessao nao permitem reutilizar credencial revogada. | testes de refresh, logout e replay. |
| ACCESS-001 | PENDENTE | domain/application | AUTH-001 | Checagem de acesso a CNPJ e unica, explicita e reutilizada por todos os casos de uso. | Matriz de grants humano, organizacao e token ERP. |
| COMPANY-001 | PENDENTE | application/persistence | ACCESS-001 | Onboarding cria empresa, primeiro owner e configuracao fiscal em uma transacao. | rollback sem empresa parcial; CNPJ normalizado e unico. |
| COMPANY-002 | PENDENTE | api | COMPANY-001 | Usuario owner compartilha CNPJ com usuario contador. | `POST /companies/{company_id}/user-access`; 201, 403 e 404. |
| COMPANY-003 | PENDENTE | api | COMPANY-001 | Usuario owner compartilha CNPJ com organizacao contador, ERP ou revenda. | `POST /companies/{company_id}/organization-access`; testes de escopo. |
| CERT-001 | BLOQUEADO | integrations/application | AUTH-001, ACCESS-001 | Certificado A1 e senha sao cifrados por envelope; plaintext nunca entra no log, evento ou banco. | Exige decisao de KMS/Vault, teste de cifra e varredura de logs antes de qualquer rota. |
| MONITOR-001 | PENDENTE | application | COMPANY-001, CERT-001 | Configuracao de monitoramento valida flags de manifestacao automatica por CNPJ. | atualizar e ler configuracao somente com grant admin. |
| COMMAND-001 | PENDENTE | domain/persistence | MONITOR-001 | Comando fiscal tem chave de idempotencia, estados e lock logico por CNPJ. | tentativa dupla cria um unico comando executavel. |
| WORKER-001 | PENDENTE | worker | COMMAND-001 | Worker simulado reclama e conclui um comando sem duplicar efeito. | dois workers concorrentes, um unico executor. |
| DFE-001 | PENDENTE | integrations/worker | WORKER-001, CERT-001 | Adaptador SEFAZ materializa documentos e cursor/NSU sem pular lacunas. | fixtures do servico atual e homologacao posterior. |
| DOCUMENT-001 | PENDENTE | application/persistence | DFE-001 | Documento e unico por CNPJ + chave; transicoes de status sao validas. | repeticao do mesmo XML nao duplica documento. |
| STORAGE-001 | PENDENTE | integrations/application | DOCUMENT-001 | XML fica no S3 com hash e chave opaca; banco guarda somente metadados. | upload/download, hash igual e acesso negado fora do CNPJ. |
| ERP-001 | PENDENTE | application/api | ACCESS-001, DOCUMENT-001 | Token de ERP possui hash, escopos e um unico CNPJ. | token revogado, escopo ausente e CNPJ diferente retornam 401/403. |
| ERP-002 | PENDENTE | api | ERP-001, STORAGE-001 | ERP lista documentos monitorados e obtém XML de um documento autorizado. | filtros, paginação por cursor e isolamento de CNPJ. |
| OUTBOX-001 | PENDENTE | domain/persistence | DB-001 | Todo evento publicado existe primeiro na transacao do fato de dominio. | rollback nao deixa evento; reprocessamento nao duplica entrega. |
| AUDIT-001 | PENDENTE | application/persistence | ACCESS-001 | Leitura de XML, alteracao de acesso, manifestacao e uso administrativo geram auditoria. | evento de auditoria com ator, CNPJ e correlacao. |
| OPS-001 | PENDENTE | operations | BUILD-001, OUTBOX-001 | Logs possuem correlacao e nao registram token, senha ou certificado. | teste de redacao de segredo e health de dependencias. |

## Inventario de rotas

Somente `GET /health` existe hoje. As demais sao contratos reservados e nao
devem ser registradas no Horse antes de seus itens de dependencia ficarem `OK`.

| Rota | Estado | Caso de uso | Dependencias |
| --- | --- | --- | --- |
| `GET /health` | OK | disponibilidade local da API | API-001 |
| `POST /auth/register` | PENDENTE | cadastrar usuario humano | AUTH-001, AUTH-002 |
| `POST /auth/login` | PENDENTE | iniciar sessao humana | AUTH-001, AUTH-003 |
| `POST /auth/refresh` | PENDENTE | renovar sessao | AUTH-001, AUTH-004 |
| `POST /auth/logout` | PENDENTE | revogar sessao atual | AUTH-001, AUTH-004 |
| `POST /auth/password-recovery` | PENDENTE | iniciar recuperacao de senha | AUTH-001 |
| `POST /auth/password-recovery/confirm` | PENDENTE | definir nova senha com token valido | AUTH-001 |
| `POST /companies` | PENDENTE | iniciar empresa/CNPJ | COMPANY-001 |
| `GET /companies` | PENDENTE | listar CNPJs autorizados | ACCESS-001, COMPANY-001 |
| `POST /companies/{company_id}/user-access` | PENDENTE | compartilhar com usuario | COMPANY-002 |
| `POST /companies/{company_id}/organization-access` | PENDENTE | compartilhar com contador/ERP/revenda | COMPANY-003 |
| `GET /documents` | PENDENTE | frontend consulta documentos autorizados | ACCESS-001, DOCUMENT-001 |
| `PUT /companies/{company_id}/monitor-settings` | PENDENTE | configurar monitor | MONITOR-001 |
| `POST /companies/{company_id}/certificates` | BLOQUEADO | enviar certificado A1 | CERT-001 |
| `POST /companies/{company_id}/fiscal-commands` | PENDENTE | solicitar monitoramento/manifestacao/download | COMMAND-001 |
| `POST /companies/{company_id}/erp-integrations` | PENDENTE | criar token ERP | ERP-001 |
| `POST /erp-integrations/{integration_id}/rotate-token` | PENDENTE | rotacionar token ERP | ERP-001 |
| `DELETE /erp-integrations/{integration_id}` | PENDENTE | revogar token ERP | ERP-001 |
| `GET /v1/documents` | PENDENTE | ERP lista documentos disponiveis | ERP-001, ERP-002 |
| `GET /v1/documents/{document_id}/xml` | PENDENTE | ERP obtem XML autorizado | ERP-001, ERP-002 |

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
| DEC-001 | Provedor e modelo de KMS/Vault para certificados. | CERT-001 e DFE-001 real. |
| DEC-002 | Politica comercial de quem paga e limites por CNPJ/documento. | cobranca, nao o nucleo fiscal. |
| DEC-003 | Politica de conta superadmin, MFA e suporte temporario. | rotas administrativas. |
| DEC-004 | Contrato de pre-lancamento que cada ERP deve receber. | `erp.document_ready` e conector Delphos. |

## Proximo item elegivel

`AUTH-001`: definir e testar o contrato de identidade humana antes de criar a
primeira rota de cadastro. Nenhuma rota de empresa, certificado, fiscal ou ERP
e elegivel antes da checagem de acesso por CNPJ.
