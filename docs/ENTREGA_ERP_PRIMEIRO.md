# Entrega ERP primeiro

Objetivo: o ERP deixa de monitorar SEFAZ, manifestar e baixar XML. Ele recebe
um token de um tenant/CNPJ e consome somente documentos prontos.

```text
FiscalWorker -> SEFAZ -> S3 + PostgreSQL -> GET /v1/documentos -> ERP
```

Ordem desta entrega:

1. Token opaco por tenant/CNPJ, armazenado somente como hash.
2. Cursor NSU, comandos e lock por CNPJ no PostgreSQL.
3. Worker Windows com ACBr, inicialmente, para monitorar, dar ciencia quando
   habilitada ou solicitada e baixar XML apos retorno aceito.
4. S3 compativel para guardar XML e hash no PostgreSQL. XML nao sera guardado
   como `bytea`: retencao de cinco anos exige backups e restauracoes independentes
   do banco transacional.
5. ERP consome `GET /v1/documentos` e `GET /v1/documentos/{id_documento}/xml`.

O monitor existente no ERP e referencia de regra: ele ja cobre NSU, bloqueio
656, ciencia e consulta por chave. Ele nao sera copiado, porque depende do banco
do ERP, arquivo INI e certificado instalado no Windows.

Fora desta entrega: login do frontend, recuperacao de senha e envio de NF-e/NFC-e
emitidas pelo ERP. O envio de documentos emitidos entra na proxima fatia, depois
que o cofre e a leitura de XML recebido estiverem operacionais.
