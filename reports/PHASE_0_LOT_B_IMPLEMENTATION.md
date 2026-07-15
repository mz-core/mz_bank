# MZ Bank — Implementação do Lote B da Fase 0

Data: 2026-07-15  
Escopo: somente `B0-05` (resultado financeiro ambíguo) e `B0-06` (contrato de valores e limites).  
Estado: implementação e validação estática concluídas; runtime não aprovado.

## 1. Diagnóstico confirmado antes das alterações

### 1.1 Serviços financeiros reais do `mz_core`

Os exports efetivamente existentes em `mz_core/server/accounts/exports.lua` e usados pelo bridge são:

- `TransferMoneyBetweenAccounts(source, fromAccount, toAccount, amount, metadata)` para saque e depósito;
- `TransferBankBetweenPlayers(source, target, amount, metadata)` para transferência entre jogadores;
- `GetMoney`, `NormalizeMoneyAccount`, `AddMoney` e `RemoveMoney` nos demais fluxos já existentes.

`transferMoneyBetweenAccounts` usa lock por `citizenid`, persiste as duas colunas do mesmo jogador em um `UPDATE` e só então atualiza o cache. `transferBankBetweenPlayers` adquire os dois locks em ordem determinística, persiste remetente e destinatário com `MySQL.transaction.await` e atualiza os dois caches somente após o commit. Esses serviços e locks foram preservados.

### 1.2 Referência e correlationId reais

O core recebe `metadata.external_ref` e, quando a movimentação é confirmada, devolve exatamente esse valor em `result.transactionRef`. Não existia um campo independente chamado `correlationId`.

Decisão aplicada: `transactionRef` continua sendo a referência oficial; a resposta do `mz_bank` publica `correlationId` como alias do mesmo valor, sem gerar uma segunda identidade transacional.

### 1.3 Integração real com `mz_economy`

Depois do commit de saldo, o `mz_core` chama `mz_economy:RecordTransaction` em modo best effort. O ledger recebe `external_ref`, mas cada lançamento gera seu próprio `transaction_id`; falha ou indisponibilidade do `mz_economy` não reverte a movimentação oficial.

Consequência: o extrato não pode confirmar nem negar o commit. A implementação não consulta o ledger para decidir sucesso, não cria outbox no `mz_bank` e não altera a política best effort existente.

### 1.4 Tipos numéricos reais

- `mz_player_accounts.wallet`, `bank` e `dirty`: `BIGINT NOT NULL`;
- `mz_economy_transactions.amount`, `balance_before` e `balance_after`: `BIGINT`;
- o core anteriormente aplicava `math.floor` em vários serviços;
- o banco também truncava `tonumber(amount)` com `math.floor`, aceitando decimal e texto numérico de forma indevida.

O teto configurado do banco, `1.000.000`, já era muito inferior ao `BIGINT`. O novo contrato também limita qualquer configuração ao maior inteiro seguro de Lua/JSON (`9.007.199.254.740.991`), que continua abaixo do máximo do `BIGINT` assinado.

## 2. B0-05 — Resultado financeiro e idempotência

### 2.1 Confirmação separada do refresh

Saque, depósito e transferência agora montam uma resposta financeira própria com:

```text
ok = true
confirmed = true
correlationId = transactionRef oficial do mz_core
replayed = true|false
data.operation
data.channel
data.amount
data.fee
```

O overview/extrato é anexado depois como complemento visual. Se essa etapa falhar após o commit, a resposta continua `ok = true` e `confirmed = true`, preserva a referência oficial e informa `data.refreshError`. Assim, uma falha posterior não transforma sucesso financeiro em falha aparente.

### 2.2 Idempotência persistente mínima

Foi criada no domínio financeiro do `mz_core` a tabela `mz_account_idempotency`, com unicidade por:

```text
(source_resource, actor_citizenid, idempotency_key)
```

Ela armazena operação, fingerprint do comando, `correlation_id` e resultado confirmado. Para as operações atuais do banco:

- o registro idempotente e a alteração de saldo são gravados na mesma transação SQL;
- no saque/depósito, a transação reúne o registro idempotente e o `UPDATE` das duas contas do jogador;
- na transferência, a transação reúne o registro e os dois `UPDATE` de remetente/destinatário;
- a mesma chave e o mesmo payload recuperam o resultado anterior com `replayed = true`;
- a referência original é mantida e nenhuma nova movimentação ocorre;
- a mesma chave com operação ou payload divergente retorna `idempotency_conflict`;
- somente resultados que efetivamente fizeram commit são persistidos; falhas sem movimentação podem ser corrigidas e reenviadas.

Essa tabela é somente um registro mínimo de deduplicação. Não possui worker, entrega de evento, retry de ledger, dead letter ou reconciliação de outbox.

### 2.3 Replay da NUI

A NUI gera uma chave opaca de 16 a 64 caracteres para cada intenção financeira. Enquanto uma resposta não é conclusiva, a mesma combinação de operação, valor e destinatário reutiliza a chave. O estado pendente é mantido em `sessionStorage` para sobreviver a timeout/reload da página quando o runtime permitir.

O bloqueio `state.busy`, o lock de sessão e o rate limit continuam ativos. Repetir a mesma chave pode atravessar o cooldown apenas para recuperar o resultado; uma chave nova continua sujeita ao rate limit normal.

Uma transferência nova ainda exige destinatário online. A única exceção é a recuperação de uma transferência já confirmada: se o destinatário sair após o commit, a mesma chave pode recuperar o resultado persistido sem executar transferência offline.

## 3. B0-06 — Valores, limites e taxa

O servidor aceita somente valor com `type == number`, inteiro, positivo e finito. São rejeitados antes de chamar o core:

- decimal;
- zero;
- negativo;
- texto, inclusive texto numérico;
- `NaN`;
- infinito positivo ou negativo;
- valor acima do inteiro seguro;
- valor acima do limite da operação/canal.

### 3.1 Limites atuais

| Canal | Saque | Depósito | Transferência |
|---|---:|---:|---:|
| ATM | 1.000.000 | 1.000.000 | 1.000.000 |
| Agência | 1.000.000 | 1.000.000 | 1.000.000 |

Os limites ficam em `Config.TransactionLimits` e são escolhidos exclusivamente pelo `session.channel` resolvido no servidor.

### 3.2 Limite diário

Não existe limite diário nesta fase. A decisão está explícita em `Config.DailyTransactionLimit = false`. Portanto, teste de limite diário não é critério obrigatório enquanto essa funcionalidade não for implementada em fase autorizada.

### 3.3 Taxa e arredondamento

A taxa efetiva atual é `0%`. Se `Config.TransferFeePercent` for configurado acima de zero:

```text
taxa = floor(valor * percentual / 100)
```

A taxa é inteira, arredondada para baixo, debitada adicionalmente do remetente pelo serviço real do core e registrada na metadata do ledger. O destinatário recebe somente o valor da transferência. Valor mais taxa também deve permanecer dentro do inteiro seguro.

## 4. Arquivos alterados

- `mz_core/server/prepare.lua` — schema persistente mínimo de idempotência;
- `mz_core/server/accounts/repository.lua` — leitura do resultado e persistência atômica junto dos saldos;
- `mz_core/server/accounts/service.lua` — escopo, fingerprint, replay e retorno da referência oficial;
- `mz_bank/config.lua` — limites por canal/operação, ausência de limite diário, taxa/arredondamento e mensagens;
- `mz_bank/server/service.lua` — contrato estrito de valores, resposta confirmada, refresh complementar e chave idempotente;
- `mz_bank/server/main.lua` — DTOs restritos dos callbacks com `idempotencyKey`;
- `mz_bank/client/main.lua` — encaminhamento da chave gerada pela NUI;
- `mz_bank/html/script.js` — geração/reuso da chave e persistência pendente;
- `mz_bank/INTEGRATION.md` — contrato server-side, limites, taxa e idempotência;
- `mz_bank/reports/PHASE_0_BLOCKER_MATRIX.md` — somente `B0-05` e `B0-06` adicionados ao Lote B;
- este relatório.

Nenhum arquivo de layout/estilo da NUI, animação, alinhamento do ped, sessão física, slot do cartão ou saldo paralelo foi alterado.

## 5. Contratos utilizados

- `mz_core:TransferMoneyBetweenAccounts`;
- `mz_core:TransferBankBetweenPlayers`;
- `metadata.external_ref` → `result.transactionRef`;
- locks de conta e `MySQL.transaction.await` do domínio de accounts;
- `mz_economy:RecordTransaction` apenas como ledger posterior, sem autoridade de commit;
- `player.money.wallet`, `player.money.bank` e `mz_player_accounts` como fontes oficiais;
- callbacks `ox_lib` já existentes no `mz_bank`.

Não foram implementados phone, PIX, conta pública, destinatário offline novo, conta empresarial ou outbox completa.

## 6. Validações estáticas executadas

### 6.1 Sintaxe

- `luac -p`: aprovado para `mz_bank/server/service.lua`, `server/main.lua`, `server/repository.lua`, `client/main.lua`, `mz_core/server/accounts/service.lua`, `repository.lua` e `mz_core/server/prepare.lua`;
- `node --check mz_bank/html/script.js`: aprovado.

### 6.2 Contrato de valores

Um harness carregou diretamente o trecho real de validação e aprovou nove classes: mínimo, máximo, decimal, zero, negativo, texto, `NaN`, infinito e excesso do limite. Também aprovou canal de agência, negação de canal sem limite, taxa zero, arredondamento `floor` e formato da chave idempotente.

Resultado observado:

```text
VALUE_CONTRACT_OK cases=9 fee_floor=ok idempotency_key=ok
```

### 6.3 Replay e clique repetido

Um harness carregou `mz_core/server/accounts/service.lua` real com repositório simulado e chamou duas vezes cada serviço com a mesma chave. Foram observados:

- uma única escrita para transferência entre contas;
- uma única escrita para transferência entre jogadores;
- mesma `transactionRef` no replay;
- `replayed = true` na segunda resposta;
- recuperação mesmo após o destinatário ficar offline;
- `idempotency_conflict` ao alterar o payload com a mesma chave.

Resultado observado:

```text
IDEMPOTENCY_REPLAY_OK own_writes=1 transfer_writes=1 offline_recovery=ok conflict=ok
```

Essas validações são estáticas/simuladas e não aprovam runtime FiveM/MySQL.

## 7. Riscos e testes pendentes

- reiniciar `mz_core` é necessário para que o prepare crie `mz_account_idempotency` antes dos testes do banco;
- a ordem/readiness completa de resources pertence a `B0-07` e não foi alterada;
- migrations/readiness globais de `mz_bank_cards` pertencem a `B0-08` e não foram alteradas;
- a tabela idempotente mínima ainda não possui política de retenção/limpeza administrativa;
- falha do `mz_economy` continua podendo deixar o extrato incompleto, pois a outbox completa pertence à fase posterior;
- `sessionStorage` é somente conveniência do client; a proteção autoritativa é a unicidade e transação do core;
- é necessário testar com MySQL real: timeout após commit, callbacks concorrentes, reconnect, restart do `mz_bank`, restart durante operação, falha SQL e comparação cache/persistência;
- testar `999.999`, `1.000.000` e `1.000.001` em cada operação/canal, além de decimal, texto, `NaN` e infinito injetados diretamente;
- conferir que overview/extrato indisponível mantém `confirmed = true` e a mesma `correlationId`;
- conferir que o ledger das duas pontas usa o mesmo `external_ref` e que replay não gera nova alteração de saldo.

Nenhum desses testes foi executado ou aprovado em runtime neste relatório.
