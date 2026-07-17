# Fase 2 — Checklist runtime delta do Lote P2-H

Data: 2026-07-17  
Estado: **APROVADO**

Resultado registrado em 2026-07-17 conforme confirmação do usuário após execução manual no FiveM
staging. Não foram fornecidos anexos adicionais.

Este checklist não repete os 149 casos já aprovados. Valida somente as duas correções encontradas na
revisão final e um smoke após restaurar o estado normal.

Antes de iniciar, deixe runners e apply desligados:

```text
set mz_bank_p2b_runtime_runner 0
set mz_bank_p2d_runtime_runner 0
set mz_bank_p2e_runtime_runner 0
set mz_bank_p2f_runtime_runner 0
set mz_bank_p2f_runtime_allow_transfer 0
set mz_bank_p2d_backfill_apply 0
set mz_bank_public_account_p2c 0
restart mz_bank
```

## P2H-INIT-01 — reboot sem convar de staging

- **Pré-condição:** `mz_bank_public_account_p2c = 0`.
- **Passos:** reiniciar `mz_bank`; abrir ATM/agência; autenticar e abrir overview/transferência.
- **Esperado:** console informa `public account ready` e schema 3 ready; conta pública aparece e a
  resolução por agência/conta/DV funciona mesmo com a convar em 0.
- **Resultado real:** comportamento esperado confirmado pelo usuário no FiveM staging.
- **Status:** `APROVADO`
- **Executado por/data:** usuário / 2026-07-17.

## P2H-STATE-01 — matriz blocked/frozen

Executar somente em staging e restaurar `active` no bloco `finally` operacional.

```sql
UPDATE mz_bank_accounts
SET status = 'blocked', closed_at = NULL
WHERE citizenid = '<CITIZENID_TESTE>' AND account_type = 'personal';
```

- Em `blocked`: overview e depósito pequeno devem funcionar; saque e transferência devem retornar
  `account_blocked`; recebimento pela conta deve permanecer permitido.

```sql
UPDATE mz_bank_accounts
SET status = 'frozen', closed_at = NULL
WHERE citizenid = '<CITIZENID_TESTE>' AND account_type = 'personal';
```

- Em `frozen`: overview deve funcionar; depósito, saque, transferência e resolução como destino
  devem ser negados sem alteração de saldo.

Restaurar obrigatoriamente:

```sql
UPDATE mz_bank_accounts
SET status = 'active', closed_at = NULL
WHERE citizenid = '<CITIZENID_TESTE>' AND account_type = 'personal';
```

- **Esperado:** matriz exatamente igual ao desenho; nenhuma operação negada chama o core ou altera
  wallet/bank/ledger.
- **Resultado real:** matriz `blocked/frozen` e restauração `active` confirmadas pelo usuário no FiveM staging.
- **Status:** `APROVADO`
- **Executado por/data:** usuário / 2026-07-17.

Não alterar uma conta real para `closed`: o estado é terminal. Os gates de `closed` já foram cobertos
pelos runners/aprovações anteriores.

## P2H-REG-01 — smoke final em active

- **Pré-condição:** confirmar por SQL que os dois personagens estão `active`.
- **Passos:** restart `mz_bank`; abrir ATM; confirmar slot/animação/NUI; depositar R$1, sacar R$1 e
  transferir R$1 por agência/conta/DV; conferir receipt/extrato; fechar; repetir abertura na agência.
- **Esperado:** operações confirmadas uma vez, saldos/cache/SQL/ledger coerentes, `correlationId`
  presente, sem server ID ou identificador interno, fechamento e slot corretos.
- **Resultado real:** depósito, saque, transferência e regressão física confirmados pelo usuário no FiveM staging.
- **Status:** `APROVADO`
- **Executado por/data:** usuário / 2026-07-17.

## Consolidado

| Métrica | Resultado |
|---|---:|
| Casos delta | 3 |
| Executados | 3 |
| Aprovados | 3 |
| Falhas | 0 |
| Bloqueados | 0 |
| Não executados | 0 |

```text
P2-H: [R] Aprovado em runtime
P2-H runtime: APROVADO
Fase 2: [R] Aprovada em runtime
```

Os três deltas passaram e não há falha ou bloqueio conhecido. A decisão consolidada está registrada
em `PHASE_2_FINAL_DECISION.md`.

