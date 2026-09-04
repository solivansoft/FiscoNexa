# Decisao - primeira fatia vertical

Problema: disponibilizar monitoramento fiscal para empresa, contador e ERP sem
atribuir a posse do CNPJ a um intermediario; evidencia: o mesmo CNPJ pode ser
operado pela empresa e compartilhado com contador e ERP; invariante: toda
leitura de documento exige concessao explicita por CNPJ, token de ERP nunca
amplia escopo e superadmin nao representa acesso normal; causa/hipotese: modelar
o CNPJ como recurso da empresa e os participantes como acessos evita transferencia
indevida de dados; referencia: arquitetura inicial e Servico.SefazDFe do ERP;
solucao: users globais, organizations para contador/ERP/revenda, grants explicitos
e token hash por integracao e CNPJ; previsao: um contador atende muitos CNPJs e
um ERP so enxerga os CNPJs autorizados; riscos/nao objetivos: politica comercial,
KMS e login nao estao implementados nesta fatia; teste/oraculo: migration idempotente,
smoke HTTP e testes negativos de autorizacao antes das rotas fiscais; gate: nao
aceitar upload de certificado ou consulta fiscal antes de validar criptografia,
autenticacao e isolamento por CNPJ.

## Ordem de implementacao

1. Ambiente, dependencias pinadas, PostgreSQL, migrations Delphi e health endpoint.
2. Autenticacao e cadastro de usuario.
3. Company onboarding, acesso compartilhado e certificado criptografado.
4. Worker fiscal isolado, cursor/NSU e comandos idempotentes.
5. Documentos no S3, API de leitura por token de ERP e integracao Delphos.
