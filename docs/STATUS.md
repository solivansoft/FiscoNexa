# Status

## Estado atual

- Nome FiscoNexa definido.
- Pedido de registro de `fisconexa.com.br` em processamento sob numero 32124263.
- Disponibilidade preliminar no INPI verificada pelo titular.
- Proposta de produto, precos iniciais e referencias de mercado documentadas.
- Pesquisa da Robotax e oportunidades de revisão fiscal por IA documentadas.
- Direcao arquitetural escolhida: Delphi + Horse + PostgreSQL.
- WMLC sera usado para compilar no Windows os binarios destinados ao Ubuntu.
- API e worker fiscal serao processos separados.
- Motor local do monitor SEFAZ existe no projeto `erp/services` e serve como
  referencia de regras de NSU, gaps, manifestacao e consumo indevido.

## Proximo passo recomendado

Executar `AUTH-001` do [ledger](LEDGER.md): contrato de credencial humana,
sessao, expiracao, revogacao e testes negativos. As proximas rotas, eventos e
camadas estao inventariados no mesmo documento por dependencia.

O alvo da primeira fatia vertical permanece:

- Empresa, CNPJ, usuario e permissao.
- Credencial de integracao do ERP.
- Cadastro de documento apenas com metadados e hash.
- Comando fiscal persistente.
- Worker simulado reclamando e concluindo o comando de forma idempotente.
- Build cruzado reproduzivel e deploy limpo no Ubuntu.
- Encerramento por `SIGTERM` e execucao sob `systemd`.

Depois, conectar o worker ACBr e validar uma consulta real em homologacao,
incluindo certificado A1, assinatura, schemas, TLS e recuperacao de falhas.

Em paralelo, validar com empresários e contadores as três primeiras análises do
FiscoNexa Oportunidades: monofásicos, compra versus venda e ICMS antecipado.
