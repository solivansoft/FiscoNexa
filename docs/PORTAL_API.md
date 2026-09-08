# Portal de integracao

- Producao: https://api.fisconexa.com.br/docs
- Homologacao: https://sandbox.fisconexa.com.br/docs
- Contrato para Postman/geradores: `/docs/openapi.json` em cada ambiente.

O portal publico Scalar apresenta 11 operacoes de integracao, exemplos de entrada, modelos
de resposta, erros, credenciais e guias de ativacao, documentos, XML e cobranca.
O teste interativo usa a origem atual. Homologacao possui dados/credenciais
separados e nao monitora certificados de producao.

O Caddy serve `/docs` e seus assets; a API continua responsavel pelas rotas de
negocio. Documentacao de integracao e health sao publicos. Login recebe email/senha e renovacao
recebe token no corpo. As demais 18 operacoes exigem a credencial indicada;
o webhook usa `asaas-access-token`, nao o token de tenant.

O contrato completo (21 operacoes) fica em `docs/openapi-interno.json`, fora
da pasta publicada. Para acessa-lo, abra `/docs/interno.html` e informe um
token de sessao de superadmin. A pagina busca `GET /admin/documentacao`
com Authorization: Bearer; o servidor valida sessao e papel, responde sem cache
e nunca aceita token por parametro de URL. O formulario vazio nao inclui o
contrato interno. Tokens ficam somente na memoria da pagina.

Administracao, sessoes humanas e webhook nao aparecem no contrato publico,
nem no JSON baixado. A assinatura documentada e do servico FiscoNexa, paga
pelo tenant a FiscoNexa; o integrador envia plano_codigo, nunca valores.

## Manutencao e gates

Fonte completa do contrato: `docs/openapi-interno.json`. Gere a projecao publica
com `python scripts/public_api_spec.py`; a lista de publicacao e explicita.
Matriz independente de acesso e
corpos de teste: `tests/api-access-policy.json`. Toda rota Horse nova deve
constar em ambos. Excecoes publicas precisam de revisao explicita no teste.

```bat
python -m pip install -r tests/requirements-api.txt
python tests/test_api_contract.py
python -m unittest discover -s tests -p test_api_contract.py
scripts\test-api-security.bat
```

O ultimo comando compila a API e executa testes HTTP com PostgreSQL real em
base local exclusiva `fisconexa_api_guardrail`. Requer o container de teste
`fisconexa-assinaturas-teste`, usuario `assinaturas_teste`, porta local 5438;
nao usa certificados, SEFAZ, KMS ou tokens de cobranca reais. Cria fixtures e
inicia/encerra somente seu processo na porta 19009. Os dados de fixture ficam
nesse banco dedicado, sem tocar a base do projeto.

Cobertura: 56 negativas basicas (18 operacoes x 3 credenciais invalidas/ausentes,
mais login e renovacao invalidos), 141 verificacoes adicionais de classe de
credencial, escopo, revogacao, expiracao, usuario desabilitado e isolamento de
documentos/cobrancas. Respostas positivas selecionadas sao validadas contra
os schemas OpenAPI. Onboarding positivo completo continua no E2E A1/KMS/S3.

CI e `build-api.bat` verificam o contrato/inventario. CI tambem verifica que o
instrumento reprova sucesso indevido, rota ausente e falha interna. A suite
HTTP com fixtures roda localmente; nao existe runner Delphi hospedado no CI.
O instalador Linux executa as 56 negativas contra o binario instalado, antes
de aceitar a release e retomar os timers. Falha aciona o rollback existente.
Isso nao equivale a auditoria completa de seguranca ou cobertura de todo payload.

## Publicacao

```bat
python scripts/deploy-api-docs.py fisconexa.vps
```

O publicador valida o contrato, transfere um pacote com SHA256, cria release em
`/var/www/fisconexa-api-docs/releases`, troca `current` e recarrega somente o
Caddy. Salva backup da configuracao e restaura em caso de falha. O snippet
`/etc/caddy/fisconexa-docs.caddy` e compartilhado pelos dois dominios; os demais
sites/proxies sao preservados. Publicacao da API/binario segue o instalador Linux.

Scalar 1.68.0 servido localmente, com hash em `scalar-version.json` e licenca
em `scalar-LICENSE.txt`. Atualizar bundle, licenca e hash juntos e repetir
validacao visual. Sem persistencia de tokens, telemetria, fontes externas ou
proxy externo. CSP limita scripts e conexoes a mesma origem.
