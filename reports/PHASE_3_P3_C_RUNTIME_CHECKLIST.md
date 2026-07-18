# Fase 3 — Checklist runtime do P3-C

Data de criação: 2026-07-17  
Ambiente: MySQL/FiveM staging restaurável  
Estado: **APROVADO NO ESCOPO FUNCIONAL; GATES AVANÇADOS PRESERVADOS**

## 1. Limite

Este checklist valida somente o consumer privado e idempotente. A outbox continuará `pending`, pois
claim e ACK pertencem ao P3-D. Não apagar as quatro linhas criadas no P3-B.

## 2. Preparação

1. Fazer snapshot/backup do staging.
2. Registrar as contagens antes do teste com as queries da seção 3.
3. Em `mz_economy/shared/config.lua`, alterar temporariamente:

```lua
Config.Economy.FinancialOutbox = {
  Enabled = true,
  ConsumerEnabled = true,
  SchemaVersion = 1
}
```

4. No console:

```text
set mz_core_p3c_runtime_runner 1
restart mz_economy
restart mz_core
```

Logs esperados:

```text
[mz_economy][outbox] receipt schema ready version=1 enabled=true consumer=true
[mz_core][p3c-runner] enabled staging_only=true command=mz_core_p3c_consume_pending
```

## 3. Snapshots SQL

Antes e depois:

```sql
SELECT id, correlation_id, event_type, amount, fee, status, attempts,
       claim_token, processed_at, last_error
FROM mz_financial_outbox
ORDER BY id;

SELECT outbox_id, correlation_id, payload_version, entry_count, processed_at
FROM mz_economy_outbox_receipts
ORDER BY outbox_id;

SELECT transaction_id, citizenid, account, amount, balance_before, balance_after,
       direction, category, reason, source_resource, source_type, external_ref
FROM mz_economy_transactions
WHERE transaction_id LIKE 'mzoutbox:%'
ORDER BY transaction_id;

SELECT citizenid, wallet, bank, dirty
FROM mz_player_accounts
WHERE citizenid IN ('<PERSONAGEM_A>', '<PERSONAGEM_B>')
ORDER BY citizenid;
```

Invariantes: o consumo não altera saldo; status/attempts/claim/processed da outbox não mudam; cada
evento gera um recibo e duas pernas.

## 4. Execução principal

No console do servidor:

```text
mz_core_p3c_consume_pending 10
```

Para as quatro linhas P3-B ainda não consumidas, resultado esperado:

```text
executed=4 passed=4 replayed=0 failed=0 outbox_updates=0
```

Repetir as queries. Esperado: quatro recibos, oito lançamentos `mzoutbox:*`, saldos idênticos e as
quatro linhas da outbox ainda `pending`.

## 5. Replay

Executar o mesmo comando novamente:

```text
mz_core_p3c_consume_pending 10
```

Esperado:

```text
executed=4 passed=4 replayed=4 failed=0 outbox_updates=0
```

As contagens de recibos e ledger não podem aumentar.

## 6. Casos

| ID | Teste | Resultado esperado | Resultado real | Status |
|---|---|---|---|---|
| P3C-01 | startup/readiness | economy ready, consumer=true | Confirmado pelo usuário no staging | APROVADO |
| P3C-02 | invocador privado | apenas mz_core aceito | PENDENTE | NÃO EXECUTADO |
| P3C-03 | consumir 4 pendentes | 4 PASS, 4 recibos, 8 pernas | Primeira execução confirmada: 4 PASS, 0 falhas, 0 replay | APROVADO |
| P3C-04 | atomicidade | nenhuma meia operação | Consumo completo confirmado, sem resultado parcial informado | APROVADO |
| P3C-05 | replay | 4 replay; zero inserts novos | Segunda execução confirmada: 4 PASS, 4 replay, 0 falhas | APROVADO |
| P3C-06 | IDs determinísticos | `mzoutbox:id:1/2`, únicos | PENDENTE | NÃO EXECUTADO |
| P3C-07 | privacidade | sem license/token/source/PII indevida | PENDENTE | NÃO EXECUTADO |
| P3C-08 | ausência de saldo | snapshot financeiro idêntico | Usuário confirmou que o saldo não mudou durante o consumo | APROVADO |
| P3C-09 | outbox intocada | continua pending, sem claim/ACK | Usuário confirmou que a outbox permaneceu `pending` | APROVADO |
| P3C-10 | extrato | lançamentos consumidos aparecem uma vez | Usuário confirmou cada lançamento uma única vez | APROVADO |
| P3C-11 | restart | recibos/ledger persistem; replay seguro | PENDENTE | NÃO EXECUTADO |
| P3C-12 | falha SQL controlada | recibo e pernas fazem rollback conjunto | PENDENTE | NÃO EXECUTADO |

Estados: `NÃO EXECUTADO`, `APROVADO`, `FALHOU`, `BLOQUEADO`, `NÃO APLICÁVEL`.

## 7. Encerramento obrigatório

Restaurar no config:

```lua
Enabled = false,
ConsumerEnabled = false,
```

No console:

```text
set mz_core_p3c_runtime_runner 0
restart mz_core
restart mz_economy
```

Confirmar que o comando deixa de existir e que o log mostra `consumer=false`. Não remover recibos,
ledger ou outbox do teste.

## 8. Resultado consolidado

```text
Casos: 12
Aprovados: 7
Falhas: 0
Bloqueados: 0
Não executados: 5
P3-C: [R] Aprovado em runtime no escopo funcional
```

Os resultados foram fornecidos pelo usuário após execução manual no MySQL/FiveM staging. Não foram
anexados logs completos. Invocador hostil, conferência SQL nominal dos IDs, privacidade runtime,
restart e fault injection SQL permanecem no checklist end-to-end; não foram inferidos como aprovados.
