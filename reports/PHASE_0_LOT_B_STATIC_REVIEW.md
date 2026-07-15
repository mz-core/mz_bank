# MZ Bank — Revisão estática do Lote B da Fase 0

Data: 2026-07-15  
Escopo: somente `B0-05` e `B0-06`.  
Resultado: três defeitos do Lote B corrigidos; demais itens aprovados estaticamente ou pendentes de runtime.  
Fase 0: não marcada como `[S]`.

## 1. Arquivos e contratos reavaliados

Foram relidos os caminhos atuais de:

- NUI → `client/main.lua` → callbacks de `server/main.lua`;
- `MZBankService.Withdraw`, `Deposit` e `Transfer`;
- `mz_core:TransferMoneyBetweenAccounts` e `TransferBankBetweenPlayers`;
- locks e persistência de `mz_core/server/accounts/service.lua` e `repository.lua`;
- schema `BIGINT` de `mz_player_accounts` e schema de `mz_account_idempotency`;
- registro posterior em `mz_economy:RecordTransaction`;
- resposta confirmada, overview/extrato complementar e replay da chave.

Contratos reais mantidos:

- saldo oficial somente em `player.money.wallet`, `player.money.bank` e `mz_player_accounts`;
- `metadata.external_ref` devolvido pelo core como `transactionRef`;
- `correlationId` do banco é alias desse mesmo valor;
- `mz_economy` é ledger best effort posterior ao commit;
- transferências permanecem sob os locks e transações SQL do `mz_core`.

## 2. Defeitos encontrados e corrigidos

### LB-SR-01 — Snapshot de saldo no resultado idempotente

**Classificação:** CORRIGIDO.

O `result_json` idempotente armazenava a tabela `balances` devolvida pelo core. Embora fosse um snapshot e não fosse usado como fonte oficial, a persistência era desnecessária e podia ser confundida com saldo paralelo.

Correção:

- o resultado persistido passou a conter somente confirmação, referência oficial, taxa e identificador interno mínimo do destinatário quando necessário à auditoria;
- `wallet` e `bank` não são gravados em `mz_account_idempotency`;
- o primeiro retorno ainda pode usar os saldos devolvidos em memória pelo core para atualizar a tela;
- replay consulta o overview atual; se ele falhar, a confirmação continua válida sem inventar saldo.

### LB-SR-02 — Overflow do saldo resultante

**Classificação:** CORRIGIDO.

O banco limitava o valor da operação ao inteiro seguro, mas o core não verificava se `saldo_destino + valor` ultrapassaria esse teto.

Correção:

- `transferMoneyBetweenAccounts` nega crédito que exceda `9.007.199.254.740.991`;
- `transferBankBetweenPlayers` nega `valor + taxa` fora do teto e crédito do destinatário que transborde;
- `mz_bank` converte `amount_overflow` em `transaction_limit`;
- nenhuma escrita ou linha idempotente é criada nesse caso.

O teto é inferior ao máximo do `BIGINT` assinado e evita perda de precisão de Lua/JSON antes de alcançar o banco de dados.

### LB-SR-03 — Identidade de auditoria em replay

**Classificação:** CORRIGIDO.

Se um server ID fosse reutilizado por outro jogador antes do replay, o log do banco poderia preferir o `citizenid` do ocupante atual, embora o core tivesse recuperado a operação antiga.

Correção:

- o log agora prefere `result.targetCitizenId`, persistido junto ao resultado original;
- o jogador atual no mesmo server ID não é notificado em replay;
- nenhuma transferência offline nova foi habilitada.

## 3. Verificações solicitadas

### 3.1 Decimal, zero, negativo e texto

**Classificação:** APROVADO ESTATICAMENTE.

`validateAmount` exige `type(amount) == 'number'`, valor finito, positivo, inteiro e até o teto seguro. Texto numérico não passa por `tonumber`; decimal não é truncado. `NaN` é rejeitado por `amount ~= amount`, e infinito é rejeitado explicitamente.

Os três callbacks financeiros encaminham o valor sem normalização permissiva e todos alcançam a mesma validação antes de chamar o core.

### 3.2 Limites e taxas

**Classificação:** APROVADO ESTATICAMENTE; PENDENTE DE RUNTIME.

`Config.TransactionLimits` possui limites separados para saque, depósito e transferência nos canais `atm` e `branch`, atualmente `1.000.000`. O canal vem de `session.channel`, não do payload financeiro.

Não existe limite diário: `Config.DailyTransactionLimit = false`. A taxa atual é `0%`; quando configurada, usa `floor(valor * percentual / 100)`, é inteira e o total `valor + taxa` também respeita o teto seguro.

### 3.3 Chave ausente, inválida, repetida e conflitante

**Classificação:** APROVADO ESTATICAMENTE; PENDENTE DE RUNTIME.

- ausência retorna `idempotency_required`;
- tamanho/formato inválido retorna `invalid_idempotency_key`;
- escopo persistente é `(source_resource, actor_citizenid, idempotency_key)`;
- mesma chave + mesmo fingerprint recupera a referência e marca `replayed = true`;
- operação ou payload divergente retorna `idempotency_conflict`;
- somente resultado confirmado é persistido; falha sem commit não bloqueia correção e nova tentativa.

A constraint única e a movimentação ficam na mesma transação SQL, eliminando a janela “saldo confirmado sem registro idempotente”.

### 3.4 Duplo clique/Enter

**Classificação:** APROVADO ESTATICAMENTE; PENDENTE DE RUNTIME.

A NUI bloqueia novo acionamento com `state.busy`. A intenção pendente mantém a mesma chave por operação/fingerprint em `sessionStorage`. No servidor, `session.busy`, rate limit, locks do core e unicidade persistente formam camadas adicionais. Mesmo que dois comandos iguais alcancem o core, somente um pode criar a linha idempotente e movimentar saldo.

### 3.5 Timeout depois do commit

**Classificação:** APROVADO ESTATICAMENTE; PENDENTE DE RUNTIME.

O abort do `fetch` retorna `bank_unavailable`, mas não apaga a chave pendente. Como saldo e resultado idempotente são confirmados na mesma transação, o retry da mesma intenção recupera o `transactionRef` original sem nova movimentação.

### 3.6 Falha de overview/extrato depois do sucesso

**Classificação:** APROVADO ESTATICAMENTE; PENDENTE DE RUNTIME.

`confirmedFinancialResponse` exige primeiro o `transactionRef` confirmado. Depois tenta `GetAccountOverview`; falha posterior apenas grava `data.refreshError`. A resposta permanece:

```text
ok = true
confirmed = true
correlationId = transactionRef
```

### 3.7 Referência oficial

**Classificação:** APROVADO ESTATICAMENTE; PENDENTE DE RUNTIME.

O banco cria `metadata.external_ref`, o core o devolve em `transactionRef`, e o banco publica o mesmo valor em `correlationId` no topo e nos dados da resposta. O mesmo `external_ref` é encaminhado aos lançamentos das duas pontas no `mz_economy`.

### 3.8 Ausência de saldo paralelo

**Classificação:** APROVADO ESTATICAMENTE após LB-SR-01; PENDENTE DE CONFERÊNCIA SQL.

- `mz_bank` não grava saldo;
- `mz_account_idempotency` não persiste `wallet`, `bank` ou `balances` no resultado;
- tabelas legadas continuam apenas no fluxo explícito de diagnóstico/migração e não recebem escrita operacional;
- overview lê o dinheiro pelo facade real do `mz_core`.

### 3.9 Locks e atomicidade do `mz_core`

**Classificação:** APROVADO ESTATICAMENTE; PENDENTE DE CONCORRÊNCIA RUNTIME.

Transferência entre contas mantém o lock do titular. Transferência entre jogadores mantém locks ordenados dos dois `citizenid`. Nos caminhos idempotentes, o insert da confirmação participa da mesma `MySQL.transaction.await` que altera as contas. Cache só é alterado depois do retorno positivo da persistência.

### 3.10 `mz_economy` indisponível

**Classificação:** APROVADO ESTATICAMENTE com limitação documentada; PENDENTE DE RUNTIME.

`recordLedgerChange` retorna sem falhar quando `mz_economy` não está iniciado. A operação de saldo e a idempotência continuam confirmadas. O overview sinaliza extrato indisponível sem negar o resultado financeiro.

Limitação esperada nesta fase: como a outbox completa foi expressamente excluída, o evento perdido enquanto `mz_economy` está offline não é recriado por replay. Isso deve ser observado no checklist, não tratado como saldo falho.

## 4. Buscas e validações estáticas

- nenhum `math.floor(tonumber(rawAmount...))` permanece nas entradas financeiras do banco;
- todos os callbacks financeiros carregam `idempotencyKey`;
- nenhum `encodeIdempotentResult(... financialResult)` permanece, evitando snapshot de saldo persistido;
- saque/depósito usam somente `TransferMoneyBetweenAccounts`;
- transferência usa somente `TransferBankBetweenPlayers`;
- resposta confirmada possui caminho explícito de `refreshError`;
- parsers aprovados: seis arquivos Lua alterados/dependentes e `html/script.js` com `node --check`.

Não foram executados casos de teste runtime, comandos financeiros, queries de alteração ou aprovação manual neste trabalho.

## 5. Arquivos alterados nesta revisão

- `mz_core/server/accounts/service.lua` — teto do saldo resultante e resultado idempotente mínimo;
- `mz_bank/server/service.lua` — mapeamento de overflow e identidade correta no log de replay;
- `mz_bank/reports/PHASE_0_LOT_B_STATIC_REVIEW.md` — este relatório;
- `mz_bank/reports/PHASE_0_LOT_B_RUNTIME_CHECKLIST.md` — checklist não executado.

Não foram alterados NUI visual, CSS, animação do ATM, alinhamento do ped, slot do cartão, sessões físicas, taxa configurada, limites configurados ou contratos dos demais lotes.

## 6. Estado final da revisão

- B0-05: **APROVADO ESTATICAMENTE após correções**.
- B0-06: **APROVADO ESTATICAMENTE após correções**.
- Bloqueios estáticos restantes: nenhum identificado no escopo.
- Runtime: **PENDENTE**.
- Fase 0: **não marcada como `[S]`**.
