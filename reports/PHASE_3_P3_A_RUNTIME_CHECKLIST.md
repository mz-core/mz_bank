# Fase 3 — Checklist runtime do P3-A

Data de criação: 2026-07-17  
Ambiente esperado: MySQL/MariaDB + FiveM staging restaurável  
Estado: **CONCLUÍDO — APROVADO COM UMA LIMITAÇÃO DE FAULT INJECTION**

```text
Fase 3: [~] Em implementação
P3-A: [R] Aprovado em runtime
P3-A runtime: 7 APROVADOS, 0 FALHAS, 0 BLOQUEADOS, 1 NÃO APLICÁVEL
```

## 1. Regras

- não ativar escrita, worker ou consumer;
- não inserir linhas manualmente nas tabelas novas;
- não executar P3-B;
- preservar integralmente saldo, idempotência e ledger atuais;
- registrar somente evidência observada no staging;
- teste não executado ou bloqueado não é aprovado.

Estados: `NÃO EXECUTADO`, `APROVADO`, `FALHOU`, `BLOQUEADO`, `NÃO APLICÁVEL`.

## 2. Ambiente

| Campo | Resultado real |
|---|---|
| FXServer/FiveM | staging; versão não fornecida |
| MySQL/MariaDB | staging; versão não fornecida |
| oxmysql | PENDENTE |
| mz_core | PENDENTE |
| mz_economy | PENDENTE |
| mz_bank | PENDENTE |
| backup/snapshot | não informado |
| executado por | usuário, manualmente |
| data | 2026-07-17 |

## 3. Execução rápida

No console do servidor:

```text
restart mz_core
restart mz_economy
restart mz_bank
```

Logs obrigatórios:

```text
[mz_core][outbox] schema ready version=1 enabled=false writes=false
[mz_economy][outbox] receipt schema ready version=1 enabled=false consumer=false
[mz_economy] passive ledger ready
```

Depois execute no banco:

```sql
SHOW CREATE TABLE mz_financial_outbox;
SHOW INDEX FROM mz_financial_outbox;
SELECT COUNT(*) AS outbox_rows FROM mz_financial_outbox;

SHOW CREATE TABLE mz_economy_outbox_receipts;
SHOW INDEX FROM mz_economy_outbox_receipts;
SELECT COUNT(*) AS receipt_rows FROM mz_economy_outbox_receipts;

SELECT column_name
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name IN ('mz_financial_outbox', 'mz_economy_outbox_receipts')
  AND LOWER(column_name) IN ('balance', 'wallet', 'bank', 'money');
```

Resultados obrigatórios: ambas as contagens em zero e nenhuma coluna financeira proibida.

## 4. Casos

### P3A-01 — criação e readiness do core

- **Pré-condição:** arquivos P3-A atuais; `mz_core` iniciável.
- **Passos:** reiniciar `mz_core`; observar todo o prepare.
- **Esperado:** tabela criada/validada; core conclui prepare; log v1 com `enabled=false` e
  `writes=false`; nenhum erro de schema.
- **Resultado real:** resultado esperado confirmado pelo usuário após execução manual.
- **Evidência:** console + `SHOW CREATE TABLE`.
- **Status:** `APROVADO`

### P3A-02 — criação e readiness do economy

- **Pré-condição:** `mz_core` ready.
- **Passos:** reiniciar `mz_economy`; observar prepare.
- **Esperado:** recibo criado/validado; passive ledger ready; `enabled=false` e `consumer=false`.
- **Resultado real:** resultado esperado confirmado pelo usuário após execução manual.
- **Evidência:** console + `SHOW CREATE TABLE`.
- **Status:** `APROVADO`

### P3A-03 — schema e índices

- **Passos:** executar os `SHOW CREATE TABLE` e `SHOW INDEX` da seção 3.
- **Esperado:** campos/índices iguais ao relatório de implementação; InnoDB; collation
  `utf8mb4_*`; correlationId único; escopo idempotente único; outbox ID e correlationId únicos no
  recibo.
- **Resultado real:** schema e índices confirmados como corretos pelo usuário; saída integral não anexada.
- **Evidência:** saídas SQL completas.
- **Status:** `APROVADO`

### P3A-04 — segunda inicialização idempotente

- **Passos:** reiniciar `mz_core` e `mz_economy` novamente; repetir contagens e schema.
- **Esperado:** nenhum erro/duplicação; schemas iguais; zero linhas; ambos ready.
- **Resultado real:** segunda inicialização e contagens esperadas confirmadas pelo usuário.
- **Evidência:** console e contagens antes/depois.
- **Status:** `APROVADO`

### P3A-05 — feature realmente inativa

- **Passos:** confirmar logs `writes=false`/`consumer=false`; abrir ATM/agência; fazer um depósito,
  um saque e uma transferência atual; repetir contagens das tabelas novas.
- **Esperado:** operações usam o contrato anterior e passam; as duas tabelas continuam com zero
  linhas.
- **Resultado real:** depósito, saque e transferência passaram; tabelas permaneceram vazias conforme confirmação do usuário.
- **Evidência:** console, correlationIds atuais e SQL.
- **Status:** `APROVADO`

### P3A-06 — ausência de saldo e regressão

- **Pré-condição:** snapshots de `mz_player_accounts` dos personagens do teste.
- **Passos:** executar a query de colunas proibidas; comparar saldo/cache/persistência após as
  operações do P3A-05; conferir extrato atual.
- **Esperado:** zero colunas proibidas; deltas exatos das operações; cache e persistência iguais;
  ledger atual sem duplicação; nenhum saldo criado nas tabelas P3-A.
- **Resultado real:** saldo, persistência e extrato corretos confirmados pelo usuário.
- **Evidência:** SQL e telas/console do teste.
- **Status:** `APROVADO`

### P3A-07 — restart completo

- **Passos:** reiniciar `mz_bank`, `mz_economy`, `mz_core` na ordem controlada e depois restaurar a
  ordem normal `mz_core -> mz_economy -> mz_bank`; abrir novamente ATM/agência.
- **Esperado:** readiness se recupera; banco abre; zero alteração inesperada de saldo ou schema;
  tabelas novas seguem vazias.
- **Resultado real:** restart/readiness e reabertura do banco confirmados pelo usuário.
- **Evidência:** console e SQL.
- **Status:** `APROVADO`

### P3A-08 — fail-closed estrutural controlado

- **Pré-condição:** staging restaurável, backup confirmado e janela exclusiva.
- **Passos:** remover temporariamente **um índice não primário** da outbox; reiniciar `mz_core`;
  confirmar falha; restaurar o mesmo índice pela definição do `SHOW CREATE TABLE`; reiniciar e
  confirmar recuperação. Repetir de forma equivalente no recibo/economy se autorizado.
- **Esperado:** readiness falha com `index_missing`; nenhuma tabela/saldo é apagado; depois da
  restauração, readiness volta ao normal.
- **Resultado real:** não executado; o usuário não informou fault injection destrutivo de índice.
- **Evidência:** backup, comandos SQL e console integral.
- **Status:** `NÃO APLICÁVEL`
- **Observação:** não executar em produção e não improvisar nomes/DDL. Se não houver staging
  restaurável, marcar `BLOQUEADO`, nunca aprovado por inferência.

## 5. Invariantes

1. Zero linhas nas duas tabelas durante todo o P3-A.
2. Zero mudança de saldo causada pelo schema/readiness.
3. Nenhum worker, consumer ou nova superfície pública.
4. Operações atuais continuam usando `mz_core` e o ledger atual.
5. Nenhuma alteração em `mz_player_accounts`, `mz_account_idempotency` ou
   `mz_economy_transactions` fora dos efeitos normais do smoke financeiro.
6. Feature continua desligada após restart.

## 6. Resultado consolidado

| Métrica | Resultado |
|---|---:|
| Casos | 8 |
| Executados | 7 |
| Aprovados | 7 |
| Falhas | 0 |
| Bloqueados | 0 |
| Não aplicáveis | 1 |
| Não executados | 0 |

```text
P3-A: [R] APROVADO EM RUNTIME
7 aprovados, 0 falhas, 0 bloqueados, 1 não aplicável
```

O fault injection destrutivo de drift não foi usado como evidência. A aprovação cobre criação,
schema, idempotência de startup, flags desligadas e regressão funcional confirmadas pelo usuário.
