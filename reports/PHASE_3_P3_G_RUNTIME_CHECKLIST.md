# Fase 3 — Checklist runtime final P3-G

Data: 2026-07-19  
Ambiente: MySQL/FiveM staging  
Estado: **APROVADO EM RUNTIME — 6/6 CASOS APROVADOS**

## Regra de execução

Este checklist testa somente os deltas avançados que não foram comprovados nos lotes anteriores.
Não repetir depósito, saque, transferência, payroll, taxa/refund ou smoke físico já aprovados.

Estados permitidos: `NÃO EXECUTADO`, `APROVADO`, `FALHOU`, `BLOQUEADO`.

## Execução consolidada

Pré-condições:

- `mz_core`, `mz_economy`, `mz_inventory` e `mz_bank` iniciados;
- outbox, writes, dispatcher e consumer habilitados no staging;
- backlog sem linha elegível `pending` ou lease já expirado;
- nenhum outro teste financeiro em execução.

No console:

```text
set mz_core_p3c_runtime_runner 0
set mz_core_p3d_runtime_runner 0
set mz_core_p3e_runtime_runner 0
set mz_core_p3f_runtime_runner 0
set mz_core_p3f_runtime_real_writes 0
set mz_core_p3g_runtime_runner 1
restart mz_core
ensure mz_economy
mz_core_p3g_runtime_test
```

O runner pausa somente o ciclo automático do dispatcher enquanto sua convar está ativa. Ele cria
fixtures reservadas `P3G_RT_OWNER`, não chama serviços de saldo e remove suas próprias linhas ao
final. Resultado obrigatório:

```text
PASS P3G-01
PASS P3G-02
PASS P3G-03
PASS P3G-04
PASS P3G-05
PASS P3G-06
SUMMARY executed=6 passed=6 failed=0 balances=false fixtures_remaining=0
```

Se ocorrer exceção, executar antes de qualquer repetição:

```text
mz_core_p3g_runtime_cleanup
```

Teardown obrigatório:

```text
set mz_core_p3g_runtime_runner 0
restart mz_core
ensure mz_economy
ensure mz_inventory
ensure mz_bank
```

Confirmar que `mz_core_p3g_runtime_test` deixa de existir e que os resources voltam a anunciar
readiness normal.

## Casos delta

| ID | Teste | Resultado esperado | Resultado real | Status |
|---|---|---|---|---|
| P3G-01 | claim concorrente | dois ciclos concorrentes não selecionam o mesmo evento; um token por linha; zero ledger duplicado | 6 linhas divididas 3/3 entre dois tokens; 6 consumos e 6 ACKs | APROVADO |
| P3G-02 | crash/lease | evento abandonado em `processing` volta a ser elegível após o lease e termina `processed` | `recovered=1`, novo claim e estado final `processed` | APROVADO |
| P3G-03 | commit antes do ACK | recibo/ledger já commitados são reconhecidos como replay; ACK posterior não duplica lançamento | recuperação 1, `replay=true`, 1 recibo e 1 ledger | APROVADO |
| P3G-04 | retry/backoff/dead letter | falhas incrementam attempts, respeitam atraso/limite e terminam em `dead_letter` sem mexer no saldo | retry em 5s, attempts 10 e estado final `dead_letter` | APROVADO |
| P3G-05 | rollback do consumer | falha SQL dirigida desfaz recibo e todas as pernas; nenhuma meia operação permanece | conflito único intencional; `outbox_consume_failed`, 0 recibo e 0 ledger novo | APROVADO |
| P3G-06 | teardown/readiness | runners e faults desligados; core/economy/bank ready; reconciliação sem divergência nova | fixtures removidas, saldos iguais, runner ausente e core/economy/bank ready após restart | APROVADO |

## Invariantes

- nenhuma execução altera `wallet`, `bank`, `dirty` ou saldo organizacional;
- fixtures usam identificadores reservados e nunca dados pessoais;
- nenhum evento de rede, callback NUI ou export de teste;
- consumer continua privado ao `mz_core`;
- uma outbox produz no máximo um recibo e o número exato de pernas;
- falha antes do commit deixa zero recibo e zero perna nova;
- falha depois do commit e antes do ACK é resolvida por replay;
- teardown elimina somente fixtures explicitamente criadas pelo runner e desativa todos os gates.

## Consolidação

| Métrica | Resultado |
|---|---:|
| Casos definidos | 6 |
| Executados | 6 |
| Aprovados | 6 |
| Falhas | 0 |
| Bloqueados | 0 |
| Não executados | 0 |

```text
P3-G: [R] Aprovado em runtime — 6/6 aprovados
Fase 3: [R] Aprovada em runtime
```

Não marcar a Fase 3 como `[R]` antes dos seis casos e da reconciliação final.

## Evidência runtime fornecida pelo usuário

Execução manual em MySQL/FiveM staging em 2026-07-19:

```text
PASS P3G-01 detail=rows=6 tokens=3,3 consumed=6 ack=6
PASS P3G-02 detail=recovered=1 claimed=1 final=processed
PASS P3G-03 detail=recovered=1 replay=true receipts=1 ledger=1
PASS P3G-04 detail=retry_after=5 attempts=10 final=dead_letter
PASS P3G-05 detail=error=outbox_consume_failed receipts=0 new_ledger=0 conflict_seed=1
PASS P3G-06 detail=fixtures_removed=true balances_equal=true
SUMMARY executed=6 passed=6 failed=0 balances=false fixtures_remaining=0
```

O erro SQL `Duplicate entry ... uq_mz_economy_transactions_txid` foi provocado deliberadamente pela
fixture P3G-05. O retorno subsequente comprovou rollback: nenhum recibo e nenhum ledger novo foram
persistidos. Não foi registrado como falha do produto.

O `PASS P3G-06` do runner comprovou cleanup de fixtures e igualdade dos saldos. No teardown externo,
o usuário desligou `mz_core_p3g_runtime_runner`, reiniciou o `mz_core` e iniciou novamente
`mz_economy`, `mz_inventory` e `mz_bank`. Os logs confirmaram:

```text
[mz_core][outbox] schema ready version=1 enabled=true writes=true dispatcher=true
[mz_core][outbox-dispatcher] started poll=1000ms batch=25 lease=30s max_attempts=10
[mz_economy][outbox] receipt schema ready version=1 enabled=true consumer=true
[mz_core][outbox-dispatcher] economy=ready reason=none
[mz_bank] ready schema_version=3; balances are provided exclusively by mz_core
No such command mz_core_p3g_runtime_test.
```

O teardown está aprovado. Nenhum teste bloqueado, não executado ou com falha permanece no P3-G.
