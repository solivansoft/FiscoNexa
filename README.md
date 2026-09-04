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
- [Status](docs/STATUS.md)
- [Decisoes pendentes](docs/DECISOES_PENDENTES.md)
- [Decisao da primeira fatia vertical](docs/DECISAO_VERTICAL_SLICE.md)
- [Ledger de rotas, eventos e camadas](docs/LEDGER.md)

## Desenvolvimento local

1. Execute `scripts\dependencies.bat win64` para preparar Horse e cliente PostgreSQL.
2. Execute `scripts\dev-up.bat` para subir o PostgreSQL local.
3. Execute `scripts\run-api-dev.bat`. A propria API aplica as migrations escritas
   em Delphi, quando pendentes, e so entao abre HTTP.
4. Para compilar sem iniciar a API, execute `scripts\build-api.bat win64` e depois
   `powershell -ExecutionPolicy Bypass -File tests\smoke-api.ps1`.

O build unico gera release: `scripts\build-api.bat win64` (Delphi) ou
`scripts\build-api.bat linux64` (WMLC, assim que o compilador suportar Horse).

As fontes de terceiros ficam fora do Git. A versao exata esta em
`third_party.lock.cmd`; o script recusa uma copia local diferente.
