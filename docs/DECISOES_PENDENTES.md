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

## Inteligência fiscal

- Definir fontes oficiais, versionamento e vigência das regras tributárias.
- Definir o limite entre cálculo determinístico e análise por IA.
- Definir revisão e responsabilidade profissional antes de alterar dados ou
  declarações.
- Escolher o primeiro estado e segmento do piloto de ICMS-ST/antecipação.
