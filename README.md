# FiscoNexa

Plataforma fiscal conectada para capturar documentos, integrar empresas e
contadores e transformar XMLs em operacoes prontas no ERP.

Direcao tecnica: Delphi + Horse + PostgreSQL, com compilacao cruzada para
Ubuntu pelo WMLC e separacao entre API e worker fiscal.

Documentacao inicial:

- [Visao do produto](docs/PRODUTO.md)
- [Pesquisa de mercado e oportunidades](docs/PESQUISA_MERCADO.md)
- [Arquitetura](docs/ARQUITETURA.md)
- [Arquitetura da API](docs/ARQUITETURA_API.md)
- [Contrato HTTP de integracao](docs/CONTRATO_API.md)
- [Status](docs/STATUS.md)
- [Decisoes pendentes](docs/DECISOES_PENDENTES.md)
- [Decisao da primeira fatia vertical](docs/DECISAO_VERTICAL_SLICE.md)
- [Ledger de rotas, eventos e camadas](docs/LEDGER.md)
- [Entrega ERP primeiro](docs/ENTREGA_ERP_PRIMEIRO.md)
- [Regras centrais do projeto](REGRAS.MD)

## Desenvolvimento local

1. Execute `scripts\dependencies.bat win64` para preparar Horse e cliente PostgreSQL.
2. Execute `scripts\dev-up.bat` para subir o PostgreSQL local.
3. Execute `scripts\run-api-dev.bat`. A propria API aplica as migrations escritas
   em Delphi, quando pendentes, e so entao abre HTTP.
4. Para compilar sem iniciar a API, execute `scripts\build-api.bat win64` e depois
   `powershell -ExecutionPolicy Bypass -File tests\smoke-api.ps1`.

Os builds de release sao `scripts\build-api.bat win64|linux64` e
`scripts\build-worker.bat win64|linux64`.

O exemplo usado para integrar o ERP real esta em
`examples\erp-delphi\FiscoNexa.ErpSpike.dpr`. Compile com
`scripts\build-erp-spike.bat`; o README da pasta documenta smoke, paginacao por
NSU e download de XML.

O smoke end-to-end do contrato ERP e executado por
`tests\smoke-erp-end-to-end.ps1`. O oraculo HTTP fica em Delphi, no
`tests\integration\FiscoNexa.ErpEndToEndIntegration.dpr`; o PowerShell apenas
prepara um A1 temporario e o processo local da API.

Para a primeira consulta SEFAZ real, use `tests\smoke-sefaz-real.ps1` somente
com um A1 autorizado e as variaveis `FISCONEXA_TEST_PFX_PATH`,
`FISCONEXA_TEST_PFX_PASSWORD`, `FISCONEXA_TEST_SEFAZ_UF` e
`FISCONEXA_SEFAZ_REAL_CONFIRMATION=YES`. Esse teste apenas consulta `distNSU`;
nao registra ciencia nem persiste XML.

O smoke seguro de monitoramento e `tests\smoke-real-monitoring.ps1`: ele autentica o
superadmin pela API, cria ERP e chave pela rota administrativa, faz o
onboarding do A1 pela API, executa o worker ACBr uma vez e confere o estado
pela API do tenant. Exige `FISCONEXA_ADMIN_EMAIL` e
`FISCONEXA_ADMIN_PASSWORD`; executa sem ciencia automatica e suspende o modulo
ao final.

As fontes de terceiros ficam fora do Git. A versao exata esta em
`third_party.lock.cmd`; o script recusa uma copia local diferente.

O build do worker leva os schemas NF-e do ACBr para `Schemas` ao lado do
executavel. Em outro computador, basta definir `FISCONEXA_ACBR_ROOT` durante o
build; em execucao o worker nao depende da instalacao do ACBr. No Windows, a
distribuicao tambem deve levar `libcrypto-3-x64.dll` e, quando houver A1 legado,
o modulo OpenSSL `legacy`; para inclui-lo no build Windows, defina
`FISCONEXA_OPENSSL_RUNTIME_DIR` para esse runtime. No Ubuntu usa
`libcrypto.so.3` da imagem.

## Validacao desta versao

Execute `scripts/test-unit.bat`, `scripts/build-worker.bat win64` e
`powershell -ExecutionPolicy Bypass -File tests/test-release-local.ps1`.
O ultimo comando compila a API e testa schema, worker simulado, NSU, FireDAC e
HTTP em um banco temporario, removido ao final. Nao consulta a SEFAZ.

`tests/smoke-erp-end-to-end.ps1` usa A1 sintetico, banco isolado e KMS/S3 reais.
O estado de liberacao e os gates fiscais pendentes estao em [STATUS](docs/STATUS.md).
