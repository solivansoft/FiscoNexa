# Contrato publico da API em portugues

Problema: as rotas e os campos JSON publicos usavam ingles enquanto banco,
produto e integradores do FiscoNexa operam em portugues do Brasil; evidencia:
as rotas anteriores usavam termos ingleses; invariante: a primeira versao nao mantem aliases ou
compatibilidade de contrato, e siglas fiscais e cabecalhos HTTP padronizados
permanecem reconheciveis; causa/hipotese: traduzir o contrato antes da primeira
liberacao elimina ambiguidade para ERPs e evita uma migracao publica posterior;
referencia: `REGRAS.MD`; solucao: rotas, parametros, campos e valores de
dominio publicos em portugues `snake_case`, com `cnpj`, `nsu`, `cstat`, `xml`,
`Authorization` e `Idempotency-Key` preservados; previsao: um integrador
consome somente termos em portugues e dados de documento suficientes para sua
lista; riscos/nao objetivos: nomes internos e schema preexistente nao sao
renomeados nesta decisao; teste/oraculo: smokes HTTP exercitam apenas as novas
rotas e validam os nomes do payload; gate: nao resta rota ou campo ingles no
contrato documentado da primeira versao.

Pedido de XML sem arquivo retido; evidencia: a SEFAZ pode devolver somente o
resumo e `596` ou `655` ja ocorreram no piloto; invariante: a rota HTTP nunca
consulta a SEFAZ e uma recusa final nao inicia novas tentativas pontuais; causa:
o worker e o unico executor fiscal e a ciencia pode ser inelegivel; solucao:
responder `202` enquanto o comando aguarda ciencia/reconsulta e `409` com
`ciencia_cstat` para `596` ou `655`; previsao: o ERP sabe quando aguardar e
quando nao insistir; riscos/nao objetivos: o monitoramento principal ainda
pode receber XML posteriormente; teste/oraculo: unitario de desfecho e smoke
HTTP sem criacao de comando; gate: 596/655 nao permanecem pendentes.
