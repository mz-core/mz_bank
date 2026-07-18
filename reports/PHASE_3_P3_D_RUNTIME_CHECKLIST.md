# Fase 3 — Checklist runtime do P3-D

Data de criação: 2026-07-17  
Ambiente: MySQL/FiveM staging restaurável  
Estado: **APROVADO NO ESCOPO FUNCIONAL — 8 CASOS APROVADOS**

## 1. Ativação controlada

No `mz_economy/shared/config.lua`:

```lua
Enabled = true,
ConsumerEnabled = true,
```

No `mz_core/config.lua`:

```lua
enabled = true,
writesEnabled = true,
dispatcher = {
  enabled = true,
  pollMs = 1000,
  batchSize = 25,
  leaseSeconds = 30,
  maxAttempts = 10,
  backoffBaseSeconds = 5,
  backoffMaxSeconds = 900,
  jitterPercent = 20
}
```

Console:

```text
set mz_core_p3c_runtime_runner 0
set mz_core_p3d_runtime_runner 1
restart mz_economy
restart mz_core
```

Esperado:

```text
[mz_core][outbox] ... dispatcher=true
[mz_core][outbox-dispatcher] started poll=1000ms batch=25 lease=30s max_attempts=10
[mz_core][outbox-dispatcher] economy=ready reason=none
```

## 2. Queries

```sql
SELECT id, correlation_id, event_type, status, attempts, next_retry_at,
       claimed_at, lease_expires_at, processed_at, last_error
FROM mz_financial_outbox
ORDER BY id;

SELECT outbox_id, correlation_id, entry_count, processed_at
FROM mz_economy_outbox_receipts
ORDER BY outbox_id;

SELECT transaction_id, external_ref, account, direction, amount
FROM mz_economy_transactions
WHERE transaction_id LIKE 'mzoutbox:%'
ORDER BY transaction_id;
```

## 3. Sequência mínima

### P3D-01 — ACK dos quatro eventos já consumidos no P3-C

Após o restart, aguardar cinco segundos. As quatro linhas devem passar de `pending` para `processed`.
Como já possuem recibo, o consumer deve responder replay. As contagens de recibo e ledger não podem
aumentar.

### P3D-02 — operação nova end-to-end

Executar um depósito, um saque e uma transferência. Cada operação deve criar uma outbox e terminar
automaticamente como `processed`, com `processed_at`, recibo e duas pernas. Saldo/cache devem refletir
somente a operação financeira original e o extrato deve mostrar cada lançamento uma vez.

### P3D-03 — economy offline sem perda

1. `stop mz_economy`;
2. executar uma operação bancária migrada, se o fluxo permanecer disponível;
3. confirmar outbox `pending` e `attempts=0`;
4. aguardar pelo menos cinco segundos: attempts continua zero;
5. `start mz_economy`;
6. confirmar processamento automático e extrato único.

Se o próprio fluxo bancário bloquear por dependência dinâmica, registrar `BLOQUEADO`, sem inventar
uma operação ou editar a outbox.

### P3D-04 — restart e lease

Durante backlog/processamento, reiniciar `mz_core`. Nenhum saldo muda. Depois do lease, eventual
`processing` volta a ser elegível e termina `processed`; recibo impede duplicidade.

### P3D-05 — status sanitizado

```text
mz_core_p3d_runtime_status
```

O comando deve mostrar somente métricas, sem citizenid, correlationId, token ou payload.

## 4. Casos

| ID | Teste | Resultado esperado | Resultado real | Status |
|---|---|---|---|---|
| P3D-01 | startup e readiness | dispatcher/economy ready | Usuário confirmou os logs esperados no staging; logs integrais não anexados | APROVADO |
| P3D-02 | backlog P3-C | 4 ACK por replay; zero ledger duplicado | Usuário confirmou os ACKs/resultados esperados; evidência SQL não anexada | APROVADO |
| P3D-03 | operação nova | outbox -> receipt/ledger -> processed | Usuário confirmou depósito, saque e transferência com resultado esperado, processados e extrato sem duplicidade | APROVADO |
| P3D-04 | economy offline | pending/attempts=0; processa no retorno | Usuário confirmou o resultado esperado: sem tentativa durante indisponibilidade e processamento correto no retorno | APROVADO |
| P3D-05 | claim concorrente | uma posse por evento | PENDENTE | NÃO EXECUTADO |
| P3D-06 | crash/lease | lease recuperado; replay sem duplicar | PENDENTE | NÃO EXECUTADO |
| P3D-07 | retry/backoff | next_retry_at cresce e fica limitado | PENDENTE | NÃO EXECUTADO |
| P3D-08 | permanente/max attempts | dead_letter técnico, sem saldo novo | PENDENTE | NÃO EXECUTADO |
| P3D-09 | restart resources | retoma automaticamente | Usuário confirmou restart e retomada esperada | APROVADO |
| P3D-10 | health/privacidade | métricas corretas e sem PII | Usuário confirmou o status esperado no smoke final | APROVADO |
| P3D-11 | regressão física | ATM/agência/NUI/animação/slot preservados | Usuário confirmou smoke de ATM/agência aprovado | APROVADO |
| P3D-12 | saldo/persistência | zero saldo paralelo/divergência | Usuário confirmou transferência, saldo, extrato e persistência esperados | APROVADO |

## 5. Encerramento

Após registrar os resultados:

```text
set mz_core_p3d_runtime_runner 0
```

Restaurar temporariamente para `false` as flags do dispatcher, escrita e consumer, reiniciar
`mz_core`, `mz_economy` e `mz_bank`, e confirmar que os comandos P3-D deixam de existir.

Não apagar outbox, recibos ou ledger. Não reprocessar dead letter nesta etapa.

## 6. Estado

```text
P3-D: [R] Aprovado em runtime no escopo funcional
Runtime: 8 aprovados, 0 falhas, 0 bloqueados, 4 gates avançados não executados
Fase 3: [~] Em implementação
```

Registro funcional: os resultados acima foram fornecidos pelo usuário após execução manual no staging.
Nenhum log ou resultado SQL foi inventado nesta atualização.
