# Schema declarativo por tabela

Problema: migrations sequenciais concentram todo o historico em um arquivo e
obrigam editar varios pontos para alterar uma tabela; evidencia: o schema
inicial ja acumulava criacao e renomeacao de tabelas sem necessidade para um
banco ainda nao publicado; invariante: cada tabela tem uma unica declaracao
legivel e a API e o unico processo que aplica o schema; causa: evolucao por
arquivos numerados dispersa a definicao atual; solucao: cada unit `Tables.*`
cria um `TTableSchema` com `AddField`, chaves estrangeiras, checks e indices;
`Schema.Postgres` compara o catalogo e cria somente o que falta;
`RenameField`, `RemoveField`, `InsertData` e `DeleteData` sao comandos
explicitos e as acoes de dados ficam registradas em `schema_actions`;
previsao: adicionar campo altera somente a unit da tabela e a segunda subida
da API nao muda o banco; riscos/nao objetivos: nao ha inferencia automatica de
renomeacao, remocao ou alteracao potencialmente destrutiva; teste/oraculo:
unitarios das declaracoes e `tests\smoke-schema.ps1` em banco Docker vazio,
duas subidas da API e conferencia de tabelas, constraints e indices; gate:
`scripts\test-unit.bat`, `scripts\build-api.bat win64` e
`tests\smoke-schema.ps1`.
