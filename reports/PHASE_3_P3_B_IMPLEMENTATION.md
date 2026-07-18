# MZ Bank — Implementação do Lote P3-B

Data: 2026-07-17  
Fase: 3 — Idempotência, outbox e auditoria  
Lote: P3-B — envelope v1 e escrita atômica dos fluxos bancários atuais  
Estado: **VALIDADO ESTATICAMENTE; APROVADO NO ESCOPO FUNCIONAL DE RUNTIME**

## 1. Resultado

O P3-B implementou, atrás de flags desligadas por padrão:

- envelope financeiro v1 server-side;
- uma outbox por `correlationId`;
- duas pernas de ledger para depósito/saque e transferência;
- insert da outbox na mesma transação SQL do saldo;
- insert da idempotência no mesmo commit quando existe chave;
- supressão do ledger best effort apenas quando a outbox foi persistida;
- preservação integral do caminho anterior quando a feature está desligada.

```text
Fase 3: [~] Em implementação
P3-A: [R] Aprovado em runtime
P3-B: [R] Aprovado em runtime no escopo funcional
P3-B runtime: 8 aprovados, 0 falhas, 0 bloqueados; gates avançados preservados
```

Não foram implementados consumer, worker, claim, retry, dead letter ou phone.

## 2. Arquivos alterados

| Arquivo | Alteração |
|---|---|
| `mz_core/config.lua` | flags `enabled` e `writesEnabled`, ambas `false` |
| `mz_core/server/prepare.lua` | deriva readiness e escrita efetiva das flags |
| `mz_core/server/accounts/exports.lua` | torna o resource invocador autoritativo |
| `mz_core/server/accounts/service.lua` | valida e monta envelope; escolhe outbox ou ledger legado |
| `mz_core/server/accounts/repository.lua` | inclui outbox nos quatro commits reais |
| `mz_bank/BANK_ROADMAP.md` | estado do lote e próximo gate |
| `mz_bank/reports/PHASE_3_P3_B_IMPLEMENTATION.md` | este relatório |
| `mz_bank/reports/PHASE_3_P3_B_RUNTIME_CHECKLIST.md` | checklist sem execução |

Não foram alterados `mz_economy`, NUI, sessões, cartões ou saldos/schema do banco.

## 3. Operações cobertas

### 3.1 Transferência entre contas do mesmo jogador

Contrato real:

```lua
TransferMoneyBetweenAccounts(source, fromAccount, toAccount, amount, metadata)
```

É usado pelos depósitos e saques atuais. O envelope contém duas pernas:

```text
1. fromAccount / out / amount / before / after
2. toAccount   / in  / amount / before / after
```

### 3.2 Transferência bancária entre jogadores

Contrato real:

```lua
TransferBankBetweenPlayers(source, target, amount, metadata)
```

O envelope contém:

```text
1. remetente / bank / out / amount + fee / before / after
2. destinatário / bank / in / amount       / before / after
```

O campo escalar `amount` guarda o valor transferido e `fee` guarda a taxa separadamente.

## 4. Atomicidade implementada

| Caminho | Statements no mesmo `MySQL.transaction.await` |
|---|---|
| entre contas, sem chave | update das duas colunas + outbox |
| entre contas, com chave | idempotência + update + outbox |
| entre jogadores, sem chave | update remetente + update destinatário + outbox |
| entre jogadores, com chave | idempotência + dois updates + outbox |

Se o insert da outbox falhar, a transação retorna falha, o saldo não é confirmado e o cache não é
alterado. O cache continua sendo atualizado somente depois do commit positivo.

Em concorrência/replay, a constraint existente de `mz_account_idempotency` e a nova constraint da
outbox fazem parte da mesma transação. Após conflito, o service recupera o resultado persistido como
já fazia e não cria outra movimentação.

## 5. Envelope v1

O payload persistido em `metadata_json` possui apenas:

```text
version
operation
correlationId
entries[]
context.sourceResource
context.sourceChannel
context.sourceType
context.category
```

Cada entry contém:

```text
leg
citizenid (server-side)
account
direction
amount
balanceBefore
balanceAfter
category
reason
relatedCitizenid (server-side, quando aplicável)
countsAsIncome
countsAsExpense
```

Não são copiados license, source FiveM, token, PIN, cartão, coordenadas, sessão, resolução ou payload
NUI bruto. O envelope aceita no máximo oito pernas e 32 KiB serializados.

Valores precisam ser inteiros, positivos e menores ou iguais ao limite numérico já usado pelo core.
Taxa precisa ser inteira e não negativa. Textos possuem os mesmos limites do schema.

## 6. Canal e resource autoritativos

`mz_core/server/accounts/exports.lua` agora sempre substitui `__invokingResource` pelo valor real de
`GetInvokingResource()`. Metadata do chamador não escolhe o namespace idempotente.

O canal usa allowlist server-side:

```text
atm, branch, system, resource, admin, payroll, org
```

`phone` não está permitido no P3-B. Nos fluxos do banco, `atm`/`branch` vêm da sessão já validada no
servidor e inserida pelo `mz_bank` no metadata interno.

## 7. Feature flag e compatibilidade

Configuração padrão:

```lua
Config.FinancialOutbox = {
  enabled = false,
  writesEnabled = false,
  schemaVersion = 1
}
```

Quando qualquer flag está desligada:

- nenhuma outbox é montada ou inserida;
- assinaturas antigas continuam aceitas;
- o repository mantém o update simples quando aplicável;
- `recordLedgerChange()` continua sendo chamado como antes;
- ATM, agência e extrato permanecem no comportamento atual.

Quando ambas estão ligadas e o schema está ready:

- saldo/idempotência/outbox são atômicos;
- `recordLedgerChange()` não é chamado para a operação migrada;
- o evento fica `pending` aguardando o consumer futuro.

Como P3-C/P3-D ainda não existem, ativar as flags agora atrasa o extrato dessas operações. Isso é
permitido somente no teste controlado de staging e não em produção.

## 8. Diferenças e compatibilidade de cutover

Operações idempotentes concluídas antes da ativação podem ser recuperadas pela chave sem possuir
outbox, pois pertencem ao ledger best effort anterior. O P3-B não inventa eventos retroativos.

O cutover futuro começa em um instante explícito. Eventos `pending` criados no teste P3-B devem ser
preservados para validar o primeiro consumo no P3-C; não podem ser apagados sem reconciliação com o
saldo/ledger.

## 9. Validações estáticas executadas

`luac -p` aprovou:

```text
mz_core/config.lua
mz_core/server/prepare.lua
mz_core/server/accounts/exports.lua
mz_core/server/accounts/repository.lua
mz_core/server/accounts/service.lua
```

Harness com os módulos reais confirmou:

- composição atômica dos quatro caminhos do repository: 4/4;
- envelope ativo para transferência entre contas e jogadores;
- duas pernas e taxa correta;
- caminho desligado envia `outbox=nil` e mantém ledger anterior;
- canal `phone` termina antes da persistência;
- replay retorna o correlationId anterior sem novo repository call;
- envelope não copia location ou license;
- caminho com outbox não chama `mz_economy` sincronicamente.

Esses testes são estáticos/simulados e não aprovam MySQL/FiveM real.

## 10. Riscos e runtime pendente

1. P3-B não possui consumidor; eventos ativos ficam pendentes e não entram imediatamente no extrato.
2. Não ativar em produção antes de P3-C/P3-D.
3. Um erro SQL real precisa comprovar rollback conjunto no staging.
4. Replay de operação anterior ao cutover não ganha outbox retroativa.
5. `AddMoney`, `RemoveMoney`, `SetMoney`, cartões, organizações e payroll continuam fora do lote.
6. O envelope contém citizenids por necessidade do consumer, mas permanece exclusivamente no banco
   e no servidor.

## 11. Itens não implementados

- consumer/recibo;
- dispatcher/worker;
- claim/lease;
- retry/backoff;
- dead letter/reprocesso;
- métricas/reconciliação;
- produtores restantes;
- phone.

## 12. Decisão

```text
P3-B: [S] Validado estaticamente
Runtime: pendente
Próximo passo: executar PHASE_3_P3_B_RUNTIME_CHECKLIST.md
```
