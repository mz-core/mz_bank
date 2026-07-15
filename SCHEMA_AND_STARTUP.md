# Inicialização e migrations do mz_bank

## Ordem requerida

O `fxmanifest.lua` declara `oxmysql`, `ox_lib`, `mz_core` e `mz_inventory` como dependências rígidas do `mz_bank`. `mz_economy` é uma dependência observada/degradável: deve iniciar antes para fornecer o extrato, mas sua indisponibilidade não invalida o commit financeiro oficial do `mz_core`. A ordem efetiva aplicada em `mz_starter/cfg/resources.cfg` é:

```cfg
ensure oxmysql
ensure ox_lib
ensure mz_core
ensure mz_economy
ensure mz_inventory
ensure mz_bank
```

O arquivo efetivo foi alterado em 2026-07-15 após autorização explícita do responsável. Os seis resources aparecem na ordem acima; outros resources opcionais não mudam essa precedência.

## Readiness

Durante o bootstrap, `mz_bank`:

1. lê o estado real das quatro dependências rígidas e do `mz_economy` observado com `GetResourceState`;
2. permanece indisponível e registra `dependency_missing:<resource>=<state>` se alguma dependência rígida não estiver `started`;
3. executa o runner versionado;
4. valida versão, tabelas, colunas, índices e engine;
5. somente então chama `MZBankService.SetReady(true)`.

Se uma dependência rígida parar durante o runtime, novas aberturas são bloqueadas e o console solicita reinício do `mz_bank` depois da recuperação. Se somente `mz_economy` parar, o serviço permanece pronto para operações do core, registra o modo degradado e o extrato retorna `statement_unavailable`; a disponibilidade do extrato volta automaticamente quando o resource observado inicia novamente.

O export server-side `GetReadiness` devolve `ready`, `error`, `degraded`, `warning`, estados das dependências e versão atual/esperada da migration. `degraded = true` é restrito à indisponibilidade do ledger/extrato e não equivale a falha do serviço financeiro. Esse export é diagnóstico interno; não é enviado à NUI.

## Fonte de verdade do schema

- `sql/000_mz_bank_schema_migrations.sql`: registro de versões.
- `sql/001_mz_bank_cards.sql`: única definição de `mz_bank_cards`.
- `sql/002_mz_bank_legacy_reports.sql`: relatórios persistentes do fluxo legado.
- `server/migrations.lua`: ordena, aplica idempotentemente e valida; não contém uma segunda definição de `mz_bank_cards`.
- `server/repository.lua`: somente consultas e comandos de dados; não cria schema.

O runner usa `CREATE TABLE IF NOT EXISTS`, registra cada versão somente depois de validar o objeto criado e aceita reexecução. Ele não contém `DROP`, `TRUNCATE`, `DELETE` nem alteração destrutiva. Uma versão desconhecida mais nova, conflito de nome, arquivo ausente, coluna/índice incompatível ou erro SQL mantém o serviço indisponível e produz erro explícito no console/readiness.

Não execute os SQLs manualmente fora do fluxo sem registrar e conferir a versão. Antes de um restart real, faça backup e valide em staging. Esta implementação não executou migrations contra o banco de runtime.
