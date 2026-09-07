# Spike Delphi para ERP

Este console Win64 demonstra o contrato que o ERP precisa implementar. O smoke
padrao faz somente leituras: saude, estado do monitoramento e primeira pagina de
documentos. O comando `xml` pode entregar um XML existente ou criar a solicitacao
assincrona prevista pela API quando ele ainda nao estiver retido.

```bat
scripts\build-erp-spike.bat
set FISCONEXA_API_URL=https://api.fisconexa.com.br
set FISCONEXA_ERP_TOKEN=token-do-tenant
bin\examples\win64\FiscoNexa.ErpSpike.exe smoke
bin\examples\win64\FiscoNexa.ErpSpike.exe documentos 0 100
bin\examples\win64\FiscoNexa.ErpSpike.exe xml ID_DOCUMENTO nota.xml
```

O executavel nunca grava o token em arquivo ou na linha de comando. O ERP deve
guardar o `ultimo_nsu` retornado e usa-lo na proxima chamada.
