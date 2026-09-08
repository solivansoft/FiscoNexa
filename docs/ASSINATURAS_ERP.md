# Assinaturas, Pix e fatura Asaas no ERP

Autenticacao: `Authorization: Bearer <token da integracao do tenant>`.
O token Asaas e o segredo do webhook ficam exclusivamente no servidor.
Producao usa `https://api.fisconexa.com.br`; homologacao usa
`https://sandbox.fisconexa.com.br` com banco e credenciais separados.

## Fluxo da tela

1. Ao abrir o modulo, consulte `GET /v1/assinatura`. Use `acesso` para habilitar
   as operacoes e apresente `avisos`. Atualize em 300 segundos ou apos pagamento.
   Nao bloqueie o faturamento proprio do ERP pelo vencimento deste servico.
2. `GET /v1/planos` fornece precos em centavos, meses e economia. O servidor
   calcula o valor; a requisicao de pagamento nao recebe valor do desktop.
3. Se `cobranca_pendente` estiver preenchida, consulte seu `id_cobranca` para
   retomar o Pix. Para trocar de plano, cancele a cobranca aberta primeiro.
4. `POST /v1/cobrancas`, cabecalho `Idempotency-Key: <UUID persistido no ERP>`,
   corpo `{"plano_codigo":"mensal"}`. Codigos: mensal, trimestral e anual.
   Reutilize a MESMA chave apos timeout. Uma nova compra recebe outra chave.
5. Exiba `pix.imagem_base64` como PNG e `pix.copia_cola` como texto copiavel.
   Ofereca tambem "Pagar no navegador" usando `url_pagamento`. A cobranca e
   criada com billingType UNDEFINED: o Asaas apresenta as formas disponiveis
   na conta, incluindo cartao. Link e QR Code identificam a MESMA cobranca.
   Respeite `pix.expira_em`. Consulte `GET /v1/cobrancas/{id_cobranca}` a cada
   dez segundos enquanto a tela estiver aberta, com backoff em erros.
6. Quando `pagamento_aprovado=true`, aplique o objeto `assinatura` retornado,
   mostre "Pagamento aprovado" e feche a tela do Pix. Cartao pode estar
   `confirmada`, antes da liquidacao; Pix precisa estar `recebida`. Nao use
   apenas `assinatura.situacao=ativa`: um tenant pode estar pagando uma
   renovacao enquanto o periodo anterior continua valido.
   Fechar/reabrir o ERP nao perde o pagamento: webhook e conciliador persistem
   os eventos no servidor. O QR Code por si so nao concede acesso.

`DELETE /v1/cobrancas/{id_cobranca}` cancela uma cobranca pendente ou vencida.
Nao estorna pagamentos recebidos. Estornos feitos no Asaas sao conciliados.

## Resposta de assinatura

Campos: `id_empresa`, `modalidade`, `situacao`, `trial_iniciado_em`,
`trial_termina_em`, `pago_ate`, `valido_ate`, `dias_restantes`,
`monitoramento_protegido_ate`, `consultar_novamente_em_segundos`,
`cobranca_pendente`, `avisos` e `acesso`.

`acesso` contem `listar_documentos`, `baixar_xml`, `monitoramento` e
`gerenciar_assinatura`. Datas seguem ISO 8601; datas de vencimento da cobranca
sao `YYYY-MM-DD`. Campos sem valor sao `null`.

Situacoes da assinatura: `trial`, `ativa`, `vencida`,
`gerenciada_pelo_parceiro`. Situacoes da cobranca: `criando`, `pendente`,
`vencida`, `confirmada`, `recebida`, `cancelada`, `estornada`, `contestada`.

A cobranca retorna tambem `url_pagamento`, `forma_pagamento`,
`pagamento_aprovado` e `aprovada_em`. Formas em pt-BR: `a_escolher`, `pix`,
`cartao_credito`, `cartao_debito`, `boleto`. `recebida_em` registra a liquidacao;
`aprovada_em` registra a primeira concessao e nao muda quando o saldo chega.
Quando o cliente escolhe cartao, o objeto `pix` deixa de ser apresentado.

Cada aviso tem `id`, `codigo`, `nivel`, `mensagem` e `acao` com
`tipo`, `rotulo` e `rota`. Use o `id` para controlar repeticoes de aviso no
desktop; consulte novamente a assinatura antes de decidir acesso.

## Regras comerciais

- 15 dias de trial desde o cadastro validado. Tenants existentes recebem trial
  na primeira migration desta funcionalidade. Redeploy nao reinicia o trial.
- Mensal R$49,90; trimestral R$149,70; anual R$499,00. Valores iniciais
  configurados em `planos_assinatura`, sem limite de documentos por plano.
- Pagamento antecipado soma meses ao prazo existente. Apos vencimento, o novo
  periodo inicia na concessao. Periodos usam meses de calendario.
- Entrega bloqueada apos vencimento; monitoramento preservado por 30 dias,
  respeitando janelas SEFAZ e demais gates. Acesso a planos/pagamento permanece.
- Assinatura direta independe da licenca do ERP. A modalidade `parceiro`
  continua obedecendo ao controle comercial do parceiro.
- Pagamento avulso por Pix ou fatura, sem renovacao/debito automatico. Estorno integral ou parcial
  retira o periodo associado a essa cobranca; outros periodos sao preservados.

## Erros e concorrencia

401: token invalido; 403: escopo insuficiente; 404: recurso ausente ou de outro
tenant; 409: conflito de plano, operacao em andamento ou criacao ambigua;
422: dados invalidos; 503: provedor/configuracao indisponivel. Reconsulte a
assinatura para obter a cobranca aberta. Nunca gere chaves novas em loop.

Um envio interrompido apos POST financeiro permanece em conciliacao pelo
`externalReference`; nao se repete POST sem prova de recusa definitiva.
Casos ambiguos persistentes exigem investigacao operacional.

## Spike Delphi

Compile com `scripts\build-erp-spike.bat`. Executavel:
`bin\examples\win64\FiscoNexa.ErpSpike.exe`. Configure `FISCONEXA_API_URL` e
`FISCONEXA_ERP_TOKEN` no ambiente do processo, sem embutir chaves no fonte.

```text
FiscoNexa.ErpSpike.exe assinatura
FiscoNexa.ErpSpike.exe planos
FiscoNexa.ErpSpike.exe cobrar mensal pedido-000001 qrcode.png
FiscoNexa.ErpSpike.exe cobranca ID_COBRANCA
FiscoNexa.ErpSpike.exe cancelar-cobranca ID_COBRANCA
```

## Webhook e operacao

`POST /webhooks/asaas` valida `asaas-access-token` contra
`ASAAS_WEBHOOK_TOKEN` (32 caracteres ou mais). Usa API Asaas v3 e persiste o
evento antes do HTTP 200. O conciliador confirma cliente, referencia, valor,
forma e status na API Asaas. RECEIVED concede periodo; CONFIRMED concede
somente para cartao de credito/debito. Pix CONFIRMED em analise, cartao
AUTHORIZED e AWAITING_RISK_ANALYSIS nao concedem periodo.

Configure os eventos PAYMENT_CREATED, PAYMENT_UPDATED, PAYMENT_CONFIRMED,
PAYMENT_RECEIVED, PAYMENT_OVERDUE, PAYMENT_DELETED, PAYMENT_RESTORED,
PAYMENT_REFUNDED, PAYMENT_REFUND_IN_PROGRESS e PAYMENT_PARTIALLY_REFUNDED
quando disponivel. A conta pode ter webhooks adicionais; eventos de cobrancas
de outros produtos sao ignorados, sem conceder acesso.
Inclua tambem PAYMENT_CHARGEBACK_REQUESTED, PAYMENT_CHARGEBACK_DISPUTE,
PAYMENT_AWAITING_CHARGEBACK_REVERSAL e eventos de analise/captura do cartao.
Estorno e contestacao removem a concessao associada; o recebimento posterior
de um cartao confirmado nao duplica nem desloca o periodo comprado.

Homologacao na VPS: `fisconexa-sandbox-api.service` e
`fisconexa-sandbox-cobrancas.timer`; binario em
`/opt/fisconexa-sandbox/current`, logs em `/var/log/fisconexa-sandbox` e journal;
segredos em `/etc/fisconexa-sandbox/`. Porta 9001 somente em localhost, exposta
por Caddy/HTTPS. Banco `fisconexa_sandbox` na VPS de dados, via WireGuard.
Sem certificados de clientes nem worker fiscal neste ambiente.

Validacao publica reproduzivel: `python tests/smoke-assinaturas-vps.py`.
Teste de estorno: `python tests/smoke-assinaturas-estorno-vps.py`.
Ambos exigem as credenciais sandbox locais e SSH configurado; nunca usar
credenciais de producao nesses smokes.
Teste adicional de link, QR Code e cartao ficticio:
`python tests/smoke-assinaturas-cartao-vps.py`.
