# Status

Atualizado em 2026-09-07 17:35 (America/Sao_Paulo).

## Producao

A API e o worker Linux estao instalados no `fisconexa.vps` como release
`2026.09.07-rc6`. `https://api.fisconexa.com.br/saude` responde
`{"situacao":"disponivel"}`. API, timer do worker, Caddy, Alloy, WireGuard e
fail2ban estao habilitados e ativos no systemd.

O PostgreSQL 16 roda nativamente no `dados.vps`, escutando apenas em
`127.0.0.1` e `10.77.0.1`. A base piloto foi restaurada integralmente como
`fisconexa`: 8 empresas, 124 documentos, 119 referencias de XML e 127 comandos.
Cursores, certificados cifrados e sequencia de sincronizacao foram preservados.
Somente a VPS da aplicacao acessa o papel e a base `fisconexa` pela VPN.

O timer de backup logico esta ativo na VPS de dados. Ele gera diariamente dumps
custom de `fisconexa` e `academy`, valida o catalogo com `pg_restore` e conserva
sete dias com permissao `0600`. Os dumps iniciais dos dois bancos passaram no
oraculo. Existe tambem o dump externo da migracao em `D:\Backups`.

## Worker fiscal

Ha um tenant ativo e sete inativos. O timer executa uma unidade oneshot a cada
dez segundos, mas somente chama a SEFAZ quando o PostgreSQL devolve trabalho
elegivel. Lote unitario, lease persistida, `next_check_at`, limite de consultas
pontuais e bloqueio 656 continuam sendo os gates de execucao.

Em producao foi encontrado um defeito de recuperacao: uma mensagem ACBr com
byte NUL impedia o PostgreSQL de registrar a falha e liberar a lease. A `rc5`
passou a persistir um codigo de erro ASCII, processou a tarefa, liberou a lease
e agendou 3.630 segundos de espera. A `rc6` conserva uma descricao ASCII para
o proximo diagnostico. O estado atual e `EInvalidOpException`, sem lease ativa,
com proxima tentativa em `2026-09-07 21:20:03 UTC`. Nao antecipar essa janela.
A ciencia automatica global permanece desligada.

## Integracao ERP

O exemplo [FiscoNexa.ErpSpike.dpr](../examples/erp-delphi/FiscoNexa.ErpSpike.dpr)
compila para `bin/examples/win64/FiscoNexa.ErpSpike.exe`. Em producao ele
comprovou HTTP 200 para saude, monitoramento e documentos e baixou pela API um
XML real de 9.020 bytes. O smoke padrao e somente leitura; o comando `xml` faz a
solicitacao assincrona apenas quando o documento ainda nao esta retido.

A credencial exclusiva do spike fica fora do repositorio, em
`D:\Hostinger\credenciais\fisconexa-erp-spike.env`. O banco guarda somente o
SHA-256 e identifica a integracao como `ERP spike`.

## Logs

API e worker escrevem JSON no terminal/journald e em arquivos rotativos de
10 MiB. Alloy acompanha os arquivos e envia lotes ao Loki central no
`loki.vps`; Grafana consulta o tenant `fisconexa`. Loki exige
`X-Scope-OrgID`, e cada projeto recebe rota, usuario, senha e datasource
separados. A retencao atual e de sete dias.

## Pendente para a liberacao comercial

- Observar a tentativa fiscal das 21:20:03 UTC e corrigir a causa descrita pela
  `rc6` caso a consulta ainda falhe.
- Criar alertas de indisponibilidade e erro recorrente no Grafana.
- Configurar uma copia de backup fora da VPS de dados ou snapshot automatico do
  provedor para perda total do host.
- Implementar manifestacao conclusiva solicitada pelo ERP e alertas de XML aos
  60, 75 e 85 dias, conforme `docs/DECISOES_PENDENTES.md`.

## Evidencias atuais

- `scripts\test-unit.bat`: 76/76 metodos aprovados.
- `scripts\build-api.bat linux64` e `scripts\build-worker.bat linux64`:
  compilacao Linux64 aprovada.
- Pacote implantado: `dist/fisconexa-2026.09.07-rc6.tar.gz`, SHA-256
  `210f5e4fc1ced8a9b3257e5007757b9162550a803aedaddc7a702f4ba6771173`.
- `scripts\build-erp-spike.bat`: executavel Win64 compilado e smoke real
  aprovado contra `https://api.fisconexa.com.br`.
