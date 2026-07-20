# Fase 3 — Checklist runtime do P3-E

Data de criação: 2026-07-17  
Ambiente: MySQL/FiveM staging restaurável  
Estado: **EM EXECUÇÃO — RECONCILIAÇÃO APROVADA**

## 1. Preparação

No `mz_core/config.lua`, manter P3-D ativo no staging e alterar temporariamente:

```lua
administration = {
  enabled = true,
  ace = 'mz_core.financial_outbox.manage',
  command = 'mz_core_outbox',
  allowApply = false,
  applyEnableConvar = 'mz_core_p3e_reprocess_apply',
  previewTtlSeconds = 120,
  confirmationPhrase = 'REPROCESS_DEAD_LETTER',
  pendingSlaSeconds = 300,
  processedRetentionDays = 90,
  reportLimit = 50
}
```

No `permissions.cfg` real:

```text
add_ace group.mz_owner mz_core.financial_outbox.manage allow
```

Para usar pelo console txAdmin em vez do F8 do owner, configurar antes do startup:

```text
add_ace system.console mz_core.financial_outbox.manage allow
```

Depois:

```text
set mz_core_p3e_reprocess_apply 0
restart mz_core
```

## 2. Reconcile inicial

```text
mz_core_outbox reconcile
```

Em estado saudável, os campos de divergência devem ser zero. `retention_eligible` pode ser maior que
zero no futuro e não provoca exclusão.

## 3. Fixture controlada

Escolher apenas uma outbox de teste já `processed`, com recibo e duas pernas confirmados. Registrar
ID e contagens. Em staging, simular somente o estado administrativo:

```sql
UPDATE mz_financial_outbox
SET status = 'dead_letter', attempts = 10, processed_at = NULL,
    last_error = 'p3e_runtime_fixture'
WHERE id = <OUTBOX_ID_DE_TESTE> AND status = 'processed';
```

O payload, correlationId, recibo, ledger e saldo não são modificados.

## 4. Preview e gates

```text
mz_core_outbox preview id <OUTBOX_ID_DE_TESTE> p3e_runtime_retry
```

Registrar o `run_ref`. Antes de habilitar apply:

```text
mz_core_outbox reprocess <RUN_REF> REPROCESS_DEAD_LETTER
```

Esperado: `reprocess_apply_disabled`, zero alteração.

Ativar apenas para o teste:

```text
set mz_core_p3e_reprocess_apply 1
```

Executar novamente com o mesmo preview ainda válido:

```text
mz_core_outbox reprocess <RUN_REF> REPROCESS_DEAD_LETTER
```

Esperado: `state_changed=true status=requeued`. O P3-D processará a linha; o consumer encontrará o
recibo e fará replay. A outbox volta a `processed`, sem nova linha de ledger.

Repetir o mesmo comando: esperado `preview_missing_or_expired`.

## 5. Conferência

```sql
SELECT id, status, attempts, processed_at, last_error
FROM mz_financial_outbox
WHERE id = <OUTBOX_ID_DE_TESTE>;

SELECT COUNT(*) AS receipts
FROM mz_economy_outbox_receipts
WHERE outbox_id = <OUTBOX_ID_DE_TESTE>;

SELECT COUNT(*) AS ledger_entries
FROM mz_economy_transactions
WHERE transaction_id LIKE CONCAT('mzoutbox:', <OUTBOX_ID_DE_TESTE>, ':%');

SELECT action, actor, target, data_json, created_at
FROM mz_logs
WHERE scope = 'financial_outbox'
ORDER BY id DESC
LIMIT 10;
```

Esperado: `processed`, um recibo, duas pernas e auditorias sem correlationId/citizenid/payload/ref.

## 6. Casos

| ID | Teste | Resultado esperado | Status |
|---|---|---|---|
| P3E-01 | administração desligada | comando inexistente | APROVADO — usuário confirmou o teardown com administração/runner/apply desligados e comando indisponível |
| P3E-02 | ACE ausente | acesso negado | APROVADO — console sem a ACE específica recebeu `admin_forbidden` |
| P3E-03 | reconcile | read-only, divergências corretas | APROVADO — após restaurar P3-D/P3-C e iniciar `mz_core -> mz_economy`, o backlog foi drenado; retorno final com `overdue_pending=0`, todas as divergências em zero, `read_only=true` e `balance_changes=false` |
| P3E-04 | seletor inexistente | resposta mínima, zero mudança | APROVADO — runner negativo retornou o resultado esperado, sem escrita |
| P3E-05 | preview válido | ref temporária, sem payload/PII | APROVADO — `outbox_id=4`, ref opaca com TTL 120, `state_changed=false`, `balance_changes=false` e `payload_changes=false` |
| P3E-06 | apply desligado/frase errada | negado, zero mudança | APROVADO — gate `apply=0` e confirmação incorreta foram negados sem mudança |
| P3E-07 | ator divergente/expiração | negado, zero mudança | APROVADO — runner confirmou negação por ator divergente e preview expirado |
| P3E-08 | reprocesso válido | requeued e depois processed | APROVADO — transição para `requeued`, dispatcher confirmou `consumer_replay=true` e a outbox voltou a `processed` |
| P3E-09 | replay da ref | negado; zero reprocesso novo | APROVADO — usuário confirmou o retorno esperado ao reutilizar a referência consumida |
| P3E-10 | recibo/ledger/saldo | 1 recibo, 2 pernas, saldo intacto | APROVADO — consulta final confirmou `receipts=1`, `ledger_entries=2`; replay não duplicou a movimentação |
| P3E-11 | auditoria | antes/depois sem PII/token | APROVADO — banco confirmou uma linha para preview, requested e completed; falso `audit_after_failed` do retorno foi localizado e corrigido |
| P3E-12 | retenção | reportada, nenhuma exclusão | APROVADO — reconcile reportou `retention_eligible=0`, permaneceu read-only e não executou purge |

## 7. Encerramento

### 7.1 Runner negativo consolidado

Os gates restantes `P3E-04`, confirmação errada de `P3E-06` e ator/expiração de `P3E-07` podem
ser executados sem fixture SQL pelo runner server-side temporário:

```text
set mz_core_p3e_runtime_runner 1
set mz_core_p3e_reprocess_apply 0
restart mz_core
ensure mz_economy
mz_core_p3e_runtime_test
```

O runner usa somente previews sintéticos em memória para os guardas que terminam antes do banco.
Ele faz uma busca inexistente read-only, compara as contagens da outbox antes/depois, não lê saldo,
não escreve ledger/outbox e restaura automaticamente a convar de apply ao valor anterior.

Depois da execução:

```text
set mz_core_p3e_runtime_runner 0
set mz_core_p3e_reprocess_apply 0
```

O caso `P3E-01` foi concluído manualmente: `administration.enabled=false`, restart do `mz_core` e
comando `mz_core_outbox` indisponível, conforme confirmação do usuário.

```text
set mz_core_p3e_reprocess_apply 0
```

Restaurar `administration.enabled=false`, reiniciar `mz_core` e confirmar que `mz_core_outbox` deixa
de existir. Não apagar outbox, recibos, ledger ou auditoria. Não iniciar P3-F nesta validação.

```text
P3-E: [R] Aprovado em runtime no escopo funcional
Runtime: CONCLUÍDO — 12 aprovados, 0 falhas financeiras, 0 bloqueados, 0 não executados
Fase 3: [~] Em implementação
```

Evidência parcial fornecida pelo usuário após execução manual; a linha integral do console não foi
anexada e nenhum valor adicional foi inferido.

Evidência inicial anexada: `RECONCILE ok=true ... overdue_pending=4 ... read_only=true` e startup do
`mz_core` com dispatcher desativado. O usuário restaurou as flags reais e reiniciou na ordem
`mz_core -> mz_economy`. O console confirmou `enabled=true`, `writes=true`, `dispatcher=true`,
consumer `enabled=true`, `consumer=true` e transição `economy=unavailable -> economy=ready`.

Evidência final fornecida pelo usuário após execução manual no MySQL/FiveM staging:

```text
[mz_core][p3d-runner] STATUS enabled=true ready=true cycles=8 claimed=0 processed=0 replayed=0 retried=0 dead_letter=0 recovered=0 ack_failures=0 pending=0 processing=0 oldest_pending=0
[mz_core][p3d-runner] PASS claimed=0 selected=0 processed=0 replayed=0 failed=0 recovered=0 skipped=false reason=none error=none
[mz_core][outbox-admin] RECONCILE ok=true processed_without_receipt=0 receipt_leg_mismatch=0 ledger_without_receipt=0 overdue_pending=0 dead_letter=0 retention_eligible=0 duplicate_outbox=0 duplicate_receipts=0 groups=2 read_only=true balance_changes=false error=none
```

O achado inicial foi resolvido pelo processamento normal do dispatcher, sem edição ou exclusão
manual da outbox e sem alteração de saldo. Os demais casos P3-E continuam pendentes.

Na execução controlada da outbox `id=4`, o usuário forneceu evidência de preview válido, bloqueio
com apply desligado, transição `dead_letter -> pending`, ACK com `consumer_replay=true` e retorno a
`processed`. A conferência SQL preservou um recibo e duas pernas. As três auditorias (`preview`,
`requested` e `completed`) existem uma vez cada. O console exibiu simultaneamente `ok=true` e
`error=audit_after_failed`; a causa foi a expressão Lua ambígua `afterAudit and nil or ...`, que
produzia o texto de erro mesmo no caminho verdadeiro. A expressão foi substituída por atribuição
condicional explícita; a correção ainda requer reload e uma validação focal do retorno.

O usuário informou que o runner negativo consolidado foi executado manualmente no FiveM staging e
retornou o resultado esperado. Foram aprovados `P3E-04`, a confirmação incorreta de `P3E-06`, ator e
expiração de `P3E-07`, além da invariável de contagens da outbox sem alteração, sem leitura de saldo
e sem escrita de ledger. O log integral não foi anexado; nenhum detalhe adicional foi inferido.

No encerramento, o usuário confirmou o resultado esperado após desligar administração, runner e
gate de apply. O caso `P3E-01` foi aprovado e o lote encerrou com 12 de 12 casos funcionais, zero
falhas financeiras e zero bloqueados. A correção do falso texto `audit_after_failed` foi carregada e
validada estaticamente; uma nova transição positiva dedicada não foi repetida e permanece como delta
de observação para o end-to-end P3-G.
