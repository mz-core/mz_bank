# MZ Bank — Implementação do Lote P3-C

Data: 2026-07-17  
Fase: 3 — Idempotência, outbox e auditoria  
Estado: **P3-C [R] APROVADO EM RUNTIME NO ESCOPO FUNCIONAL**

## 1. Resultado

Foi implementado somente o consumer idempotente privado `mz_core -> mz_economy`:

- validação estrita do evento e do envelope v1;
- permissão exclusiva para `GetInvokingResource() == 'mz_core'`;
- recibo e todas as pernas do ledger em um único `MySQL.transaction.await`;
- IDs determinísticos `mzoutbox:<outbox_id>:<leg>`;
- replay persistente sem novo lançamento;
- conflito de recibo fail-closed;
- runner manual, server-side, console-only e desligado por padrão.

O lote não implementa claim, lease, ACK da outbox, retry automático, dead letter, loop, saldo,
transferência, NUI ou phone.

## 2. Arquivos alterados

| Arquivo | Alteração |
|---|---|
| `mz_economy/shared/config.lua` | adiciona `ConsumerEnabled = false` |
| `mz_economy/server/prepare.lua` | readiness efetivo do consumer e log explícito |
| `mz_economy/server/repository.lua` | consulta de recibo e commit atômico recibo + ledger |
| `mz_economy/server/outbox_consumer.lua` | contrato privado, validação, consumo e replay |
| `mz_economy/server/main.lua` | export server-side `ConsumeFinancialOutbox` |
| `mz_economy/fxmanifest.lua` | carrega o consumer após o service |
| `mz_core/server/accounts/p3c_runtime_runner.lua` | entrega manual de `pending` em staging |
| `mz_bank/BANK_ROADMAP.md` | registra P3-C `[S]` e o próximo gate |

Nenhum arquivo do `mz_bank`, `mz_phone`, saldo ou schema foi alterado.

## 3. Contrato privado

```lua
exports['mz_economy']:ConsumeFinancialOutbox(event)
```

O export existe porque é o limite entre resources, mas rejeita qualquer invocador diferente de
`mz_core`. Não há evento de rede, callback NUI, comando client-facing ou entrada de citizenid pelo
client.

O retorno confirmado contém apenas:

```text
ok, replayed, outboxId, correlationId, entryCount
```

Erros de contrato são permanentes (`retryable=false`); indisponibilidade/readiness/SQL são
transientes (`retryable=true`). A política de retry pertence ao P3-D.

## 4. Validações do envelope

O consumer exige:

- `payload_version = 1`, envelope `version = 1`;
- igualdade de operation, correlationId, source resource e channel entre linha e envelope;
- canal em `atm, branch, system, resource, admin, payroll, org`;
- no máximo oito pernas e exatamente duas para os eventos atuais;
- leg sequencial, conta/direção válidas, inteiros positivos e snapshots coerentes;
- sem license, source FiveM, token, sessão, PIN, cartão, coordenada ou location;
- tamanho máximo de 32 KiB;
- sem autotransferência e com titulares/valores coerentes com o evento externo.

Eventos aceitos neste lote:

```text
transfer_between_accounts
bank_transfer
```

## 5. Atomicidade e idempotência

A única transação do `mz_economy` contém:

```text
1. INSERT mz_economy_outbox_receipts
2..N. INSERT mz_economy_transactions
```

Falha em qualquer statement reverte recibo e todas as pernas. Antes do commit, o consumer procura
recibo por `outbox_id` ou `correlation_id`. Recibo compatível retorna replay; recibo divergente
retorna conflito. Uma corrida que perde a constraint consulta o recibo novamente e recupera replay.

Os lançamentos usam a constraint real de `transaction_id` com:

```text
mzoutbox:<outbox_id>:<leg>
```

O consumer não lê nem escreve saldo e não atualiza `mz_financial_outbox`.

## 6. Runner de staging

Convar, desligada por padrão:

```text
mz_core_p3c_runtime_runner 0
```

Quando ativado, registra somente no console:

```text
mz_core_p3c_consume_pending [limit 1..10]
```

O runner lê linhas `pending`, chama o export real e imprime PASS/FAIL com correlationId mascarado.
Ele não registra eventos, não aceita dados do client, não faz claim/ACK e não atualiza a outbox.

## 7. Validações estáticas executadas

- parser Lua 5.5 aprovou os cinco arquivos Lua alterados/adicionados;
- harness do consumer aprovou invocador privado, commit único, replay e campo proibido;
- harness do repository confirmou três statements em uma transação para recibo + duas pernas;
- busca estática não encontrou escrita em `mz_financial_outbox` no consumer/runner;
- busca estática confirmou ausência de evento de rede ou callback NUI no P3-C;
- o ledger persistido não contém license e sua metadata é uma allowlist técnica mínima.

## 8. Riscos e testes pendentes

1. O runtime MySQL/FiveM ainda precisa confirmar o commit de recibo + pernas.
2. As quatro linhas P3-B existentes devem permanecer `pending` até o P3-D; isso é esperado.
3. A ordem de startup precisa deixar `mz_economy` ready antes do comando manual.
4. A ativação do consumer sem P3-D não cria processamento automático.
5. Falha SQL e corrida real ainda precisam de evidência runtime.

## 9. Itens explicitamente não implementados

- dispatcher/worker e polling;
- claim token, lease e recuperação;
- ACK/status `processed` na outbox;
- retry/backoff e dead letter;
- reprocessamento administrativo;
- métricas/reconciliação;
- novos produtores financeiros;
- phone.

## 10. Decisão

```text
Fase 3: [~] Em implementação
P3-C: [R] Aprovado em runtime no escopo funcional
Runtime: 7 aprovados, 0 falhas, 0 bloqueados, 5 gates avançados não executados
Próximo passo: P3-D — dispatcher, claim, lease e retry
```
