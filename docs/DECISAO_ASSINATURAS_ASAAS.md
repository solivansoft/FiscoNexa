# Assinaturas diretas e pagamentos Asaas

Problema: tenants precisam contratar o FiscoNexa no ERP com teste gratuito e
pagamento direto; evidencia: existe apenas bloqueio pela licenca do parceiro;
invariante: token identifica o tenant, preco vem do servidor, repeticao nao
duplica cobranca nem periodo, sandbox nao concede acesso em producao, renovacao
preserva prazo restante e recadastro nao reinicia trial; solucao: planos,
assinaturas, cobrancas com preco congelado e eventos idempotentes, pagamento avulso
Asaas e consulta autenticada do pagamento antes de conceder acesso.

Politica inicial: R$49,90 mensal, R$149,70 trimestral e R$499,00 anual;
15 dias de teste desde ativacao (tenants atuais desde migration), avisos a tres
dias e no ultimo dia; protecao de monitoramento por 30 dias apos vencimento.
Assinatura direta governa seu acesso independentemente da licenca do ERP.
Contratacao por parceiro continua representada explicitamente. Portal fica
para outra entrega; toda interacao de assinatura e pagamento ocorre por API.

Riscos: timeout depois de criar pagamento remoto, reenvio ou inversao de
webhooks, pagamento atrasado, estorno e troca de ambiente. Reserva local e
referencia externa permitem reconciliar criacao ambigua; nao repetir POST
financeiro sem evidencia. Webhook consulta o estado atual no Asaas, verifica
cliente, referencia, valor e modalidade; periodos pagos sao recalculados de
registros confirmados, excluindo estornos. Credenciais ficam fora do Git.

Oraculo/gate: migrations reaplicaveis; testes de isolamento, trial, vencimento,
renovacao antecipada, duplicacao, conflito, webhook autenticado e estorno;
build Windows/Linux; smoke sandbox completo via rotas e spike ERP. Producao
mantem cursores, certificados, documentos e XML existentes.

Referencias: https://docs.asaas.com/reference/criar-nova-cobranca,
https://docs.asaas.com/reference/obter-qr-code-para-pagamentos-via-pix,
https://docs.asaas.com/docs/webhook-para-cobrancas.

Isolamento de homologacao: mesmo host Ubuntu, usuario systemd, binario, porta
localhost 9001 e banco/papel PostgreSQL exclusivos. Caddy publica subdominio
sandbox com HTTPS; sem worker fiscal, certificados ou credenciais da base real.
Oraculo: health publico, 401 sem segredo, evento real Asaas persistido, periodo
concedido uma vez e API/worker de producao ainda ativos.

Evidencia de estorno: resposta real retornou refunds com estado
AWAITING_CRITICAL_ACTION_AUTHORIZATION e pagamento RECEIVED. A mera existencia
de refunds nao significa dinheiro devolvido. Usa-se refunds[].status=DONE e
valor positivo para reconhecer estorno parcial, conforme
https://docs.asaas.com/docs/estornos. Teste distingue pedido pendente, cancelado,
array null e estorno concluido de um centavo. Nao conceder periodo integral
com devolucao parcial; remocao do periodo desta cobranca e politica inicial.

Recusa financeira HTTP 400/401/403/422 permite nova tentativa apos correcao;
timeout/5xx permanece ambiguo e e conciliado por referencia externa. Cada
retentativa consulta o provedor antes de criar. Falhas do conciliador registram
identificador local e classe do erro, sem token, corpo financeiro ou segredo.

Escolha do pagador: usuario validou a fatura com billingType UNDEFINED, que
mantem QR Pix disponivel e permite cartao. API devolve url_pagamento da propria
cobranca; dados de cartao ficam na pagina Asaas. CONFIRMED de cartao concede
periodo, distinguido como confirmada de recebida; Pix CONFIRMED nao concede,
pois pode ser retencao preventiva. aprovada_em fixa o inicio da concessao e a
liquidacao posterior preenche recebida_em sem comprar outro periodo.
Oraculo: cartao ficticio recusado nao concede, aprovado via callback concede
uma vez, QR e URL coexistem, SQL confirmou que liquidacao tardia nao muda prazo.
Referencias: https://docs.asaas.com/docs/cobrancas-via-cartao-de-credito e
https://docs.asaas.com/reference/obter-qr-code-para-pagamentos-via-pix.
