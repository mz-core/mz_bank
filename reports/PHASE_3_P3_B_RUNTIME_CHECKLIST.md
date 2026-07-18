# Fase 3 — Checklist runtime do P3-B

Data de criação: 2026-07-17  
Ambiente: MySQL/FiveM staging restaurável  
Estado: **APROVADO NO ESCOPO FUNCIONAL; RESILIÊNCIA AVANÇADA PENDENTE**

## 1. Aviso obrigatório

P3-B ainda não possui consumer. Com as flags ligadas, as operações serão confirmadas no saldo e
ficarão `pending`, sem lançamento imediato no extrato. Não habilitar em produção e não apagar os
eventos criados: o P3-C deverá consumi-los de forma idempotente.

## 2. Preparação

1. criar backup/snapshot;
2. registrar saldo e últimos lançamentos de dois personagens de staging;
3. confirmar `mz_financial_outbox` vazia ou identificar exatamente as linhas anteriores;
4. em `mz_core/config.lua`, alterar temporariamente:

```lua
enabled = true,
writesEnabled = true,
```

5. executar:

```text
restart mz_core
restart mz_economy
restart mz_bank
```

Log esperado:

```text
[mz_core][outbox] schema ready version=1 enabled=true writes=true
```

## 3. Queries

```sql
SELECT id, correlation_id, idempotency_key, event_type, account, amount, fee,
       source_resource, source_channel, payload_version, status, attempts,
       next_retry_at, created_at, processed_at, last_error
FROM mz_financial_outbox
ORDER BY id DESC
LIMIT 20;

SELECT source_resource, source_citizenid, idempotency_key, COUNT(*) AS total
FROM mz_financial_outbox
WHERE idempotency_key IS NOT NULL
GROUP BY source_resource, source_citizenid, idempotency_key
HAVING COUNT(*) > 1;

SELECT correlation_id, COUNT(*) AS total
FROM mz_financial_outbox
GROUP BY correlation_id
HAVING COUNT(*) > 1;
```

As duas queries de duplicidade devem retornar zero linhas.

## 4. Casos

| ID | Teste | Resultado esperado | Status |
|---|---|---|---|
| P3B-01 | startup com flags desligadas | banco atual funciona; zero outbox nova | APROVADO |
| P3B-02 | startup com flags ligadas | log `enabled=true writes=true`; resources ready | APROVADO |
| P3B-03 | depósito | saldo/cache corretos; uma outbox `transfer_between_accounts`, duas pernas | APROVADO |
| P3B-04 | saque | saldo/cache corretos; uma outbox, duas pernas | APROVADO |
| P3B-05 | transferência entre jogadores | deltas corretos; uma outbox `bank_transfer`, duas pernas | APROVADO |
| P3B-06 | taxa | perna remetente usa `amount+fee`; destinatário usa `amount` | NÃO APLICÁVEL |
| P3B-07 | duplo clique/replay | mesmo resultado/correlationId; uma outbox e um movimento | NÃO EXECUTADO |
| P3B-08 | concorrência | uma confirmação por chave; zero duplicidade | NÃO EXECUTADO |
| P3B-09 | erro SQL controlado | saldo, cache, idempotência e outbox fazem rollback juntos | NÃO EXECUTADO |
| P3B-10 | envelope/privacidade | v1 válido; sem license, source, token, PIN, cartão ou coordenadas | NÃO EXECUTADO |
| P3B-11 | ledger legado suprimido | correlationIds novos ainda não aparecem no ledger antes do consumer | APROVADO |
| P3B-12 | restart/persistência | eventos `pending` persistem sem alteração | APROVADO |
| P3B-13 | retorno seguro | flags novamente false; novos fluxos voltam ao ledger atual | APROVADO |

## 4.1 Evidência real fornecida

O usuário confirmou manualmente no FiveM que os valores foram recebidos e que, com a outbox ativa,
os lançamentos ainda não apareceram no extrato, conforme esperado antes do consumer. O MySQL
retornou quatro eventos persistentes:

```text
id=4 bank_transfer amount=10 status=pending
id=3 bank_transfer amount=10 status=pending
id=2 transfer_between_accounts amount=100 status=pending
id=1 transfer_between_accounts amount=100 status=pending
```

Depois de restaurar as flags para `false`, o usuário confirmou que uma nova operação voltou ao
extrato legado e que as quatro linhas anteriores permaneceram `pending`. Logs completos, metadata
JSON e versões do ambiente não foram anexados.

## 5. Encerramento obrigatório

Depois dos testes, restaurar em `mz_core/config.lua`:

```lua
enabled = false,
writesEnabled = false,
```

E executar:

```text
restart mz_core
restart mz_economy
restart mz_bank
```

Confirmar:

```text
[mz_core][outbox] schema ready version=1 enabled=false writes=false
```

Não remover eventos `pending`. Registrar IDs/correlationIds para o P3-C.

## 6. Resultado consolidado

```text
Casos: 13
Aprovados: 8
Falhas: 0
Bloqueados: 0
Não aplicáveis: 1
Não executados: 4 gates avançados/partes pendentes
P3-B runtime funcional: APROVADO
```

Replay forçado, concorrência, erro SQL e inspeção runtime integral do JSON permanecem para o teste
end-to-end. Eles não foram marcados como aprovados por inferência.
