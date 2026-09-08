# Nomenclatura da primeira entrega

## Rotas

Rotas tecnicas usam ingles convencional: `/health`, `/admin`, `/auth/login`,
`/auth/logout`, `/auth/refresh` e `/auth/password`. Recursos do negocio continuam
em portugues. O cadastro previsto usa `/auth/register`; recuperacao de senha
prevista usa `/auth/forgot-password` e `/auth/reset-password`.

| Recurso | Rota adotada |
| --- | --- |
| administracao de ERP | `/admin/erps` |
| chaves de ERP | `/admin/erps/{id_erp}/chaves` |
| empresas | `/v1/empresas` |
| modulo de monitoramento | `/v1/empresas/{id_empresa}/modulos/monitoramento` |
| monitoramento | `/v1/monitoramento` |
| documentos | `/v1/documentos` |

Os campos JSON tambem usam portugues do Brasil em `snake_case`; `cnpj`, `nsu`,
`cstat` e `xml` permanecem como siglas fiscais.

## Tabelas

| Nome atual | Nome adotado |
| --- | --- |
| `app_users` | `users` |
| `organization_members` | `organization_users` |
| `company_user_access` | `company_users` |
| `company_organization_access` | `company_organizations` |
| `company_certificates` | `certificates` |
| `fiscal_monitor_settings` | `monitor_settings` |
| `fiscal_documents` | `documents` |
| `erp_integrations` | `integrations` |
| `erp_bootstrap_credentials` | `erp_keys` |
| `module_entitlements` | `company_modules` |
| `fiscal_monitor_state` | `monitor_status` |
| `fiscal_commands` | `commands` |

`organizations`, `companies` e `audit_events` permanecem. A migration de
nomenclatura ocorrera antes das novas tabelas e rotas desta entrega.
