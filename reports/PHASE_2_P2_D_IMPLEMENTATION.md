# Fase 2 — Implementação do Lote P2-D

Data: 2026-07-17  
Estado: **P2-D `[R]` — APROVADO EM RUNTIME**  
Runtime MySQL/FiveM: **8/8 GATES APROVADOS EM 2026-07-17**

## 1. Escopo implementado

O P2-D implementa somente o backfill controlado de identidade bancária pública:

- preview obrigatório e read-only;
- ACE dedicada `mz_bank.accounts.backfill`;
- apply desligado por padrão;
- confirmação forte;
- batch padrão 100, máximo 500;
- cursor estável por `mz_players.id`;
- criação pela mesma `EnsurePersonalAccount` do P2-C;
- repetição e retomada idempotentes;
- resumo agregado persistido por `mz_core:CreateDetailedLog`;
- nenhuma leitura ou escrita de saldo.

Não foram implementados resolução de destinatário, `resolutionToken`, transferência por conta,
cutover da NUI, phone, conta empresarial, PIX ou QR Code.

## 2. Contrato operacional

Comando server-side:

```text
mz_bank_accounts_backfill preview [batch_size] [after_player_id]
mz_bank_accounts_backfill apply <run_ref> <batch_size> <after_player_id> APPLY_PUBLIC_ACCOUNT_BACKFILL
```

Configuração:

```lua
Config.PublicAccount.Backfill = {
  Enabled = true,
  AllowApply = false,
  ApplyEnableConvar = 'mz_bank_p2d_backfill_apply',
  Ace = 'mz_bank.accounts.backfill',
  DefaultBatchSize = 100,
  MaxBatchSize = 500,
  PreviewMaxAgeSeconds = 1800,
  ConfirmationPhrase = 'APPLY_PUBLIC_ACCOUNT_BACKFILL'
}
```

O preview exige schema v3 ready. O apply exige também:

- feature P2-C ativa e CSPRNG ready;
- convar `mz_bank_p2d_backfill_apply = 1` ou liberação deliberada;
- mesmo ator, batch e cursor do preview;
- preview com no máximo 30 minutos;
- fingerprint do lote ainda idêntico;
- frase completa.

## 3. Fluxo

### Preview

1. valida configuração, schema, batch e cursor;
2. lê somente `mz_players.id`, `mz_players.citizenid` e o status da identidade;
3. consulta `batch + 1` para determinar `hasMore`;
4. contabiliza existentes, encerradas, ausentes e registros inválidos;
5. cria `run_ref` por CSPRNG;
6. persiste log agregado sem listar titulares ou rotas;
7. guarda apenas fingerprint e resumo em memória.

Preview nunca chama `EnsurePersonalAccount` e nunca cria conta.

### Apply

1. revalida flag, confirmação, ator, parâmetros e runtime;
2. relê o mesmo lote e compara fingerprint;
3. persiste `public_account_backfill_apply_started`;
4. pula identidades existentes/closed;
5. cria cada ausente em transação curta pela função idempotente do P2-C;
6. agrega criadas, existentes, closed, colisões e erros por código;
7. persiste o resumo final;
8. avança o cursor somente quando não há falha.

Em falha ou interrupção, `nextCursor` volta ao cursor anterior. Um novo preview do mesmo lote relê
as criações já confirmadas como existentes, permitindo retomada sem duplicidade.

## 4. Persistência e auditoria

Não foi criada tabela paralela. Os eventos agregados usam o contrato real:

```lua
exports['mz_core']:CreateDetailedLog('bank', action, payload)
```

Ações:

- `public_account_backfill_preview`;
- `public_account_backfill_apply_started`;
- `public_account_backfill_completed`;
- `public_account_backfill_interrupted`;
- `public_account_backfill_invalidated`.

O log contém apenas `run_ref`, cursores, contagens, códigos agregados e
`zeroBalanceChanges=true`. Não registra lista de `citizenid`, nomes ou números de conta.

## 5. Arquivos alterados

| Arquivo | Alteração |
|---|---|
| `config.lua` | política fechada do P2-D |
| `server/repository.lua` | paginação read-only de jogadores/identidades |
| `server/account_service.lua` | origem de metadata e contagem interna de colisões |
| `server/account_backfill.lua` | preview, apply, ACE, cursor, auditoria e retomada |
| `server/p2d_runtime_runner.lua` | runner técnico staging-only, inerte por padrão |
| `server/main.lua` | status explícito do backfill no startup |
| `fxmanifest.lua` | carrega o P2-D somente no servidor |
| `BANK_ROADMAP.md` | P2-D registrado como `[R]` após aprovação runtime |
| `mz_phone/docs/MZ_BANK_APP_PRODUCTION_AUDIT.md` | gates atuais, sem integrar phone |

Não foram alterados schema, migrations, `mz_core`, `mz_economy`, `mz_inventory`, client Lua,
NUI, animação, slot, cartão ou transferência.

## 6. Contratos reais utilizados

- schema real `mz_players(id, citizenid)`;
- `MZBankRepository.listPublicAccountBackfillRows`;
- `MZBankAccountService.EnsurePersonalAccount`;
- constraints `uq_mz_bank_accounts_owner_type` e `uq_mz_bank_accounts_route`;
- `MZBankAccountIdentity.IsValidStatus`;
- `mz_core:CreateDetailedLog`;
- `IsPlayerAceAllowed` para jogadores e `IsPrincipalAceAllowed` para `system.console`;
- comando server-side do runtime FiveM.

Nenhum export, evento de rede ou callback NUI novo foi criado.

## 7. Validações estáticas

```text
Lua syntax: PASS
preview_read_only=true
created=1
repeated_created=0
cursor=2
actor_bound=true
confirmation=true
apply_gate=true
schema_gate=true
snapshot_invalidation=true
failure_retry_cursor=true
```

Buscas confirmaram:

- nenhuma referência a `mz_player_accounts`, wallet, bank ou dirty no serviço P2-D;
- nenhuma query financeira;
- nenhuma superfície client-facing;
- nenhuma listagem de titulares/rotas em console ou auditoria;
- transferência por server ID e fluxos físicos não foram alterados.

## 8. Decisões e limitações

1. O resumo persistente usa `mz_logs`, evitando migration/tabela paralela.
2. O preview ativo fica em memória por 30 minutos. Após restart, o operador executa novo preview do
   mesmo cursor; as contas já criadas tornam a repetição idempotente.
3. O apply permanece desativado após deploy até liberação deliberada em staging.
4. Falha individual não apaga sucessos anteriores; o cursor não avança até o lote ser repetido sem
   falhas.
5. Backfill cria identidade, nunca saldo, item, cartão, extrato ou transferência.

## 9. Runtime pendente

- ACE ausente/presente;
- preview com apply desligado;
- batch 1, padrão 100 e máximo 500;
- confirmação, ator, run_ref e parâmetros adulterados;
- apply real em clone staging;
- repetição, paginação, restart e concorrência com lazy creation;
- closed e falha individual;
- logs agregados sem PII;
- snapshots wallet/bank/dirty idênticos;
- regressão física.

## 10. Estado final

```text
Fase 2: [~] Em implementação
P2-A: [R]
P2-B: [R]
P2-C: [R]
P2-D: [R] Aprovado em runtime
P2-E e seguintes: NÃO IMPLEMENTADOS
Runtime P2-D: 8 aprovados, 0 falhas, 0 bloqueados
```

Próximo passo: implementar somente o P2-E conforme `PHASE_2_DESIGN_REVIEW.md`, sem antecipar P2-F
ou lotes seguintes.
