# Arquitetura da API

## Decisao

Problema: expor cadastro, compartilhamento e documentos fiscais sem deixar HTTP
ou SQL direto misturarem regras de acesso por CNPJ; evidencia: a API atual ja
aplica migrations e responde health, enquanto o dominio exige participantes
humanos, organizacoes e tokens ERP com escopos diferentes; invariante: uma rota
nao decide autorizacao, token ERP nunca amplia escopo de CNPJ, e a API nunca
consulta a SEFAZ de forma sincrona; causa/hipotese: separar transporte, caso de
uso e persistencia evita que novas rotas repliquem regras de seguranca e permite
o worker operar sem expor HTTP; referencia: `docs/ARQUITETURA.md`,
`docs/DECISAO_VERTICAL_SLICE.md` e `docs/LEDGER.md`; solucao: monolito modular
em camadas com API como processo de borda e PostgreSQL como fonte de verdade;
previsao: cada rota sera pequena, testavel e podera publicar comandos para o
worker sem bloquear o usuario; riscos/nao objetivos: ainda nao escolhe provedor
de sessao, KMS ou contrato de cada ERP; teste/oraculo: testes de caso de uso,
matriz negativa de autorizacao e smoke HTTP; gate: nenhuma rota fiscal ou de XML
entra antes de autenticacao e checagem centralizada de acesso por CNPJ.

## Papel da API

A API e o processo publico do FiscoNexa. Ela autentica identidades, autoriza
acesso, grava fatos e comandos duraveis e entrega dados ja processados. Ela nao
executa consulta SEFAZ, manifestacao ou download de XML durante uma requisicao.

```text
Cliente humano / ERP
        |
        v
  HTTP API (Horse)
        |
        +--> casos de uso --> PostgreSQL
        |                       |- dados de negocio
        |                       |- comandos fiscais
        |                       |- outbox/auditoria
        v
 resposta curta

FiscalWorker le comandos e eventos posteriormente.
```

## Fronteiras de codigo

| Camada | Responsabilidade | Regra |
| --- | --- | --- |
| `src/api` | Horse, rotas, middleware, JSON e mapeamento HTTP. | Nao usa FireDAC nem SQL. |
| `src/application` | casos de uso, transacao, autorizacao e publicacao de evento. | Nao conhece Horse, ACBr ou formato HTTP. |
| `src/domain` | entidades, regras e erros de negocio. | Sem banco, HTTP ou ambiente. |
| `src/persistence` | repositorios PostgreSQL, migrations e transacoes. | Nao retorna respostas HTTP. |
| `src/integrations` | adaptadores de storage, KMS e ERP. | So por interfaces definidas pela aplicacao. |
| `src/contracts` | DTOs de entrada/saida e contratos compartilhados. | Sem regra de negocio ou FireDAC. |
| `src/operations` | configuracao, logs, composicao e health. | Apenas conecta dependencias. |

O primeiro arranjo de pastas, sem criar abstracoes ainda, sera:

```text
apps/
  api/FiscoNexa.Api.dpr
src/
  api/              # Horse e HTTP
  application/      # casos de uso por capacidade
  contracts/        # DTOs e erros de contrato
  domain/           # regras puras
  persistence/      # repositorios e migrations PostgreSQL
  integrations/     # adapters externos
  operations/       # bootstrap, config e logs
tests/
  unit/             # domain/application sem HTTP
  integration/      # PostgreSQL real em Docker
  api/              # contrato HTTP e autorizacao
```

As units Delphi seguem nomes por camada e capacidade, por exemplo
`Application.Auth.RegisterUser`, `Domain.Access.CompanyGrant` e
`Api.Routes.Auth`. Diretorios novos somente entram junto do primeiro caso de uso
que os exigir.

## Ciclo de requisicao

1. Middleware atribui `request_id`, inicia log estruturado e limita tamanho do
   corpo.
2. Middleware resolve a identidade: usuario humano ou token de integracao.
3. A rota valida apenas sintaxe e transforma JSON em DTO.
4. O caso de uso valida regra de negocio e pede autorizacao por CNPJ a um unico
   servico de acesso.
5. Repositorios alteram dados e outbox dentro de uma unica transacao.
6. A rota transforma resultado ou erro conhecido em resposta HTTP.
7. Middleware registra status, duracao e `request_id`, sem segredo.

Rotas nao recebem `company_id` como autorizacao. Esse campo e apenas alvo da
operacao; a permissao vem da identidade resolvida no passo 2.

## Identidades e autorizacao

Ha dois principals, representados internamente por uma interface unica:

| Principal | Credencial | Escopo maximo |
| --- | --- | --- |
| Usuario humano | sessao autenticada | grants ativos de usuario e organizacao |
| Integracao ERP | token opaco com hash armazenado | um CNPJ e os scopes do token |

`superadmin` e papel de plataforma, nao grant implicito aos CNPJs. Acesso de
suporte exige concessao temporaria auditada; essa rota nao faz parte da primeira
fatia.

O mecanismo concreto de senha, sessao, refresh e revogacao pertence ao
`AUTH-001`. A API depende apenas de `IRequestPrincipal`, para que a decisao nao
vaze pelas rotas.

## Superficies HTTP separadas

O prefixo organiza a API; a protecao real e feita pelo middleware de identidade
e audiencia. Uma credencial de ERP deve ser recusada no portal, e uma sessao
humana deve ser recusada nas rotas de integracao.

| Superficie | Prefixo | Principal aceito | Uso |
| --- | --- | --- | --- |
| Infraestrutura | `/health` | nenhum | health check local e do proxy. |
| Frontend | sem versao | usuario humano | portal web e aplicativo futuro. |
| Integracao REST | `/v1` | token de integracao ERP | consumo maquina-a-maquina. |
| Interno futuro | sem HTTP inicialmente | worker autenticado no banco | comandos e eventos; se houver HTTP, sera em rede privada com mTLS. |

Criar, rotacionar ou revogar token ERP e acao do frontend. O token serve apenas
para consumir a superficie REST `/v1`.

## Contrato HTTP comum

- Rotas do frontend nao recebem versao; a API REST de integracao usa `/v1`.
- `GET /health` fica sem versao para infraestrutura.
- JSON UTF-8; chaves em ingles `snake_case`.
- Datas em ISO-8601 UTC (`2026-09-04T12:34:56Z`).
- UUIDs como strings canonicas; CNPJ somente 14 digitos, sem mascara no wire.
- Colecoes usam cursor opaco, nunca offset como contrato publico.
- Escritas que podem sofrer retry aceitam `Idempotency-Key`; sua semantica sera
  exigida primeiro em comandos fiscais e criacoes externas.

Resposta de erro padrao:

```json
{
  "error": {
    "code": "company_access_denied",
    "message": "Acesso nao permitido para esta empresa.",
    "request_id": "uuid"
  }
}
```

Erros de dominio possuem codigo estavel; `message` e voltada ao consumidor e
nunca contem SQL, stack trace, token, senha ou certificado.

## Rotas da primeira fronteira

| Grupo | Rotas | Condicao para iniciar |
| --- | --- | --- |
| Infraestrutura | `GET /health` | ja entregue |
| Frontend: identidade | registro, login, recuperacao e logout | `AUTH-001` |
| Frontend: empresa | criar/listar empresa e grants | `ACCESS-001` |
| Frontend: documentos | consultar documentos e configuracoes | `ACCESS-001` |
| Integracao REST | listar documento e obter XML | `ERP-001` e `STORAGE-001` |

Certificado, manifestacao, download e SEFAZ nao terao rota nesta etapa. A API
apenas criara um comando fiscal depois que autenticacao, cofre e idempotencia
forem validados.

## Persistencia, comandos e eventos

A API e responsavel por iniciar transacoes. Um caso de uso que muda estado e
notifica outro processo grava o fato de negocio e o registro da outbox na mesma
transacao. O publicador entrega a outbox depois; falha de entrega nao desfaz a
empresa, documento ou comando criado.

Para trabalho fiscal, a API grava um comando com:

- `company_id`;
- tipo de operacao;
- chave de idempotencia;
- estado e tentativas;
- `requested_by` e correlacao;
- payload minimo, sem certificado em plaintext.

O worker reclama o comando no PostgreSQL. Lock logico por CNPJ e transicao
atomica de estado impedem concorrencia contra a SEFAZ.

## Ordem de implementacao da API

1. `AUTH-001`: contrato de identidade, hash de senha, sessao e revogacao.
2. `AUTH-002..004`: rotas e testes negativos de identidade.
3. `ACCESS-001`: servico unico para grants de usuario, organizacao e ERP.
4. `COMPANY-001..003`: onboarding e compartilhamento de CNPJ.
5. `OUTBOX-001` e `AUDIT-001`: base para eventos e rastreabilidade.
6. `MONITOR-001` e `COMMAND-001`: API passa a solicitar trabalho ao worker.

Cada item e detalhado no [ledger](LEDGER.md); um item somente muda para `OK`
com o oraculo registrado executado.
