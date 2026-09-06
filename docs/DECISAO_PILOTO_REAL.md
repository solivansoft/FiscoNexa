# Piloto real: gates operacionais

Problema: um teste local aprovado nao demonstra que o FiscoNexa pode operar
um CNPJ real com seguranca fiscal; evidencia: em 2026-09-05, o smoke HTTP
aprovou A1 temporario, AWS KMS real, PostgreSQL e reenvio idempotente, mas o
worker atual ainda retorna apenas cursor e `cStat` do ACBr; invariante: nenhum
CNPJ entra em producao sem que o XML baixado seja persistido de forma
idempotente, acessivel apenas ao tenant correto, e que o cancelamento comercial
pare novos ciclos; causa/hipotese: os elos `docZip -> documento -> S3 -> ERP`
ainda nao estao conectados; referencia: `Integrations.AcbrSefaz.pas`,
`Application.MonitorCycle.pas` e `Servico.SefazDFe.pas` do ERP; solucao:
implementar e testar primeiro fixtures ACBr, persistencia e S3, depois validar
consulta de distribuicao e ciencia como etapas independentes com CNPJ/A1
expressamente autorizados; previsao: o piloto permite identificar a falha por
elo, sem gerar ciencia fiscal por acidente; riscos/nao objetivos: homologacao
nao substitui operacao em producao e nao testa cobranca; teste/oraculo: upload
e download S3 com SHA-256, duplicacao de `docZip` sem duplicar documento,
paginas crescentes pelo NSU proprio, cancelamento sem lease nova, e consulta
SEFAZ autorizada antes de ciencia; gate: somente apos todos os oraculos locais
verdes e autorizacao do responsavel pelo CNPJ executar ciencia automatica.

Atualizacao 2026-09-05: o adaptador ACBr agora converte `schresNFe` e
`schprocNFe` em resposta de aplicacao com NSU SEFAZ, chave, emissao, emitente,
valor e XML; evidencia: `scripts\test-unit.bat` e
`scripts\build-worker.bat win64` aprovados. Isso ainda nao persiste nem expõe
o documento, portanto nao satisfaz o gate de piloto.

Decisao de storage: PostgreSQL e S3 nao participam da mesma transacao;
invariante: um documento so recebe `xml_available` apos `PutObject` bem
sucedido e hash conferido; solucao: a chave do objeto e deterministica por
CNPJ e chave de acesso, portanto uma falha apos o upload e antes do commit do
banco e recuperada por reenvio idempotente do mesmo objeto; risco: ha objeto
orfao temporario, que e preferivel a banco apontando para XML inexistente;
oraculo: repetir upload apos falha simulada preserva uma unica chave, SHA-256
e objeto legivel; gate: a rota de XML so consulta documentos com
`xml_object_key` e `xml_sha256` preenchidos.

Atualizacao 2026-09-05: `tests\smoke-s3.ps1` executou `PUT` real no bucket
`xml.fisconexa.com.br` com o adaptador SigV4 e recebeu HTTP 2xx. O primeiro
teste revelou falha TLS no endpoint virtual-hosted, porque o nome do bucket
contem pontos; a correcao usa endpoint regional path-style, sem desabilitar a
validacao do certificado. O objeto temporario esta sob `nfe/00000000000000/`.

Consulta SEFAZ real: o primeiro oraculo operacional e
`tests\integration\FiscoNexa.SefazRealIntegration.dpr`. Ele recebe PFX, senha
e UF exclusivamente por ambiente, extrai o CNPJ do A1 e chama somente
`distNSU` com cursor zero. A ciencia fica explicitamente desativada no gateway
e a execucao exige `FISCONEXA_SEFAZ_REAL_CONFIRMATION=YES`; portanto esta etapa
nao manifesta, nao baixa XML e nao altera o cadastro fiscal. O teste somente
avanca para ciencia ou worker apos o responsavel autorizar o CNPJ e a consulta
retornar resposta valida da SEFAZ.

Compatibilidade A1: alguns arquivos PKCS#12 antigos usam algoritmos que o
OpenSSL 3 mantem no provider `legacy`. O inspetor tenta carregá-lo sem torná-lo
obrigatório para PFXs modernos. O smoke local aceita
`FISCONEXA_OPENSSL_RUNTIME_DIR`, que aponta para uma distribuicao OpenSSL com
`bin\libcrypto-3-x64.dll` e `lib\ossl-modules\legacy.dll`; a imagem de
producao deve distribuir esse runtime compatível como parte do produto, nunca
depender da instalacao de outra aplicacao na maquina.

Empacotamento ACBr: os schemas NF-e sao dados de execucao obrigatorios, nao
arquivos de desenvolvimento. O worker resolve `Schemas` relativo ao proprio
executavel e `build-worker.bat` os copia da versao ACBr declarada para essa
pasta. Assim, a maquina de producao nao precisa ter ACBr instalado; no Ubuntu,
o binario usa `libcrypto.so.3`, e no Windows usa a DLL OpenSSL distribuida com
o produto. Oraculo: iniciar o worker/teste fora da arvore ACBr e obter a
validacao de schema do ACBr sem depender de caminho absoluto de desenvolvimento.


## Smoke autorizado com cliente (2026-09-05)

Autorizacao operacional nesta sessao: monitorar, registrar ciencia e baixar
XML com o A1 apontado pelo responsavel no ambiente; sem expor material fiscal
em logs. `tests/smoke-real-fiscal.ps1 -AllowAwareness` orquestra API e worker
reais. O banco confirmou onboarding cifrado. A primeira execucao registrou
falha de persistencia: timestamp com minutos invalidos produzido pelo parametro
UniDAC `AsDateTime`. O teste isolado reproduziu a falha com data sintetica
fracionaria; o bind passou a usar ISO 8601 e cast PostgreSQL, com comparacao
exata de horario/fuso/milissegundos aprovada. Nao houve repeticao fiscal durante
o diagnostico; a proxima consulta foi adiada conservadoramente por 3.630 s.
Nao presumir ausencia de ciencia na tentativa: o evento pode ter ocorrido
antes da falha transacional. A homologacao fiscal permanece aberta.

A policy agora adota o `ultNSU` de `656` mesmo quando o cursor local estava
vazio. Falha de storage/persistencia apos resposta fiscal tambem aguarda a
janela completa, sem converter a resposta em retry de sessenta segundos.
Oraculos: 67 unitarios e `tests/test-release-local.ps1`.
