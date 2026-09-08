# Contrato de integracao HTTP v1

Todas as respostas JSON usam UTF-8 e campos em portugues do Brasil com
`snake_case`. As datas sao ISO-8601 UTC. Use `Authorization: Bearer <token>`
para sessao ou token de integracao e `Idempotency-Key` no cadastro de empresa.

| Metodo e rota | Credencial | Uso |
| --- | --- | --- |
| `GET /health` | nenhuma | Retorna `{"situacao":"disponivel"}`. |
| `POST /auth/login` | nenhuma | Recebe `email` e `senha`; retorna `token_acesso`, `token_renovacao`, `tipo_token`, `expira_em`. |
| `POST /auth/refresh` | nenhuma | Recebe `token_renovacao`. |
| `PUT /auth/password` | sessao | Recebe `senha_atual` e `nova_senha`. |
| `POST /auth/logout` | sessao | Revoga a sessao atual. |
| `POST /admin/erps` | superadmin | Recebe `razao_social`, `rotulo_chave`; retorna `id_erp`, `id_chave`, `chave_erp`. |
| `POST /admin/erps/{id_erp}/chaves` | superadmin | Rotaciona a chave, recebendo `rotulo_chave`. |
| `DELETE /admin/erps/{id_erp}/chaves/{id_chave}` | superadmin | Revoga a chave ERP. |
| `POST /v1/empresas` | chave ERP bootstrap | Recebe A1 e inicia o monitoramento. |
| `PUT /v1/empresas/{id_empresa}/modulos/monitoramento` | chave ERP bootstrap | Recebe `situacao`: `ativo`, `suspenso` ou `cancelado`. |
| `GET /v1/monitoramento` | token do tenant | Retorna a situacao persistida do monitoramento. |
| `GET /v1/documentos?nsu=0&limite=100` | token do tenant | Lista documentos do tenant em ordem de NSU. |
| `GET /v1/documentos/{id_documento}/xml` | token do tenant | Entrega XML retido, `202` com `id_comando` ou `409` para ciencia final recusada. |

## Cadastro de empresa

`POST /v1/empresas` recebe:

```json
{
  "uf": "PA",
  "certificado_a1_base64": "...",
  "senha_certificado_base64": "..."
}
```

`uf` e opcional se a ReceitaWS a obtiver pelo CNPJ do certificado. A resposta
contém `id_empresa`, `id_integracao`, `repetido`, `uf`, `razao_social`,
`nome_fantasia`, `cadastro_disponivel`, `dados_cadastrais` quando disponivel e,
somente no primeiro cadastro, `token_integracao`.

## Sincronizacao de documentos

Envie `nsu=0` na carga inicial e, depois, o maior `ultimo_nsu` confirmado. A
resposta tem `itens` e `ultimo_nsu`. Cada item traz `nsu`, `id_documento`,
`chave_acesso`, `tipo_documento`, `modelo`, `serie`, `numero`, `emitido_em`,
`cnpj_emitente`, `nome_emitente`, `tipo_operacao`, `situacao_fiscal`,
`valor_total`, `situacao`, `ciencia_cstat` quando houve tentativa e
`xml_disponivel`.

Valores de `tipo_operacao`: `entrada`, `saida`. Valores de `situacao_fiscal`:
`autorizada`, `cancelada`, `denegada`, `encerrada`. Valores de `situacao`:
`localizado`, `ciencia_registrada`, `manifestado`, `xml_disponivel` ou
`cancelado`.

Erros JSON seguem `{"erro":{"codigo":"...","mensagem":"..."}}`.

Quando o XML ainda nao estiver retido, o ERP chama a rota de XML e recebe
`202` com `situacao: "pendente"` e `id_comando`. O worker registra a ciencia
quando a SEFAZ devolver somente o resumo, aguarda a proxima consulta permitida
e retenta sem chamar a SEFAZ na rota HTTP. Para `ciencia_cstat` `596` ou `655`,
a rota retorna `409` com `situacao: "indisponivel"`, `motivo` e o cStat; nao
cria nova consulta pontual. O monitoramento normal pode entregar o XML depois,
caso a SEFAZ o disponibilize.
