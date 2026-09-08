# Regras do projeto FiscoNexa

Este arquivo e a autoridade central das regras especificas do FiscoNexa. Toda
nova regra dada pelo responsavel pelo projeto deve ser registrada aqui antes de
orientar implementacoes futuras. Instrucoes de sistema, seguranca e `AGENTS.md`
prevalecem quando houver conflito.

## Qualidade e testes

- Testes unitarios devem validar algoritmos e servir de guardrails contra
  regressao.
- Testes unitarios Delphi devem usar `tests\TestFramework.pas`.
- Smoke tests de HTTP e PostgreSQL complementam os unitarios; eles nao os
  substituem quando houver algoritmo ou regra de negocio a proteger.
- Teste de carga do worker usa adaptador SEFAZ simulado, e seus numeros medem
  somente custo local de agendamento, concorrencia e memoria; nunca comprovam
  limite ou homologacao da SEFAZ real.
- Antes de qualquer listagem paginada de producao com UniDAC, validar em teste
  de integracao mais de 100 registros e o comportamento de `SmartFetch`; nao
  assumir que a paginacao funciona apenas pela primeira pagina.
- A validacao UniDAC deve reproduzir leitura completa de colecoes acima do
  lote de fetch (incluindo venda com 30 itens), leitura e escrita com e sem
  transacao, `SmartFetch` e cache ligados/desligados, e pagina SQL por
  `TUniQuery`. Nenhuma hipotese sobre `SmartFetch` entra em producao sem esse
  oraculo comparar quantidade, ordem, duplicacao e itens ausentes.

## Registro de mudancas

- Regras novas devem ser adicionadas sem apagar regras anteriores, salvo ordem
  expressa do responsavel pelo projeto.

## Entrega inicial por ERP

- A primeira entrega comercial opera somente por integracao com ERP; frontend
  nao e pre-requisito para cadastrar empresa, configurar monitoramento ou
  consumir documentos.
- O ERP envia o certificado A1 e a senha para iniciar o cadastro da empresa.
  A API deve obter CNPJ e validade do certificado, cifrar o material antes de
  persistir e, apos o cadastro confirmado, solicitar o inicio do
  monitoramento.
- A contratacao, ativacao e operacao inicial do modulo de monitoramento devem
  acontecer no ERP do cliente. O cliente nao recebe token, nao informa CNPJ
  manualmente e nao precisa acessar o FiscoNexa para a primeira entrega.
- Ciencia automatica e baixa de XML sao politicas internas do FiscoNexa e nao
  aparecem como escolha do cliente no ERP. No onboarding do modulo, ambas
  iniciam habilitadas.
- O operador pode desligar temporariamente a ciencia automatica apenas por
  `FISCONEXA_AUTO_AWARENESS=false` para a primeira consulta homologada de um
  CNPJ. A variavel nao e contrato publico, nao aparece no ERP e o padrao de
  producao permanece `true`.
- O cliente nao configura o monitoramento. Ao validar o A1 no onboarding, o
  monitoramento inicia ativo por padrao. A API retorna apenas estado, intervalo
  efetivo, ultima e proxima execucao, sem expor controles de ativacao.
  Quando a ciencia for aceita, o download e a retencao do XML sao obrigatorios.
- Uma empresa pode conceder acesso simultaneo a varias organizacoes, incluindo
  varios escritorios contabeis. A relacao empresa-organizacao e N:N; o tipo da
  organizacao (contador, ERP ou revenda) e distinto do papel de acesso
  concedido a ela.
- O CNPJ extraido do certificado A1 e a fonte de verdade para o onboarding. A
  consulta externa de CNPJ enriquece o cadastro, mas falha, lentidao ou dado em
  cache nunca impedem a ativacao do monitoramento.
- A cobranca e a contratacao pertencem ao ERP. O FiscoNexa recebe somente o
  direito de uso do modulo, por evento autenticado e idempotente. Cancelamento
  interrompe novos ciclos de monitoramento, ciencia e download, sem apagar
  automaticamente documentos ou XMLs ja retidos.
- Cada ERP homologado possui credencial bootstrap exclusiva, rotacionavel e
  vinculada a sua organizacao. Essa credencial autentica onboarding e eventos
  de direito de uso, mas nao le documentos de nenhum CNPJ.
- O cadastro, rotacao e revogacao de credenciais bootstrap de ERP sao operacoes
  administrativas exclusivas do FiscoNexa; nenhuma credencial de ERP pode
  cadastrar ou alterar outro ERP.
- Ao ativar uma empresa, a credencial bootstrap cria automaticamente o vinculo
  entre o CNPJ e a organizacao do ERP emissor. Esse vinculo nao transfere a
  propriedade do CNPJ e nao impede grants posteriores para contadores ou outros
  ERPs homologados.
- O onboarding do ERP e idempotente pela combinacao da organizacao ERP, CNPJ
  extraido do A1 e `Idempotency-Key`. Reenvio nao pode duplicar empresa,
  certificado, modulo, integracao ou comando de monitoramento.

## Nomenclatura

- Atualizacao expressa do responsavel: rotas tecnicas seguem convencoes em
  ingles (`/health`, `/admin`, `/auth/login`, `/auth/logout`, `/auth/refresh`
  e `/auth/password`). Portugues fica para recursos especificos do negocio,
  como empresas, documentos, monitoramento, assinaturas e cobrancas. Esta
  regra especializa a orientacao anterior de rotas em portugues.
- O painel consome a API; regras de negocio e autorizacao pertencem ao backend.
  Qualquer usuario autenticado pode cadastrar seu ERP, sendo contador ou nao,
  sem receber privilegios administrativos da plataforma. Onboarding de empresa
  deve funcionar tanto pelo ERP quanto pelo usuario no painel, com validacao
  de certificado e vinculo de acesso. Estas regras substituem a exclusividade
  administrativa anterior para gestao de credenciais dos proprios ERPs.

- Rotas publicas usam colecoes curtas em portugues do Brasil, minusculas e no
  plural. Quando um segmento composto for inevitavel, usa `kebab-case`; por
  exemplo, `/admin/erps`, `/empresas`, `/monitoramento` e `/modulos`.
- Tabelas usam substantivos simples no plural e nao recebem prefixo tecnico de
  camada ou modulo. Seguem a mesma semantica das rotas; em nomes compostos,
  usam `snake_case`, pois hifen nao e apropriado em SQL. Tabelas de relacao
  usam os dois substantivos envolvidos.
- Campos do banco usam `snake_case` em portugues do Brasil, com nomes curtos e
  compreensiveis. Termos fiscais padronizados pelo ecossistema NF-e, como
  `cnpj`, `nsu`, `cstat`, `xml` e `chave_acesso`, permanecem inalterados.
- Valores persistidos que representam acao ou estado do dominio tambem usam
  portugues do Brasil. Em especial, comandos de worker usam verbos como
  `iniciar_monitoramento`, `registrar_ciencia` e `baixar_xml`; nao usar
  codigos ingleses como `start_monitoring` ou `retrieve_xml`. Siglas e codigos
  normativos da NF-e permanecem como definidos pela SEFAZ.
- Dicionario minimo: `empresa_id`, `organizacao_id`, `usuario_id`,
  `criado_em`, `atualizado_em`, `revogado_em`, `situacao`, `tentativas`,
  `proxima_consulta_em`, `ultima_consulta_em`, `ultimo_nsu`, `ultimo_cstat`,
  `chave_acesso`, `tipo_documento`, `cnpj_emitente`, `valor_total`,
  `xml_chave_objeto` e `xml_sha256`. Rotas, parametros e campos JSON publicos
  usam portugues do Brasil em `snake_case`. Siglas e codigos fiscais
  estabelecidos, como `cnpj`, `nsu`, `cstat` e `xml`, permanecem inalterados.
  Cabecalhos HTTP padronizados, como `Authorization` e `Idempotency-Key`,
  tambem permanecem inalterados.
- Cada tabela possui uma unit declarativa correspondente em
  `src/persistence/schema`, nomeada como `Tables.<NomeFisicoEmPascalCase>.pas`.
  Exemplo obrigatorio: tabela `documentos`, unit `Tables.Documentos.pas` e
  funcao `DocumentosTable`. A unit nunca recebe nome tecnico ou ingles que
  divirja da tabela que ela declara.
- Contratos publicos nao usam termos internos como `bootstrap`, `entitlement`
  ou `vendor`.

## Implementacao incremental

- O ledger define a ordem da implementacao; o proximo item elegivel e a unica
  mudanca funcional em curso.
- A evolucao do schema e aplicada pelo executavel da API e organizada por
  tabela, nao por uma sequencia de units de migration. Cada unit declara a
  propria tabela por metadados e `AddField`; o motor PostgreSQL compara essa
  declaracao com o catalogo, cria tabela/campo/indice/constraint ausente e
  aplica somente mudancas compativeis. Adicionar campo novo significa alterar
  somente a unit da tabela correspondente. Mudancas destrutivas ou ambiguas
  falham de modo explicito e nunca descartam dados automaticamente.
- Units, classes e metodos devem ter responsabilidade unica, nomes legiveis e
  fluxo sequencial simples. Metodos pequenos devem separar validacao, regra de
  negocio, persistencia e integracao externa.
- Camadas permanecem desacopladas: rotas nao usam SQL, aplicacao nao conhece
  Horse e integracoes externas ficam atras de contratos da aplicacao.
- Toda regra de negocio ou algoritmo novo possui teste unitario no framework
  do projeto antes de ser considerado concluido; migrations e rotas tambem
  exigem teste de integracao ou smoke reproduzivel.

## Monitoramento SEFAZ DF-e

- O cursor `ultNSU` pertence ao CNPJ e o monitoramento principal por
  `distNSU` deve respeitar a janela retornada pela SEFAZ: respostas `137`
  (sem documentos), `656` (consumo indevido) e `138` que alcanca `maxNSU`
  agendam a proxima consulta para uma hora mais margem de seguranca. A
  cadencia nao e configuravel por prioridade comercial.
- Em `138`, enquanto `ultNSU < maxNSU`, o worker continua consumindo lotes
  imediatamente, com limite operacional por ciclo; ao alcancar `maxNSU`,
  entra na janela de espera.
- Em `656`, o `ultNSU` devolvido pela SEFAZ e a nova referencia do cursor.
  Se ele avancou em relacao ao cursor local, registrar a lacuna do proximo
  NSU local ate o NSU devolvido. Nunca insistir no cursor antigo.
- Lacunas de NSU sao recuperadas por `consNSU`, em fila separada do
  monitoramento principal. Por CNPJ, consultas pontuais possuem intervalo
  minimo de cinco minutos e limite preventivo de quinze por hora; consulta
  principal pendente tem prioridade sobre recuperacao de lacuna.
- Lock, lease, cursor, proxima consulta, bloqueio, contagem e lacunas sao
  estado persistido por CNPJ. Nenhuma dessas garantias pode depender de
  memoria de um worker.
- Empresa sem certificado A1 ativo, ou cujo `valid_until` seja anterior a
  data atual, nao entra no monitoramento principal nem na recuperacao de
  lacunas. O worker nao consulta a SEFAZ, manifesta nem baixa XML nesses casos.
- O envio de A1 renovado substitui atomicamente o material cifrado, senha,
  hash e `valid_until` do certificado ativo; a volta ao monitoramento decorre
  somente dessa validacao, sem ativacao manual e sem permitir renovar apenas a
  data de um certificado vencido.
- O worker usa o A1 somente em memoria, pelo campo `DadosPFX` do ACBr. Nao
  instala certificado no Windows, nao usa numero de serie e nao grava PFX ou
  senha em arquivo temporario.
- O conector ACBr da SEFAZ deve operar com `SSLLib = libOpenSSL`. Nao pode
  fixar `httpWinINet` nem outra biblioteca exclusiva do Windows; a mesma
  configuracao precisa compilar e executar em Windows e Ubuntu, com as
  bibliotecas OpenSSL da plataforma.
- Ciencia automatica permanece a politica padrao. Para excecoes, o ERP pode
  solicitar ciencia pontual de um documento pendente do proprio tenant; a API
  grava comando idempotente e responde de forma assincrona, sem consultar a
  SEFAZ na rota.
- Fluxo fiscal normal: o ERP cria ou ativa a empresa enviando A1, senha e UF;
  o FiscoNexa inicia o monitoramento. Ao localizar um resumo sem XML completo,
  o worker registra Ciencia da Operacao automaticamente, agenda a nova
  consulta necessaria, baixa o XML autorizado, envia-o ao S3 e materializa o
  documento para o tenant. O ERP apenas lista documentos pelo seu NSU proprio
  e solicita o XML pelo identificador do documento. Se ainda nao houver XML,
  o ERP pode solicitar manifestacao pontual somente para documento pendente do
  proprio tenant; a solicitacao e um comando assincrono e idempotente.
- O smoke de monitoramento sem ciencia valida somente onboarding, lease,
  consulta SEFAZ e persistencia da janela. A liberacao de producao do fluxo
  fiscal exige um segundo smoke vertical, expressamente autorizado pelo titular
  do CNPJ, que prove ciencia, reconsulta, XML no S3 e leitura pelo token ERP.
- O worker fiscal e um motor de estado persistido por CNPJ, nao um fluxo linear
  de sucesso. Cursor, ultima resposta, proxima consulta, bloqueio, tentativas,
  leases, documentos pendentes, comandos ERP e lacunas pertencem ao banco e
  sobrevivem a reinicio, erro de processo e escala horizontal.
- A consulta principal por `ultNSU`, a recuperacao pontual de lacuna e a
  manifestacao/download sob demanda sao filas distintas. A consulta principal
  tem prioridade; recuperacao pontual nunca pode gerar abuso, repetir antes de
  cinco minutos ou ultrapassar quinze consultas por hora por CNPJ.
- Em resposta `656`, o worker interrompe novas consultas daquele CNPJ, persiste
  a janela de espera e o `ultNSU` retornado. Se o NSU retornado avancou por
  acao de outro robo, registra lacuna para recuperacao pontual; nunca repete o
  cursor antigo. A proxima elegibilidade ocorre somente uma hora e trinta
  segundos apos a resposta que gerou o bloqueio; nunca antes. Falha tecnica, timeout ou resposta desconhecida tambem entra
  em backoff persistido, sem loop imediato.
- Pedido de XML pelo ERP nunca consulta a SEFAZ na rota. Se o XML estiver no
  S3, a API o entrega. Se houver documento pendente sem XML, a API cria um
  comando idempotente e assincrono para ciencia/reconsulta; pedidos repetidos
  do mesmo tenant e documento compartilham o mesmo comando. O tenant nunca
  escolhe CNPJ nem acessa documento, comando ou XML de outro tenant.
- A sincronizacao de documentos para ERP usa `nsu` sequencial proprio do
  FiscoNexa, nao o `ultNSU` da SEFAZ. Na carga inicial o ERP envia `nsu=0`;
  nas proximas consultas envia o maior NSU confirmado. A resposta e paginada,
  ordenada de forma crescente e informa o ultimo NSU devolvido para permitir
  retomada idempotente. O ERP espelha os documentos localmente e decide quais
  ainda nao foram faturados; o FiscoNexa nao recebe estado de faturamento.
- Contratacao, ativacao, suspensao e cancelamento de modulo devem registrar o
  ator por identificador imutavel, nunca por nome duplicado: `user_id` para
  portal e `erp_key_id` para chamadas ERP. A auditoria tambem registra acao,
  horario UTC e contexto da requisicao; o nome e resolvido para exibicao. Em
  chamadas pelo ERP, a origem deve ser uma instalacao previamente identificada,
  e nao um nome de maquina enviado livremente.
- O `POST /v1/empresas` consulta a ReceitaWS pelo CNPJ extraido do A1 e
  preenche os dados cadastrais da empresa. O campo `state` e opcional quando
  a consulta retorna UF valida; UF explicitamente informada prevalece.
  Falha externa nao impede onboarding com UF informada, nem apaga dados
  cadastrais existentes. Sem UF informada ou obtida, retornar erro explicito
  solicitando `state`, sem ativar monitoramento com UF presumida.
  A UF e persistida com o CNPJ e
  usada pelo worker como UF e `cUFAutor` na Distribuicao DF-e.
- Chaves bootstrap de ERP sao criadas, rotacionadas e revogadas somente pelas
  rotas administrativas internas, autenticadas por sessao de superadmin. O
  primeiro superadmin nasce em bootstrap unico e nao por migration; o segredo
  bruto de uma chave ERP aparece apenas na resposta de criacao/rotacao, e o
  banco guarda exclusivamente seu SHA-256.
- Toda rota nova exige teste automatizado de contrato e de acesso antes de ser
  considerada pronta: ausencia de credencial, token invalido/expirado ou
  revogado e papel/escopo insuficiente devem ser recusados. Nenhuma rota pode
  ficar publica por omissao.
- Antes do smoke fiscal de workers, um teste de integracao somente da API deve
  provar no PostgreSQL que o onboarding HTTP gravou empresa, certificado
  cifrado, vinculo ERP, modulo de monitoramento, estado inicial e comando de
  worker. Esse teste nao executa ACBr nem consulta a SEFAZ.
- Validacao em SEFAZ de producao requer CNPJ e certificado A1 explicitamente
  autorizados para o piloto. A consulta de distribuicao e o envio de ciencia
  sao etapas separadas: nenhum teste tecnico pode registrar ciencia automatica
  em producao sem a autorizacao operacional do responsavel pelo CNPJ.

## Versao inicial sem legado

- O projeto ainda nao roda em nenhum ambiente. Nesta versao inicial, usar um
  unico schema e contrato finais; nao manter compatibilidade com nomes ou
  formatos intermediarios, fallbacks de legado ou codigo morto.

## Operacao continua e observabilidade

- API e worker devem operar continuamente na VPS Ubuntu. Bloqueio SEFAZ pausa
  somente o trabalho fiscal do CNPJ ate o prazo persistido; nao derruba a API,
  nao zera cursor e nao antecipa consulta ao reiniciar ou escalar instancias.
- Os smokes podem executar no Windows ou no WSL; validacao Windows nao
  substitui compilacao e execucao dos binarios destinados ao Ubuntu.
- Implementar logs estruturados e coleta centralizada para API e worker em
  cluster, identificando servico, instancia, versao, horario UTC e severidade.
  Correlacionar requisicao HTTP, empresa por identificador interno, tarefa,
  tentativa e resultado fiscal, incluindo cStat e proxima elegibilidade.
- Logs nao contem senha, token, certificado A1, chave privada nem conteudo
  integral de XML fiscal. A infraestrutura de coleta, busca, retencao e
  alertas sera definida no item de observabilidade do ledger.

## Migracao FireDAC ? 2026-09-06

Por autorizacao expressa do operador, FireDAC substitui UniDAC no acesso PostgreSQL da API, worker e testes compartilhados. As regras anteriores de UniDAC ficam como historico; a exigencia de leitura completa, paginacao e transacoes permanece para FireDAC, com fetch sob demanda e integral. Nao executar fluxos fiscais reais para validar a migracao.
