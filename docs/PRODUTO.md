# FiscoNexa - visao do produto

## Marca

- Nome: **FiscoNexa**
- Assinatura principal: **Da SEFAZ ao estoque, sem digitacao.**
- Marca de origem: **FiscoNexa by Delphos**
- Dominio: `fisconexa.com.br`, com pedido de registro numero `32124263`.
- Consulta preliminar do titular indicou disponibilidade da marca no INPI.

O nome combina fisco, nexo e conexao. Representa a ligacao entre SEFAZ,
empresa, ERP e contador.

## Problema

Empresas e contadores ainda dependem de consultas manuais, troca de XMLs,
acesso remoto, planilhas e digitacao repetida. Isso causa documentos perdidos,
entradas atrasadas, divergencias fiscais e retrabalho.

## Proposta de valor

> Todas as notas da empresa monitoradas, guardadas e entregues ao ERP e ao
> contador, prontas para virar operacao.

O diferencial da FiscoNexa nao sera somente guardar XML. Para ERPs integrados,
principalmente o Delphos, o documento deve seguir ate a pre-entrada, conferencia
tributaria, formacao de preco e faturamento.

Proposta sintetica:

> A FiscoNexa transforma documentos fiscais em tarefas prontas para empresas e
> contadores.

Slogan institucional:

> FiscoNexa - Clareza fiscal para empresas e contadores.

## Publicos

### Empresas

- Clientes Delphos, com integracao operacional nativa.
- Empresas que utilizam outros ERPs, por API ou conectores.
- Grupos com diversos CNPJs e necessidade de visao centralizada.

### Contadores

- Escritorios que precisam centralizar documentos de varios clientes.
- Acesso por competencia, empresa e tipo de documento.
- Exportacao em lote e integracao com sistemas contabeis.
- Alertas fiscais e acompanhamento de pendencias em fases posteriores.

## Produto inicial

### Fiscal Cloud

- Cadastro multiempresa e multi-CNPJ.
- Certificado A1 armazenado de forma segura.
- Monitoramento de NF-e e CT-e destinados ao CNPJ.
- Controle de NSU, intervalos, consumo indevido e recuperacao de lacunas.
- Manifestacao do destinatario.
- Download e guarda do XML e de seus eventos.
- Recepcao dos XMLs de venda enviados pelo ERP emissor.
- Consulta e download por API.
- Alertas de cancelamento, falhas e vencimento de certificado.
- Historico tecnico e trilha de auditoria.

### Portal da empresa e do contador

- Caixa de entrada de documentos e pendencias.
- Filtros por CNPJ, periodo, fornecedor, situacao e tipo.
- Download individual ou em lote.
- Compartilhamento controlado com o contador.
- Visao operacional: o que chegou, o que falhou e o que exige acao.

### Entrada assistida no ERP Delphos

- Baixar o XML da FiscoNexa.
- Criar pre-lancamento idempotente pela chave do documento.
- Relacionar fornecedor e produtos conhecidos.
- Sugerir unidade, fator de conversao, margem e preco.
- Destacar somente produtos e regras que exigem intervencao.
- Movimentar estoque, fiscal e financeiro apenas apos confirmacao do usuario.

## Evolucao do produto

1. Captura, manifestacao, cofre e API.
2. Portal do contador e envio das vendas pelo ERP.
3. Pre-entrada automatica no Delphos.
4. Conciliacao entre XML, cadastro e lancamentos do ERP.
5. Revisao de NCM, CFOP, CSOSN, CST, IBS/CBS e cClassTrib.
6. ICMS antecipado, substituicao tributaria e DAE.
7. Monitoramento e-CAC por integracoes oficiais do SERPRO.
8. Integracoes com outros ERPs e sistemas contabeis.

Detalhes da análise competitiva e do módulo de revisão fiscal assistida por IA
estão em [Pesquisa de mercado e oportunidades](PESQUISA_MERCADO.md).

## Referencias de mercado observadas

Robotax, Qive, SIEG, Fiscal.io e Jettax validam a demanda por:

- Captura e guarda de documentos fiscais.
- Integracoes com ERP e contabilidade.
- Manifestacao e eventos.
- Auditoria de cadastros e impostos.
- Comparacao de compras e vendas.
- Guias e monitoramento do e-CAC.

A oportunidade da FiscoNexa e reduzir a distancia entre o documento fiscal e a
operacao da empresa. A interface deve priorizar pendencias acionaveis, evitando
um produto composto apenas por graficos gerenciais.

## Precos iniciais para validacao

| Plano | Preco sugerido | Entrega principal |
| --- | ---: | --- |
| Documentos | R$ 49,90 por CNPJ/mes | Captura, cofre, eventos e exportacao |
| Operacao | R$ 99,90 por CNPJ/mes | Manifestacao, ERP e pre-entrada |
| Inteligencia | R$ 169,90 por CNPJ/mes | Conciliacao, divergencias e automacoes fiscais |

Oferta inicial sugerida para clientes Delphos: plano Operacao por R$ 69,90 por
CNPJ/mes durante a validacao comercial.

Planos para contadores devem possuir franquia de CNPJs, nunca uso ilimitado sem
controle de custo:

- Ate 10 CNPJs: R$ 249/mes.
- Ate 30 CNPJs: R$ 399/mes.
- Ate 100 CNPJs: R$ 699/mes.
- Excedentes cobrados por CNPJ.

Os valores sao hipoteses comerciais. O preco final depende do custo real de
storage, consultas, certificados, suporte, retencao e integracoes.

## Limites assumidos no MVP

- Certificados A1 inicialmente.
- A3 depende de agente local ou provedor de assinatura remota.
- A nuvem nao deve depender da Distribuicao DF-e para recuperar vendas. O ERP
  emissor envia o XML autorizado, protocolo e eventos.
- Apenas um monitor, local ou nuvem, pode controlar o mesmo CNPJ.
- Pre-lancamentos sao rascunhos; nenhuma movimentacao ocorre sem confirmacao.
- Calculos tributarios avancados exigem regras testaveis e validacao fiscal.
