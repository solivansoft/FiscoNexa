# Onboarding inicial por ERP e certificado A1

Problema: o ERP precisa cadastrar um CNPJ e iniciar o monitoramento sem frontend, mas o A1 e sua senha nao podem ser tratados como dado comum; evidencia: o token atual de ERP esta ligado a um unico CNPJ e so pode consumir documentos; invariante: plaintext do A1 e da senha nunca vai para log, evento, banco ou disco persistente, e um token de tenant nunca cadastra outro CNPJ; causa/hipotese: e necessaria uma credencial bootstrap do fornecedor de ERP, separada do token do tenant; referencia: `REGRAS.MD` e `docs/LEDGER.md`; solucao: credencial opaca com escopo `companies:onboard`, cofre por envelope usando chave KMS exclusiva para certificados e onboarding idempotente; previsao: a API extrai CNPJ e validade do A1, persiste somente dados cifrados, cria ou retoma a empresa, emite o token do tenant e grava o comando de monitoramento; riscos/nao objetivos: nao cria portal e nao executa SEFAZ na requisicao HTTP; teste/oraculo: reenvio idempotente, teste de cifra/recuperacao pelo worker e varredura de segredos; gate: `ERP-BOOTSTRAP-001`, `CERT-001` e `PILOT-002` aprovados antes de expor `POST /v1/empresas`.

## Credenciais distintas

| Credencial | Quem usa | Escopo |
| --- | --- | --- |
| Bootstrap ERP | Instalacao de um ERP homologado | Cadastrar ou retomar clientes e informar direito de uso; nunca le XML. |
| Token do tenant | ERP vinculado a um CNPJ | Listar e baixar XML somente do proprio CNPJ. |

## Fluxo alvo

```text
ERP -- bootstrap token + A1/senha --> POST /v1/empresas
API -- valida/cifra --> PostgreSQL
API -- transacao --> empresa + token tenant + comando monitorar
Worker -- reclama comando --> monitora SEFAZ
ERP -- token tenant --> GET /v1/documentos
```

O CNPJ informado pelo ERP nao e fonte de verdade: ele e extraido do certificado. O token do tenant e retornado uma unica vez e armazenado apenas como hash no banco.

Cada ERP homologado recebe credencial bootstrap exclusiva, vinculada a sua
organizacao, com hash persistido, escopos, rotacao, revogacao e auditoria. Ela
nao e compartilhada com outro ERP e nao concede leitura de XML.

No onboarding, a empresa recebe automaticamente um grant para a organizacao do
ERP que enviou a credencial bootstrap. O grant representa o vinculo operacional
e comercial, nao propriedade do CNPJ; outros grants podem coexistir.

## Primeira superficie HTTP

| Rota | Credencial | Funcao |
| --- | --- | --- |
| `POST /administracao/erps` | plataforma/superadmin | Cadastra ERP homologado e retorna chave uma unica vez. |
| `POST /v1/empresas` | bootstrap ERP | Recebe A1 e senha, cria/retoma empresa, vinculo e monitoramento. |
| `GET /v1/monitoramento` | token tenant | Retorna estado, intervalo, ultima/proxima consulta e documentos disponiveis do proprio CNPJ. |
| `PUT /v1/empresas/{id_empresa}/modulos/monitoramento` | bootstrap ERP autorizado | Informa `ativo`, `suspenso` ou `cancelado` sem dados de cobranca. |
| `GET /v1/documentos` | token tenant | Lista documentos prontos do proprio CNPJ. |

## KMS e cifra local

AWS KMS e o provedor escolhido, na chave simetrica
`fisconexa-certificates`. A API solicita uma data key ao KMS, cifra A1 e senha
localmente com AES-256-GCM e persiste somente a data key cifrada, ciphertext,
nonce e tag. A integracao usa HTTPS com AWS Signature Version 4; AWS CLI serve
somente para operacao e nunca como dependencia do processo da API.

## Persistencia da primeira entrega

| Tabela | Uso |
| --- | --- |
| `organizations` | ERP homologado, contador ou revenda. |
| `erp_keys` | Hash, escopos, rotacao e revogacao da chave exclusiva de cada ERP. |
| `companies` | CNPJ extraido do A1 e dados cadastrais essenciais. |
| `company_organizations` | Grant N:N; separa tipo de relacao (`erp`, `accountant`) de papel (`admin`, `viewer`). |
| `certificates` | A1 e senha cifrados, chave de dados cifrada pela KMS, validade e hash. |
| `monitor_settings` | Politicas internas de ciencia e baixa automatica. |
| `monitor_status` | Estado, intervalo, ultimo NSU, ultima/proxima consulta e erro operacional. |
| `commands` | Fila duravel e idempotente para monitorar, manifestar e baixar. |
| `company_modules` | Situacao operacional enviada pelo ERP, sem fatura, preco ou cartao. |
| `integrations` | Token hash de leitura, limitado a um CNPJ. |
| `documents` | Metadados dos documentos e referencia do XML no S3. |

## ReceitaWS no onboarding — 2026-09-06

Problema: cadastro guardava apenas subject do A1 e exigia UF manual.
Evidencia: servico nao possuia consulta cadastral; pedido explicito do operador.
Invariante: CNPJ vem do A1; resposta de outro CNPJ nunca enriquece o tenant;
UF nao e presumida e indisponibilidade externa nao apaga cadastro anterior.
Causa: integracao ReceitaWS ausente. Solucao: adaptador HTTPS com timeout,
uma tentativa por onboarding, sem retry imediato; guardar retorno JSON e data
da coleta em empresas, preencher nomes e usar UF retornada quando omitida.
UF explicita prevalece. Sem nenhuma UF valida, 422 `state_required`.
Previsao: cadastro completo pela rota padrao, sem mudanca do cursor fiscal.
Riscos: cache e limites do provedor; sem garantia de atualidade do cadastro ou
reprocessamento automatico de enriquecimento indisponivel nesta entrega.
Teste/oraculo: parser rejeita CNPJ divergente, UF invalida e resposta de erro;
servico cobre UF omitida/informada e falha externa; PostgreSQL preserva dados
no replay sem enriquecimento. Gate: 68 unitarios, suite local e integracao
cadastral aprovados; lote real confirma resposta com `cadastro_disponivel=true`.
Referencia: https://www.receitaws.com.br/api

## Compartilhamento futuro (contrato)

Empresa e organizacao se relacionam por grants N:N. Assim, o mesmo CNPJ pode
ser acessado por mais de um escritorio contabil sem transferir sua propriedade.
`organization_type` identifica se a organizacao e contador, ERP ou revenda;
o grant define o papel efetivo, como `admin` ou `viewer`.
