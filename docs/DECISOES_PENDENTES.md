# Decisoes pendentes

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
