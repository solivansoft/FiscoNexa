# Worker SEFAZ: cursor, janela e lacuna

Problema: dez mil CNPJs podem ser monitorados por varios workers, mas a
Distribuicao DF-e impoe cadencia por CNPJ e outro consumidor pode avancar o
cursor; evidencia: `Servico.SefazDFe.pas` e `SefazDFe.Policy.pas` do ERP
aplicam espera de 3.630 s para `137`/`656`, lotes imediatos em `138` enquanto
`ultNSU < maxNSU`, e recuperacao pontual de lacuna; invariante: nenhum worker
consulta `distNSU` antes da janela persistida, nem repete cursor ultrapassado;
causa: o cursor e compartilhado por todos os consumidores do mesmo CNPJ;
solucao: `status_monitoramento` guarda cursor e proxima consulta, e uma fila
persistida de lacunas usa `consNSU` pontual com intervalo de 300 s e maximo de
15 por hora por CNPJ; previsao: replicas horizontais nao geram bloqueio nem
perdem documentos quando outro robo avanca o NSU; riscos/nao objetivos:
limites futuros da SEFAZ exigem revisao da policy, e o MVP-005 ainda nao chama
ACBr. A regra oficial do `NFeDistribuicaoDFe` descreve sequencia e bloqueio
por CNPJ informado na requisicao, sem publicar limite global por IP; outros
web services e UFs podem aplicar criterios adicionais, portanto concorrencia
global permanece configuravel; teste/oraculo: testes puros da policy para `137`, `138`, `656`, janela,
lacuna e duas leases concorrentes; gate: worker simulado reclama um unico CNPJ
e persiste a proxima decisao antes de integrar SEFAZ.

Atualizacao do MVP-006: o gateway real usa `TACBrNFe` com o A1 em
`DadosPFX`, decifrado somente em memoria, e `SSLLib = libOpenSSL`. Evidencia:
o ACBr compila a configuracao para Win64 sem `httpWinINet`; invariante:
nenhuma configuracao do gateway pode depender de API exclusiva do Windows;
risco: o ambiente Ubuntu ainda precisa ser validado no WSL com as bibliotecas
OpenSSL e dependencias nativas adequadas; gate: build e smoke reais no WSL
antes de liberar producao Linux.


## Fechamento local do MVP-006

Problema: comandos nao eram consumidos, lacunas descartavam documentos e o NSU
nao notificava atualizacoes; evidencia: revisao dos chamadores e teste PostgreSQL
com 150 documentos, resumo, XML e falha de storage; invariante: avancar lacuna
somente apos persistencia, concluir download somente com XML retido e publicar
mudanca observavel em ordem por tenant; causa: filas nao conectadas e upsert
que preservava o cursor de sincronizacao; solucao: conectar as tres filas,
compartilhar armazenamento do XML e gravacao transacional, consultar XML por
chave, alocar novo NSU apenas para mudanca e serializar essa escrita pela linha
da empresa antes de alocar o cursor; previsao: replay nao duplica, resumo nao
apaga XML e o ERP recebe a atualizacao apos retomar pelo NSU anterior;
riscos/nao objetivos: simulacao nao comprova ciencia nem comportamento real da
SEFAZ; teste/oraculo: `tests/test-release-local.ps1` e
`tests/smoke-erp-end-to-end.ps1`; gate: aprovacao local registrada no STATUS,
com homologacao fiscal real ainda pendente.

As filas pontuais reclamam a mesma linha de estado do CNPJ e reservam a
contagem de consultas na mesma instrucao SQL da lease, antes de acessar a
SEFAZ. Falha externa tambem consome essa reserva. O worker reclama uma tarefa
por vez e verifica a fila principal antes de comandos e lacunas.
