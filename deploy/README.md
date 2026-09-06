# Operacao Ubuntu

Destino autorizado: VPS Ubuntu. Estes arquivos sao a configuracao de operacao;
nao constituem homologacao dos binarios Linux. `LINUX-001` permanece bloqueado
no WMLC/Horse. Nao instalar executaveis Windows como se fossem a entrega Linux.

A API permanece supervisionada pelo systemd. O timer inicia uma tarefa do
worker dez segundos depois do termino da anterior; nunca sobrepoe a mesma
unit. Isso consulta a elegibilidade no PostgreSQL, nao significa consulta a
SEFAZ a cada dez segundos. O banco determina a janela por CNPJ, os limites
pontuais e a retomada. Reiniciar API, worker ou VPS nao apaga esse estado.

O worker executa uma tarefa por ativacao. A lease e maior que o tempo maximo
permitido ao processo; uma interrupcao conserva a protecao persistida ate sua
expiracao. `656` nao exige reiniciar a API nem liberar manualmente o CNPJ.

Depois de compilar e homologar Linux:

1. Instalar os binarios e `Schemas` em `/opt/fisconexa`, com as dependencias
   nativas ACBr/OpenSSL/UniDAC validadas para Linux.
2. Criar usuario de servico `fisconexa` e configurar
   `/etc/fisconexa/fisconexa.env` legivel apenas por root. Usar as variaveis
   `FISCONEXA_DB_*`, AWS/KMS/S3 e `FISCONEXA_SEFAZ_MODE=acbr`.
   `FISCONEXA_AUTO_AWARENESS=true` exige autorizacao operacional do cliente.
   O arquivo nao contem PFX em texto; o worker recupera o A1 cifrado do banco.
3. Instalar as tres units em `/etc/systemd/system`, executar `systemctl
   daemon-reload` e habilitar `fisconexa-api.service` e
   `fisconexa-worker.timer` com `systemctl enable --now`.
4. Validar API, consulta fiscal autorizada, reinicio durante janela de espera
   e recuperacao apos reboot sem chamada antecipada.

`journalctl -u fisconexa-api -u fisconexa-worker` mostra a saida local.
Logs estruturados, correlacao e coleta centralizada de cluster estao em
`LOG-001`; o journald local nao conclui esse requisito.

Referencias de agendamento e supervisao: [systemd.timer](https://github.com/systemd/systemd/blob/main/man/systemd.timer.xml)
e [systemd.service](https://github.com/systemd/systemd/blob/main/man/systemd.service.xml).
