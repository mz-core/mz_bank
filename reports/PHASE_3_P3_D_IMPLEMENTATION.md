# MZ Bank — Implementação do Lote P3-D

Data: 2026-07-17  
Fase: 3 — Idempotência, outbox e auditoria  
Estado: **P3-D [R] APROVADO EM RUNTIME NO ESCOPO FUNCIONAL**

## 1. Escopo implementado

- worker periódico no ownership do `mz_core`;
- preflight privado de readiness do consumer antes do claim;
- recuperação de leases expirados;
- claim atômico em lote por UUID do MySQL;
- seleção exclusiva pelo `claim_token`;
- entrega ao consumer real do P3-C;
- ACK apenas por `id + status=processing + claim_token`;
- retry com backoff exponencial e jitter;
- `dead_letter` técnico para erro permanente ou limite de tentativas;
- health mínimo sem PII;
- comandos de observabilidade/execução manual somente em staging e desligados por padrão.

## 2. Arquivos alterados

| Arquivo | Alteração |
|---|---|
| `mz_core/config.lua` | configuração P3-D desligada por padrão |
| `mz_core/server/prepare.lua` | readiness/log do dispatcher |
| `mz_core/server/accounts/outbox_repository.lua` | claim, lease, ACK, retry, dead letter e health |
| `mz_core/server/accounts/outbox_dispatcher.lua` | ciclo do worker e integração privada |
| `mz_core/server/accounts/p3d_runtime_runner.lua` | status/run-once console-only em staging |
| `mz_economy/server/outbox_consumer.lua` | readiness privado para preflight |
| `mz_economy/server/main.lua` | export privado de readiness |
| `mz_bank/BANK_ROADMAP.md` | estado e próximo gate |

## 3. Configuração

```lua
Config.FinancialOutbox = {
  enabled = false,
  writesEnabled = false,
  schemaVersion = 1,
  dispatcher = {
    enabled = false,
    pollMs = 1000,
    batchSize = 25,
    leaseSeconds = 30,
    maxAttempts = 10,
    backoffBaseSeconds = 5,
    backoffMaxSeconds = 900,
    jitterPercent = 20
  }
}
```

O dispatcher efetivo exige schema ready, `FinancialOutbox.enabled=true` e
`dispatcher.enabled=true`. `writesEnabled` controla produtores, não o consumo de backlog.

## 4. Fluxo real

```text
recover lease expirado
  -> preflight mz_economy
  -> gerar UUID
  -> UPDATE pending elegível para processing + attempts + lease
  -> SELECT somente pelo UUID
  -> ConsumeFinancialOutbox
       -> sucesso/replay: ACK por id+token
       -> falha transitória: pending + next_retry_at
       -> permanente/max attempts: dead_letter
```

O preflight ocorre antes do claim. `mz_economy` parado, consumer desabilitado ou não ready não
consome tentativa. Uma indisponibilidade entre preflight e entrega é tratada por retry/lease.

## 5. Concorrência e crash safety

- `UPDATE ... ORDER BY id LIMIT batch` reivindica somente `pending` elegível;
- cada ciclo usa UUID opaco e não logado;
- o SELECT enxerga somente linhas desse token;
- ACK/reschedule/dead letter exigem o mesmo token;
- crash antes da entrega deixa lease recuperável;
- crash depois do commit do ledger e antes do ACK repete a entrega, mas o recibo P3-C retorna replay;
- falha ao gravar ACK não remove o claim; o lease expirará e recuperará a linha.

Não foi usado `SKIP LOCKED`, preservando compatibilidade com o schema/engine reais conhecidos.

## 6. Backoff e dead letter

O atraso é exponencial pelo número persistido de tentativas, limitado a 15 minutos e com jitter
server-side de ±20%. Erro `retryable=false` vai imediatamente para `dead_letter`; erro transitório
vai após a décima tentativa.

Este lote cria somente a transição técnica. Preview, ACE, reprocessamento, justificativa e auditoria
administrativa pertencem ao P3-E e não foram antecipados.

## 7. Health e privacidade

O estado interno registra contagens de ciclos, claims, processados, replays, retries, dead letters,
leases recuperados e falhas de ACK. Snapshot periódico contém `pending`, `processing`, `processed`,
`dead_letter` e idade do pending mais antigo.

Logs mostram somente ID técnico, tipo e resource sanitizados. Nunca mostram citizenid, correlationId,
payload, claim token, saldo ou metadata.

## 8. Validações estáticas

- parser Lua aprovou todos os arquivos alterados/adicionados;
- harness confirmou economy offline com zero claim;
- harness confirmou ACK condicionado ao token;
- harness confirmou retry transitório, erro permanente e limite de tentativas;
- harness confirmou falha de ACK recuperável por lease;
- repository harness confirmou os predicados `status + claim_token`;
- busca estática confirmou zero escrita em `mz_player_accounts` e zero endpoint de rede/NUI;
- o consumer continua aceitando somente o invocador `mz_core`.

## 9. Riscos e runtime pendente

1. Confirmar portabilidade runtime de `UUID()`, `TIMESTAMPADD` e `UPDATE ORDER BY LIMIT`.
2. Confirmar dois ciclos concorrentes sem dupla seleção.
3. Confirmar recuperação após restart durante lease.
4. Confirmar replay após ledger commitado e ACK ausente.
5. Confirmar economy offline sem incremento de attempts.
6. P3-D não oferece reprocessamento de dead letter.

## 10. Não implementado

- comando administrativo de dead letter;
- edição/recriação de payload;
- reconciliação e retenção;
- novos produtores (`AddMoney`, `RemoveMoney`, `SetMoney`, org/payroll);
- novo canal financeiro ou phone;
- aprovação completa da Fase 3.

## 11. Decisão

```text
Fase 3: [~] Em implementação
P3-D: [R] Aprovado em runtime no escopo funcional
Runtime: 8 aprovados, 0 falhas, 0 bloqueados, 4 gates avançados não executados
Próximo passo: P3-E — administração de dead letter e reconciliação
```
