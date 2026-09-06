# Fluxo de ativacao do modulo no ERP

Objetivo: resolver o monitoramento e o recebimento de XML sem exigir que o
cliente conheca token, CNPJ tecnico ou portal FiscoNexa.

## Jornada do cliente

1. No ERP, o cliente abre **Monitoramento de notas fiscais** e contrata/ativa o
   modulo para a empresa corrente.
2. Envia o certificado A1 `.pfx` e sua senha, depois confirma em
   **Validar e ativar**.
3. O FiscoNexa extrai CNPJ, razao social e validade do certificado. O ERP mostra
   esses dados para confirmacao, sem pedir CNPJ manualmente.
   Uma consulta cadastral externa complementa razao social, nome fantasia e
   endereco quando disponivel, mas nao bloqueia a ativacao.
4. A ciencia automatica e a baixa de XML iniciam habilitadas como politica
   interna do FiscoNexa; o ERP nao exibe esses controles ao cliente.
5. O monitoramento inicia automaticamente e o ERP exibe `Ativando`, `Ativo`, `Atencao` ou
   `Certificado proximo do vencimento`.
6. Notas localizadas aparecem na entrada de compras para importar ou
   pre-lancar.

## Regras fixas do modulo

- Monitorar notas recebidas inicia `Ativo` apos a validacao do A1; nao existe
  controle de ativar/desativar para o cliente nesta entrega.
- Ciencia automatica e baixa de XML sao habilitadas pelo backend e nao sao
  configuraveis pelo cliente.
- Depois de uma ciencia aceita, o XML e baixado, armazenado e retido.
- O token de tenant nunca e mostrado ao cliente. O ERP o armazena de forma
  protegida e o usa somente para o CNPJ correspondente.
- Vencimento, troca ou senha invalida do A1 impedem novo ciclo fiscal e devem
  gerar alerta no ERP.

## Dados retornados ao ERP

O ERP recebe somente informacao operacional relevante: `situacao`,
`intervalo_minutos`, `consultado_em`, `proxima_consulta_em`,
`ultimo_cstat` e `certificado_valido_ate`. Nao recebe token, segredo
ou controles internos de ciencia e baixa de XML.

## Contrato tecnico posterior

O ERP usa uma credencial bootstrap para ativar a empresa. O FiscoNexa cria o
tenant, armazena o A1 cifrado, gera o token de integracao do CNPJ e publica o
comando de monitoramento. A consulta SEFAZ nunca ocorre dentro da chamada HTTP
de ativacao.

## Cobranca e cancelamento

O ERP e a fonte de verdade da contratacao, preco, fatura e pagamento. O
FiscoNexa mantem somente a situacao operacional do direito de uso:
`ativo`, `suspenso` ou `cancelado`.

Quando o ERP cancela, envia um evento idempotente autenticado pelo token
bootstrap. O FiscoNexa interrompe novos ciclos, inclusive ciencia e baixa de
XML. Documentos e XMLs anteriormente retidos nao sao apagados pelo
cancelamento; a politica de acesso posterior sera definida separadamente.
