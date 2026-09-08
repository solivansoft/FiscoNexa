# Decisoes pendentes

## Portal de usuarios, contadores e ERPs — backlog de 2026-09-08

Registrado por solicitacao do responsavel. Todos os itens abaixo sao pendentes;
esta anotacao nao declara implementacao ou homologacao. O painel consumira a
API, que concentra regras de negocio e autorizacao. Estruturas existentes no
banco nao significam que os fluxos HTTP estejam completos.

### Funcionalidades a entregar

- [ ] Conta: cadastro de usuario, confirmacao de e-mail, recuperacao de senha,
  consulta/edicao do perfil e listagem/revogacao de sessoes. Reutilizar login,
  refresh, logout e troca de senha existentes.
- [ ] Organizacoes: cadastro de escritorio e organizacao ERP, convite e aceite
  de colaboradores, papeis/permissoes e remocao de membros.
- [ ] ERPs do usuario: qualquer usuario autenticado, contador ou nao, pode
  cadastrar ERP, listar os ERPs autorizados e emitir/rotacionar/revogar suas
  chaves. Nao conceder superadmin por esse cadastro. Hoje a gestao exige
  superadmin; falta implementar o fluxo do proprio usuario.
- [ ] Carteira: cadastrar empresa pelo painel com certificado, listar somente
  empresas autorizadas, compartilhar acesso e revogar vinculos. Preservar o
  onboarding existente por chave ERP e o fluxo simplificado do contador,
  com certificado e aceite de autorizacao descrito adiante neste documento.
- [ ] Certificados: consultar validade e renovar pelo painel sem reiniciar NSU,
  apagar documentos ou duplicar monitoramento.
- [ ] Documentos: consulta autorizada por empresa, periodo, emitente e situacao,
  download individual e exportacao mensal em ZIP. Exportacoes em lote devem
  executar em segundo plano, com consulta de andamento e entrega autorizada.
- [ ] Assinatura do escritorio: planos, franquia de CNPJs, uso, cobrancas e
  pagamentos da carteira. A assinatura direta do tenant ja existe; esta frente
  nao deve recria-la. Precos e limites do contador ainda precisam ser definidos.
- [ ] Avisos: central de notificacoes para certificado proximo do vencimento ou
  vencido, assinatura e pendencias de XML. Reutilizar os avisos comerciais ja
  existentes no retorno da assinatura; definir leitura e canais de entrega.
- [ ] Visao da carteira: indicadores de empresas ativas/inativas, validade de
  certificados, ultima/proxima consulta e documentos/XMLs disponiveis/pendentes,
  sempre limitados ao acesso do usuario. Grafana continua sendo operacional.
- [ ] Seguranca: limitacao de tentativas, recuperacao segura de conta, MFA para
  administradores e testes de isolamento entre usuarios e organizacoes.
- [ ] Higiene do planejamento: reconciliar ledger, status e pendencias antigas
  com codigo e evidencias; ha itens historicos pendentes ja entregues em outras
  frentes. Nao marcar conclusao apenas porque tabela ou rota existe.

### Contratos e decisoes antes da implementacao

- Separar usuario, organizacao, empresa e assinatura. Uma pessoa pode integrar
  um escritorio e cadastrar ERP; tipo de organizacao nao define privilegio de
  plataforma nem concede acesso automatico a CNPJs.
- Definir uma regra central de autorizacao por empresa, utilizada por todos os
  casos de uso do painel. Diferenciar leitura de XML, administracao de acesso e
  manifestacao fiscal. Revogacao deve valer nas requisicoes seguintes.
- Separar quem paga de quem acessa. Resolver a convivencia de assinatura direta
  da empresa e assinatura do escritorio: cobertura, franquia e responsabilidade
  pelo monitoramento compartilhado. Inadimplencia ou revogacao de um vinculo nao
  deve bloquear outro acesso coberto por contrato vigente, nem duplicar captura
  ou cobranca indevida.
- Manter rotas tecnicas em ingles convencional (`/auth`, `/admin`, `/health`) e
  recursos especificos do negocio em portugues. Contratos novos devem seguir
  essa convencao, sem aliases de nomes intermediarios.

### Ordem de entrega e gates

1. Reconciliar o planejamento e fechar cadastro, verificacao e recuperacao de
   conta, com tokens expiraveis/de uso unico e sem escalada de privilegios.
2. Organizar membros e permissoes; provar isolamento entre organizacoes e
   revogacao efetiva, inclusive para usuario que participa de mais de uma.
3. Liberar gestao dos proprios ERPs/chaves; provar que um usuario ou chave ERP
   nao administra organizacao alheia nem recebe privilegio de superadmin.
4. Entregar onboarding pelo painel e carteira; provar idempotencia, certificado
   valido, aceite quando aplicavel, vinculo autorizado e preservacao de NSU,
   documentos e acesso ERP existentes.
5. Entregar documentos, certificados, avisos e indicadores; provar filtros,
   paginacao e isolamento, inclusive apos revogacao e na renovacao de A1.
6. Entregar assinatura do contador e exportacoes em lote; testar coexistencia
   de contratos, inadimplencia, limites e acesso ao arquivo gerado. Definir os
   precos antes de ativar cobranca real dessa modalidade.

Cada entrega exige contrato OpenAPI, guardrail de autenticacao/autorizacao,
testes de regra de negocio e integracao apropriados. O portal nao deve receber
uma funcionalidade cuja autorizacao dependa somente da interface.

## Backend do nucleo SaaS

- Direcao escolhida: Delphi + Horse + PostgreSQL.
- Build Linux x64 pelo WMLC a partir do Windows.
- Pendente validar a fatia vertical e o pipeline de deploy no Ubuntu.

## Motor fiscal

- Opcao inicial: Delphi/ACBr em processo separado da API.
- Priorizar worker Linux gerado pelo WMLC quando todos os gates fiscais passarem.
- Manter worker Windows como alternativa para dependencias ou certificados
  incompatíveis com Linux.
- Lazarus/FPC permanece apenas como contingencia.

## API

- Resolvido para a entrega ERP: REST com sincronizacao por NSU proprio.
- Implementadas sessoes humanas e credenciais distintas de ERP/tenant; ver ledger.
- XML pendente retorna 202 e reutiliza o comando por tenant/documento.
- Pendente homologar o fluxo fiscal real do `MVP-006`.

### Manifestacao conclusiva e fechamento mensal

- Manter Ciencia da Emissao automatica quando a NF-e for localizada dentro do
  prazo, para permitir a obtencao do XML sem declarar que a operacao ocorreu.
- Nao registrar Confirmacao da Operacao automaticamente apenas para obter XML.
  Confirmacao, Desconhecimento ou Operacao Nao Realizada exigem decisao explicita
  do ERP/usuario ou evidencia confiavel do recebimento registrada pelo ERP.
- Criar `POST /v1/documentos/{id_documento}/manifestacoes`, idempotente e
  assincrono. Entrada minima: `tipo`, `baixar_xml` e `referencia_erp`. A API
  retorna 202; o worker manifesta, aguarda a propagacao da SEFAZ e agenda a
  obtencao do XML quando a manifestacao for aceita.
- Auditar ator/token ERP, tipo, referencia, data, cStat e resultado, sem registrar
  certificado, senha ou XML integral.
- Expor ao ERP os estados `xml_disponivel`, `manifestacao_pendente`,
  `prazo_expirando` e `indisponivel_por_prazo`.
- Alertar documentos sem XML aos 60, 75 e 85 dias e permitir manifestacao em
  lote no fechamento mensal. O lote deve exigir escolha explicita por documento
  ou evidencia do ERP; a necessidade contabil nao presume que a operacao ocorreu.
- Gate: confirmar em smoke real que uma manifestacao conclusiva aceita cria uma
  unica tentativa de download, persiste o XML no S3 e o disponibiliza somente ao
  tenant correto. Cobrir repeticao idempotente, cStat recusado, prazo expirado e
  isolamento entre tenants.

## Infraestrutura

- Escolher provedor da VPS, PostgreSQL e storage S3.
- Decidir banco autogerenciado ou gerenciado antes da producao.
- KMS/Vault para certificados: resolvido. Usar AWS KMS com a chave simetrica
  `fisconexa-certificates` e envelope encryption. O adaptador da API nao pode
  depender da AWS CLI.
- Definir politica de backup, retencao e recuperacao.

## Comercial

- Validar disposicao a pagar com clientes Delphos.
- Medir documentos por CNPJ e custo de storage/suporte.
- Revisar precos depois do piloto.
- Definir limites dos planos para contadores.
- Validar a disposição a pagar pelo módulo FiscoNexa Oportunidades.
- Decidir se o módulo será adicional ou parte dos planos superiores.
- Entrevistar contadores sobre monofásicos, ICMS antecipado e preparação para
  IBS/CBS antes de automatizar as regras.

## Proxima frente futura: carteira e painel do contador

Registrada em 2026-09-08 por solicitacao do usuario. Escopo futuro, ainda nao
implementado; inclui assinatura do escritorio e painel web do contador.

### Cadastro simplificado aprovado

- Problema/evidencia: o usuario atende empresas com pouca familiaridade com
  computadores; exigir portal ou aprovacao pelo ERP dificulta a adesao.
- O contador faz todo o cadastro: envia certificado A1 e senha; a API valida o
  certificado, identifica o CNPJ e busca os dados cadastrais.
- O contador declara: "Tenho autorizacao desta empresa para consultar seus
  documentos fiscais." Registrar ator, empresa, data e versao do aceite, sem
  expor certificado ou senha nos logs.
- Com validacao e aceite, ativar o vinculo conforme a assinatura do escritorio
  e iniciar o monitoramento respeitando as janelas da SEFAZ.
- O cliente nao precisa entrar em portal nem aprovar pelo ERP. Apenas informar
  um CNPJ nao concede acesso; posse do certificado nao substitui a autorizacao
  declarada pelo contador.

### Invariantes de acesso e cobranca

- Reutilizar empresa, acervo, NSU e monitoramento existentes por CNPJ; criar o
  vinculo do escritorio sem duplicar captura ou reiniciar o monitoramento.
- Vinculo nao transfere propriedade da conta nem remove acesso do ERP.
- Separar acesso aos XMLs de permissoes de manifestacao fiscal; nao confirmar
  operacoes automaticamente por necessidade contabil.
- Permitir revogar o vinculo sem apagar documentos ou historico da empresa.
- Assinatura do escritorio distinta da assinatura direta do tenant. Definir
  franquia de CNPJs ativos e precos; pacote de 1.000 CNPJs e ilimitado sao ideias
  em avaliacao, sem compromisso de oferta ou preco definido.
- Resolver antes da implementacao quem custeia o monitoramento compartilhado e
  como contratos do ERP e do escritorio convivem, inclusive inadimplencia e
  revogacao, sem bloquear acesso coberto por outro contrato vigente.

### Painel e evolucao

- Painel web com login do contador e carteira de empresas; adicionar/vincular
  empresas, consultar situacao do monitoramento e gerenciar certificados.
- Indicadores de empresas ativas/inativas, certificados vencidos ou proximos do
  vencimento, ultima consulta, documentos monitorados e XMLs disponiveis/pendentes.
- Consultar documentos por empresa e periodo; baixar XML individual e lote/ZIP
  mensal, mostrando pendencias de documentos ainda indisponiveis.
- Exibir assinatura do escritorio, uso da franquia, cobrancas e avisos.
- Evolucao posterior: ERP enviar XMLs de vendas e eventos associados, reunindo
  compras e vendas para o fechamento contabil.

### Previsao, riscos e gate

- Previsao: contador consegue cadastrar e acompanhar a empresa sem intervencao
  operacional do cliente, preservando isolamento e monitoramento existente.
- Riscos a resolver: vinculo indevido, conflito entre contratos e escritorios,
  tratamento seguro de certificados e custo de carteiras grandes.
- Gate antes de liberar: provar cadastro com certificado valido e aceite;
  rejeicao de certificado invalido e CNPJ divergente; ausencia de acesso somente
  por CNPJ; isolamento entre escritorios; revogacao efetiva; vinculo repetido
  idempotente; preservacao de NSUs, acervo e acesso ERP; coexistencia de contratos
  pagos/inadimplentes sem duplicar monitoramento ou cobranca indevida.

## Inteligência fiscal

- Definir fontes oficiais, versionamento e vigência das regras tributárias.
- Definir o limite entre cálculo determinístico e análise por IA.
- Definir revisão e responsabilidade profissional antes de alterar dados ou
  declarações.
- Escolher o primeiro estado e segmento do piloto de ICMS-ST/antecipação.
