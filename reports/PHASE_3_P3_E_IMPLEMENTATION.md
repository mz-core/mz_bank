# MZ Bank — Implementação do Lote P3-E

Data: 2026-07-17  
Fase: 3 — Idempotência, outbox e auditoria  
Estado: **P3-E [S] VALIDADO ESTATICAMENTE; RUNTIME NÃO EXECUTADO**

## 1. Escopo implementado

- administração server-side desligada por padrão;
- ACE específica `mz_core.financial_outbox.manage`;
- preview por ID ou correlationId explícito;
- motivo técnico obrigatório;
- preview com TTL, vínculo ao ator e capacidade limitada;
- gate separado de aplicação e frase `REPROCESS_DEAD_LETTER`;
- referência opaca de uso único;
- revalidação do envelope pelo consumer privado;
- snapshot imutável antes do update condicional;
- transição exclusiva `dead_letter -> pending`;
- auditoria antes/depois sem PII;
- reconciliação read-only e relatório de retenção sem purge.

## 2. Arquivos alterados

| Arquivo | Alteração |
|---|---|
| `mz_core/config.lua` | política administrativa fail-closed |
| `mz_core/server/accounts/outbox_repository.lua` | lookup, reprocesso condicional e queries read-only |
| `mz_core/server/accounts/outbox_admin.lua` | ACE, preview, confirmação, auditoria e comando |
| `mz_economy/server/outbox_consumer.lua` | validação privada sem persistência |
| `mz_economy/server/main.lua` | export privado de validação |
| `mz_bank/BANK_ROADMAP.md` | estado e próximo gate |

## 3. Política padrão

```lua
administration = {
  enabled = false,
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

Mesmo com a administração habilitada, reprocesso permanece bloqueado enquanto `allowApply=false` e
a convar não for ativada. Reconcile e preview continuam exigindo ACE.

## 4. Contratos

```text
mz_core_outbox reconcile
mz_core_outbox preview <id|correlation> <value> <reason_code>
mz_core_outbox reprocess <run_ref> REPROCESS_DEAD_LETTER
```

Não existe evento de rede, callback NUI ou export administrativo. O comando é registrado somente no
servidor quando a política está habilitada e também usa `RegisterCommand(..., true)`.

## 5. Segurança do reprocesso

1. ACE explícita;
2. seletor explícito, sem listagem pública;
3. linha deve estar em `dead_letter`;
4. envelope deve ser aceito novamente pelo validator privado do `mz_economy`;
5. preview gera UUID, expira em 120 segundos e pertence ao mesmo ator;
6. apply exige convar, referência e frase forte;
7. referência é removida antes da mutação e não pode ser reutilizada;
8. update exige ID, status, correlationId, versão e metadata idênticos ao preview;
9. apenas status/tentativas/lease/erro são reinicializados;
10. payload, correlationId, valores, saldo, recibo e ledger permanecem intactos.

## 6. Auditoria e privacidade

São registrados preview, solicitação, conclusão/falha e reconciliação no `mz_logs`. A auditoria usa
somente outbox ID, tipo, resource, tentativas, motivo técnico e estados. Não grava correlationId,
citizenid, payload, claim token, preview ref, saldo ou metadata.

## 7. Reconciliação read-only

O relatório conta:

- processed sem recibo;
- recibo com quantidade divergente de pernas;
- ledger `mzoutbox:*` sem recibo;
- pending acima do SLA;
- dead letters;
- correlationIds duplicados;
- processados elegíveis à retenção de 90 dias;
- grupos por tipo/resource/status e tentativas.

Não existe DELETE, TRUNCATE, DROP, correção automática, saldo compensatório ou edição de payload.

## 8. Validações estáticas

- parser Lua aprovou cinco arquivos;
- preview, apply gate, vínculo ao ator e one-time passaram em harness;
- reprocesso condicional preservou snapshot e não tocou saldo;
- auditoria não recebeu correlationId nem payload;
- reconcile executou quatro leituras e zero escrita;
- busca confirmou ausência de eventos, NUI, export administrativo e escrita financeira;
- retenção é somente métrica; `purge=false`.

## 9. Riscos e runtime pendente

1. Confirmar ACE real do `group.mz_owner` no staging.
2. Confirmar preview expirado/ator divergente no FiveM.
3. Confirmar reprocesso de fixture controlada sem duplicar recibo/ledger.
4. Confirmar auditoria real sem PII.
5. Confirmar queries de reconciliação na versão real do MySQL/MariaDB.
6. Falha da auditoria após update é reportada explicitamente como estado alterado.

## 10. Não implementado

- purge automático ou manual;
- alteração/correção de payload;
- lançamento compensatório;
- mudança de saldo;
- painel/NUI/API/client;
- produtores restantes do P3-F;
- phone;
- aprovação completa da Fase 3.

## 11. Decisão

```text
Fase 3: [~] Em implementação
P3-E: [S] Validado estaticamente
Runtime: NÃO EXECUTADO
Próximo passo: PHASE_3_P3_E_RUNTIME_CHECKLIST.md
```
