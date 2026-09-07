# Status

Atualizado em 2026-09-07 20:10 (America/Sao_Paulo).

## Producao

A API e o worker Linux estao instalados no `fisconexa.vps` como release
`2026.09.07-rc9`. `https://api.fisconexa.com.br/health` responde
`{"situacao":"disponivel"}`. API, timer do worker, Caddy, Alloy, WireGuard e
fail2ban estao habilitados e ativos no systemd. Uma reinicializacao controlada
comprovou que os servicos retornam sem intervencao.

O PostgreSQL 16 roda nativamente no `dados.vps`, escutando apenas em
`127.0.0.1` e `10.77.0.1`. A base piloto preservou os 8 tenants, cursores,
certificados cifrados e sequencia de sincronizacao. A rodada fiscal da `rc8`
elevou a base de 124 para 157 documentos e de 119 para 122 referencias de XML;
nenhum registro ou XML foi removido. Somente a VPS da aplicacao acessa o papel
e a base `fisconexa` pela VPN.

O timer de backup logico esta ativo na VPS de dados. Ele gera diariamente dumps
custom de `fisconexa` e `academy`, valida o catalogo com `pg_restore` e conserva
sete dias com permissao `0600`. Os dumps iniciais dos dois bancos passaram no
oraculo. Existe tambem o dump externo da migracao em `D:\Backups`. Uma
reinicializacao controlada comprovou o retorno do PostgreSQL, WireGuard e timer.

## Worker fiscal

Os 8 tenants e seus 8 modulos de monitoramento estao ativos. O timer executa
uma unidade oneshot a cada dez segundos, mas somente chama a SEFAZ quando o
PostgreSQL devolve trabalho elegivel. Lote unitario, lease persistida,
`next_check_at`, limite de consultas pontuais e bloqueio 656 continuam sendo os
gates de execucao. Nenhuma lease permaneceu presa depois da rodada.

A falha `error:0308010C ... unsupported` foi reproduzida fora da SEFAZ. O pacote
Linux continha arquivos distintos para `libcrypto.so` e seu SONAME, e o ACBr
abria uma segunda instancia do OpenSSL com outro contexto de providers. A
`rc8` empacota uma unica biblioteca e cria hardlinks para os nomes sem versao;
o carregamento ACBr do A1 passou no WSL, na VPS com o pacote instalado e no
worker real.

Em 2026-09-07 22:20:44 UTC o worker consultou a SEFAZ na janela persistida,
recebeu `cStat 137`, zerou a falha, liberou a lease e agendou a proxima consulta
para 23:21:14 UTC. Esse resultado liberou de forma transacional os demais
tenants. A fila processou os vencidos, inclusive um lote `cStat 138`, avancou o
NSU e aplicou novas janelas de aproximadamente uma hora. O tenant que ainda
guardava um erro da release anterior foi processado pelo proprio worker as
22:46:59 UTC, recebeu `cStat 138` e nova janela para 23:47:29 UTC. A ciencia
automatica global permanece desligada.

## Integracao ERP

O exemplo [FiscoNexa.ErpSpike.dpr](../examples/erp-delphi/FiscoNexa.ErpSpike.dpr)
compila para `bin/examples/win64/FiscoNexa.ErpSpike.exe`. Depois da ativacao dos
tenants, o executavel voltou a comprovar HTTP 200 para saude, monitoramento e
documentos na API de producao. Em prova anterior, o comando `xml` baixou pela
API um XML real valido de 9.020 bytes. O smoke padrao e somente leitura; o
comando `xml` cria uma solicitacao assincrona quando o documento ainda nao esta
retido.

A credencial exclusiva do spike fica fora do repositorio, em
`D:\Hostinger\credenciais\fisconexa-erp-spike.env`. O banco guarda somente o
SHA-256 e identifica a integracao como `ERP spike`.

## Logs

API e worker escrevem JSON no terminal/journald e em arquivos rotativos de
10 MiB. Alloy acompanha os arquivos e envia lotes ao Loki central no
`loki.vps`; uma consulta posterior a rodada encontrou streams recentes dos
servicos `api` e `worker`. Grafana consulta o tenant `fisconexa`. Loki exige
`X-Scope-OrgID`, e cada projeto recebe rota, usuario, senha e datasource
separados. A retencao atual e de sete dias. Docker, WireGuard, Loki, Grafana e o
gateway retornaram automaticamente em reinicializacao controlada.

## Pendencias comerciais

- Criar alertas de indisponibilidade e erro recorrente no Grafana.
- Configurar uma copia de backup fora da VPS de dados ou snapshot automatico do
  provedor para perda total do host.
- Implementar manifestacao conclusiva solicitada pelo ERP e alertas de XML aos
  60, 75 e 85 dias, conforme `docs/DECISOES_PENDENTES.md`.

## Evidencias atuais

- `scripts\test-unit.bat`: 76/76 metodos aprovados.
- `scripts\build-api.bat linux64` e `scripts\build-worker.bat linux64`:
  compilacao Linux64 aprovada.
- Pacote implantado: `fisconexa-2026.09.07-rc9.tar.gz`, SHA-256
  `d92a32b0998f5b7f9b79f5d386b0d88e4ca7df1baaee49540b0e542972780386`.
- Teste de certificado ACBr sem chamada SEFAZ aprovado no WSL e na VPS com as
  bibliotecas autocontidas da `rc8`.
- `scripts\build-erp-spike.bat`: `.dpr` e `.exe` Win64 recompilados; smoke real
  aprovado contra `https://api.fisconexa.com.br` pela rota `/health` na `rc9`.
