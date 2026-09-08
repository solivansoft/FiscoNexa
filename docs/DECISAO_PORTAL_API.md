# Portal de integracao e protecao das rotas

Data: 2026-09-08. Escopo autorizado: portal OpenAPI/Scalar e verificacao
automatica da autenticacao das rotas.

Revisao solicitada pelo usuario: a documentacao publica nao deve expor rotas
administrativas nem estrategia comercial. O contrato completo passou a ficar
fora da pasta estatica e a ser entregue por rota autenticada com superadmin;
nao basta esconder itens na interface ou enviar parametro de URL. A projecao
publica usa lista explicita e remove schemas/credenciais internos sem uso.
Oraculo: publico sem administracao/webhook, token tenant e usuario comum
recusados, superadmin valido recebe JSON UTF-8, token em URL nao autentica.

- Problema/evidencia: documentacao espalhada em Markdown; testes de autenticacao
  das classes e smokes pontuais nao cobrem todo o inventario HTTP.
- Invariante: cada rota implementada possui contrato e politica de credencial;
  endpoint de negocio nunca entrega dados ou executa acao sem autenticacao.
- Hipotese: comparar inventario Horse com OpenAPI e uma matriz independente de
  acesso, mais chamadas HTTP negativas a cada rota, detecta exposicoes novas.
- Solucao: portal Scalar com assets locais e versao fixa, OpenAPI versionado,
  excecoes publicas explicitas e teste HTTP sem token/com token invalido.
  Credenciais de sessao, bootstrap ERP, tenant, licencas e webhook sao distintas.
- Previsao: uma rota nova sem politica/contrato falha no gate; remocao de uma
  verificacao de autenticacao faz o teste HTTP falhar.
- Riscos: teste negativo com corpo invalido pode mascarar falta de autenticacao;
  usar corpos validos no formato e IDs de fixture. Testar tambem revogacao,
  expiracao, usuario desabilitado, escopo e isolamento em base local dedicada.
- Gate: contrato OpenAPI valido, inventarios identicos, testes negativos em
  todas as rotas protegidas, testes de credenciais persistidas e isolamento;
  verificar portal publicado sem enviar segredos a proxies externos.
- Limite: testes cobrem os cenarios definidos, nao constituem auditoria completa
  de seguranca. CI de contrato nao substitui o gate HTTP de release.

Referencia de integracao: https://scalar.com/products/api-references/integrations/html-js

Resultado: 20 operacoes documentadas; 17 exigem credencial de cabecalho. As
53 negativas HTTP passaram em Windows local, Linux producao e Linux sandbox.
132 verificacoes adicionais passaram com PostgreSQL dedicado, incluindo
isolamento de documentos e cobrancas e validacao de respostas contra OpenAPI.

Correcao reproduzida: FindSessionUser retornava Disabled, mas RequireSuperadmin,
ChangePassword e Logout ignoravam o campo. Novo teste falhou antes da correcao
(85/86) e passou depois (86/86). Agora essas operacoes recusam usuario desabilitado.
Builds Windows e Linux aprovados; release 2026.09.08-documentacao-rc2 instalada
nos dois ambientes. O gate HTTP do instalador passou antes de retomar timers.

Portal validado em Edge headless (navegador integrado indisponivel), desktop e
viewport mobile 390px sem overflow. Navegacao e requisicao interativa ao health
retornaram 200; sem erros JavaScript e carregamento restrito a propria origem.
