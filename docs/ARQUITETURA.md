# Arquitetura inicial

## Principio

Separar o nucleo SaaS da comunicacao fiscal. Sao responsabilidades com ciclos,
riscos e ferramentas diferentes, mesmo permanecendo no mesmo repositorio e
produto.

```text
ERP / Portal / Contador
          |
          v
     FiscoNexa API -------- PostgreSQL
          |                     |
          |                     +-- metadados, agenda e auditoria
          |
          +----------------- Storage S3
          |
          v
  FiscoNexa Fiscal Worker
          |
          v
        SEFAZ
```

## Direcao escolhida

### Stack principal: Delphi + Horse + PostgreSQL

Adotar Delphi para o nucleo SaaS e para o motor fiscal. O WMLC sera usado para
compilar no Windows os binarios destinados ao Ubuntu.

Motivos:

- Uma unica linguagem para API, dominio, jobs e integracao fiscal.
- Reaproveitamento direto do conhecimento e das rotinas ACBr existentes.
- Binarios nativos, sem runtime adicional no servidor.
- Horse suporta aplicacoes console e daemons Linux.
- PostgreSQL permanece como fonte de verdade do SaaS.

Mesmo usando a mesma stack, API e worker fiscal permanecem em processos
separados:

```text
FiscoNexa.API           Delphi Console + Horse       Ubuntu
FiscoNexa.FiscalWorker  Delphi Console + ACBr         Ubuntu ou Windows
```

Essa separacao impede que indisponibilidade, timeout ou falha de certificado no
ACBr derrube a API publica.

### Build e deploy

- Desenvolvimento principal no Delphi em Windows.
- Compilacao cruzada para Linux x64 pelo WMLC.
- API executada como daemon controlado pelo `systemd`.
- Horse exposto apenas na interface interna; Nginx encerra HTTPS.
- Worker Windows continua permitido quando certificado ou dependencia fiscal
  nao funcionar de forma segura no Linux.

## Alternativas

### Go

Pontos fortes:

- Binario unico, baixo consumo e deploy excelente em Ubuntu.
- Concorrencia e workers simples.
- Tipagem estatica e falhas detectadas no build.

Custos:

- Exige montar autenticacao, autorizacao, admin e migrations com mais pecas.
- Um portal administrativo equivalente ao Django Admin demanda trabalho.
- Tende a produzir mais codigo de infraestrutura no inicio.

Go e a segunda opcao recomendada. Deve vencer se o spike mostrar que o dominio
e pequeno e que a equipe prefere operacao simples a recursos prontos de SaaS.

### Laravel/PHP

- Excelente produtividade para SaaS, autenticacao, filas e paineis.
- Deploy amplamente conhecido e ecossistema grande.
- Exigiria adotar PHP, que nao faz parte do repertorio atual da equipe.

E uma alternativa tecnicamente boa, mas abaixo de Django e Go neste contexto.

### C# / ASP.NET Core

- Maduro para web em Linux, tipado e com bom suporte a seguranca e workers.
- Deploy em Ubuntu e Docker e suportado e comum.
- Nao sera escolhido apenas para viabilizar ACBrLib; a maturidade dessa ponte
  precisa ser demonstrada primeiro.
- Permanece como alternativa, nao como recomendacao atual.

### Lazarus + Horse

Permanece como contingencia caso o WMLC ou a cadeia Delphi/Linux nao cumpra os
gates. Nao sera usado inicialmente para evitar diferencas entre Delphi e FPC em
RTTI, generics, JSON, threads e bibliotecas.

## PocketBase

Nao usar um fork do PocketBase adaptado para PostgreSQL no nucleo do produto.

Razoes:

- PocketBase foi projetado sobre SQLite.
- O projeto oficial declara que nao planeja suportar outros bancos.
- Antes da versao 1.0 nao garante compatibilidade total e nao recomenda uso em
  aplicacoes criticas sem aceitar migracoes manuais.
- Trocar a camada de dados criaria um fork permanente justamente nas areas de
  autenticacao, regras de acesso e migrations.

Pode ser usado em prototipo descartavel, nunca como atalho que vire fundacao do
cofre fiscal.

## Dados e concorrencia

- PostgreSQL como fonte de verdade.
- `tenant_id` obrigatorio em toda entidade pertencente ao cliente.
- Chave de acesso do documento unica dentro do contexto correto.
- Fila persistente no PostgreSQL inicialmente.
- Lock logico por CNPJ para impedir dois workers consultando a SEFAZ.
- Operacoes idempotentes para captura, upload, manifestacao e download.
- XML fora do banco, em storage compativel com S3, com hash e versionamento.
- Outbox transacional para eventos destinados ao ERP e notificacoes.

Redis, RabbitMQ ou Kafka somente entram quando uma metrica demonstrar a
necessidade.

## Autenticacao e autorizacao

Separar identidades humanas de integracoes:

- Usuarios web: sessao segura, recuperacao de senha e MFA administrativo.
- ERP/agentes: credenciais proprias por instalacao, rotacionaveis e com escopo.
- Contador: acesso explicito apenas aos CNPJs compartilhados.
- Suporte: acesso auditado, temporario e com justificativa.
- Nunca confiar em `tenant_id` recebido sem validar o vinculo da identidade.

## Seguranca de certificados e documentos

- Certificado e senha criptografados com chave mestra fora do banco.
- Preferir envelope encryption com chave individual por tenant/CNPJ.
- TLS em todo transporte.
- Segredos fora do repositorio e das imagens de container.
- Auditoria de leitura, manifestacao, download e acesso administrativo.
- Backup testado do PostgreSQL e do storage em destino independente da VPS.
- Politica de retencao e exclusao definida contratualmente.

## Deploy inicial

- VPS Ubuntu.
- Containers separados para API e worker web/assincrono do nucleo.
- PostgreSQL com backup externo; banco gerenciado deve ser avaliado antes da
  producao comercial.
- Worker Delphi/ACBr em host Windows separado enquanto durar a validacao.
- Proxy reverso com HTTPS, health checks e logs estruturados.

## Registro breve da decisao arquitetural

- Problema: construir um SaaS fiscal seguro sem reimplementar a comunicacao
  SEFAZ ja dominada em ACBr nem manter stacks desnecessarias.
- Evidencia: a integracao fiscal atual funciona em Delphi e o WMLC gera binarios
  Delphi para Ubuntu a partir do Windows; PocketBase e baseado em SQLite.
- Invariante: somente um executor consulta cada CNPJ e toda operacao e
  idempotente e auditavel.
- Hipotese: uma stack Delphi unificada reduz integracoes e aproveita melhor o
  dominio tecnico existente sem sacrificar o deploy Linux.
- Solucao: Delphi/Horse/PostgreSQL/S3, com API e worker ACBr isolados e build
  Linux pelo WMLC.
- Previsao: compartilhamento seguro do dominio e menor tempo ate a primeira
  integracao fiscal completa.
- Riscos: infraestrutura web que frameworks maiores entregariam pronta,
  compatibilidade Linux de dependencias, TLS, certificados e pipeline WMLC.
- Teste/oraculo: executar uma fatia vertical no Ubuntu com API concorrente,
  PostgreSQL, encerramento por sinal e captura fiscal real em homologacao.
- Gate: liberar producao apenas apos build reproduzivel, isolamento multi-tenant,
  idempotencia, recuperacao de falhas e operacao fiscal Linux serem demonstrados.

## Gate tecnico do WMLC

1. Gerar build Linux x64 reproduzivel no Windows.
2. Atender requisicoes Horse concorrentes.
3. Usar pool PostgreSQL sem compartilhar conexoes entre threads.
4. Encerrar corretamente por `SIGTERM` sob `systemd`.
5. Operar atras do Nginx com HTTPS.
6. Carregar schemas e assinar XML com certificado A1.
7. Consultar a Distribuicao DF-e em homologacao.
8. Preservar UTF-8, datas e timezone.
9. Executar testes automatizados no artefato Linux.
10. Mapear e empacotar todas as dependencias `.so`.
