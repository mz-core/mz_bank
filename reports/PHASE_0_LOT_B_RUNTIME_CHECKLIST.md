# MZ Bank — Checklist runtime do Lote B da Fase 0

Data de preparação: 2026-07-15  
Escopo: somente `B0-05` e `B0-06`.

## Estado deste documento

Todos os casos abaixo estão **NÃO EXECUTADOS**. Este documento não aprova runtime, não marca a Fase 0 como `[S]` e não autoriza avanço de fase.

## Regras de execução e evidência

1. Executar somente em staging, com backup/snapshot e personagens descartáveis.
2. Reiniciar primeiro `mz_core` para preparar `mz_account_idempotency`; depois iniciar `mz_economy` e `mz_bank` na ordem real do servidor.
3. Registrar configuração efetiva de `TransactionLimits`, `DailyTransactionLimit`, `TransferFeePercent` e `TransferFeeRounding`.
4. Manter console F8, console do servidor, log detalhado do core e acesso SQL somente leitura para conferência.
5. Payload adulterado, timeout artificial e falha SQL exigem harness temporário autorizado e documentado. Não alterar o código avaliado durante a rodada.
6. Nunca publicar token, chave completa ou `citizenid`; redigir evidências, preservando os valores completos somente na planilha/arquivo seguro da rodada.
7. Capturar saldo antes e depois no SQL e na NUI. Não deduzir aprovação apenas pela mensagem visual.
8. Preencher cada caso com `PASSOU`, `FALHOU` ou `BLOQUEADO`. `BLOQUEADO` não equivale a aprovação.
9. Falhas controladas de MySQL/restart devem ser feitas somente por operador autorizado, com plano de restauração. As queries deste documento são de leitura.
10. Não executar casos de taxa diferente de zero em produção. Se autorizados em staging, restaurar a configuração e reiniciar os resources antes de continuar.

## Ambiente da rodada

- **Executor:** `[PENDENTE]`
- **Data/hora:** `[PENDENTE]`
- **Servidor/build/artifacts/OneSync:** `[PENDENTE]`
- **Pacote implantado:** `[PENDENTE]`
- **Ordem e estado dos resources:** `[PENDENTE]`
- **Versão de MySQL/MariaDB e oxmysql:** `[PENDENTE]`
- **Personagem A / source redigido:** `[PENDENTE]`
- **Personagem B / source redigido:** `[PENDENTE]`
- **Saldo inicial A (`wallet`, `bank`):** `[PENDENTE]`
- **Saldo inicial B (`wallet`, `bank`):** `[PENDENTE]`
- **Harness/fault injector autorizado:** `[PENDENTE]`
- **Backup/snapshot:** `[PENDENTE]`
- **Configuração de limites/taxa:** `[PENDENTE]`

## Invariantes obrigatórios

### INV-B-01 — Saque e depósito sem taxa

```text
wallet_antes + bank_antes = wallet_depois + bank_depois
```

### INV-B-02 — Transferência entre jogadores

Com taxa zero:

```text
bank_A_antes + bank_B_antes = bank_A_depois + bank_B_depois
```

Com taxa configurada:

```text
bank_A_antes + bank_B_antes = bank_A_depois + bank_B_depois + taxa
```

### INV-B-03 — Idempotência

```text
mesmo actor + resource + chave + payload
= uma linha idempotente + uma movimentação + uma correlationId
```

### INV-B-04 — Falha atômica

```text
sem commit de saldo = sem linha idempotente confirmada
linha idempotente confirmada = saldo persistido na mesma transação
```

### INV-B-05 — Referência

```text
response.correlationId
= response.data.correlationId
= response.data.transactionRef
= mz_account_idempotency.correlation_id
= mz_economy_transactions.external_ref (quando o ledger estiver disponível)
```

### INV-B-06 — Cache e persistência

```text
saldo da NUI após refresh/reconnect = mz_player_accounts = player.money carregado pelo core
```

### INV-B-07 — Ausência de saldo paralelo

```text
mz_account_idempotency.result_json não contém wallet, bank ou balances
mz_bank não escreve bank_accounts ou bank_transactions
```

### INV-B-08 — Sucesso financeiro independente da visualização

```text
commit confirmado + falha de overview/extrato
= ok true + confirmed true + correlationId preservada + refreshError
```

## Queries de conferência — somente leitura

Substituir os placeholders sem registrar identificadores completos em evidência pública.

### Q-B-01 — Schema e índices idempotentes

```sql
SHOW COLUMNS FROM mz_account_idempotency;
SHOW INDEX FROM mz_account_idempotency;
SHOW COLUMNS FROM mz_player_accounts;
```

Esperado: unicidade de `(source_resource, actor_citizenid, idempotency_key)`, unicidade de `correlation_id` e saldos oficiais como `BIGINT`.

### Q-B-02 — Saldos oficiais

```sql
SELECT citizenid, wallet, bank, dirty, updated_at
FROM mz_player_accounts
WHERE citizenid IN ('<CID_A>', '<CID_B>');
```

### Q-B-03 — Resultado por chave

```sql
SELECT source_resource, actor_citizenid, idempotency_key, operation,
       request_fingerprint, correlation_id, result_json, created_at
FROM mz_account_idempotency
WHERE source_resource = 'mz_bank'
  AND actor_citizenid = '<CID_A>'
  AND idempotency_key = '<KEY>';
```

### Q-B-04 — Duplicidade de escopo/correlationId

```sql
SELECT source_resource, actor_citizenid, idempotency_key, COUNT(*) AS total
FROM mz_account_idempotency
GROUP BY source_resource, actor_citizenid, idempotency_key
HAVING COUNT(*) > 1;

SELECT correlation_id, COUNT(*) AS total
FROM mz_account_idempotency
GROUP BY correlation_id
HAVING COUNT(*) > 1;
```

Esperado: zero linhas em ambas.

### Q-B-05 — Ausência de snapshot de saldo idempotente

```sql
SELECT id, correlation_id,
       result_json LIKE '%"balances"%' AS has_balances,
       result_json LIKE '%"wallet"%' AS has_wallet,
       result_json LIKE '%"bank"%' AS has_bank
FROM mz_account_idempotency
WHERE correlation_id = '<CORRELATION_ID>';
```

Esperado: `has_balances = 0`, `has_wallet = 0`, `has_bank = 0`.

### Q-B-06 — Ledger pela referência oficial

```sql
SELECT transaction_id, citizenid, account, amount, balance_before,
       balance_after, direction, category, reason, source_resource,
       source_type, related_citizenid, external_ref, created_at
FROM mz_economy_transactions
WHERE external_ref = '<CORRELATION_ID>'
ORDER BY id;
```

Esperado com `mz_economy` disponível: duas linhas por operação atual — duas contas do mesmo titular em saque/depósito ou remetente/destinatário na transferência — compartilhando `external_ref`.

### Q-B-07 — Delta do ledger

```sql
SELECT external_ref,
       SUM(CASE WHEN direction = 'in' THEN amount ELSE -amount END) AS net_delta,
       COUNT(*) AS entries
FROM mz_economy_transactions
WHERE external_ref = '<CORRELATION_ID>'
GROUP BY external_ref;
```

Esperado: `net_delta = 0` sem taxa; com taxa, `net_delta = -taxa`; `entries = 2` para os fluxos atuais.

### Q-B-08 — Presença de tabelas legadas

```sql
SELECT table_name, table_rows
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name IN ('bank_accounts', 'bank_transactions');
```

Se existirem, registrar `table_rows` antes/depois como indício e usar contagem exata autorizada para confirmar que operações do Lote B não escrevem nelas.

---

## Valores, limites e taxas

### RTB-VAL-01 — Valores inválidos

- **ID:** `RTB-VAL-01`
- **Pré-condição:** sessão autenticada válida; harness autorizado capaz de enviar o payload real sem normalização da NUI.
- **Passos:** chamar separadamente saque, depósito e transferência com `1.5`, `0`, `-1`, `'100'`, texto não numérico, `null` e, se o harness Lua suportar, `NaN`, `math.huge` e `-math.huge`; usar chave nova válida em cada tentativa.
- **Resultado esperado:** decimal/zero/negativo/texto/NaN/infinito negados com `invalid_amount`; nenhuma alteração em Q-B-02, nenhuma linha em Q-B-03 e nenhum ledger em Q-B-06.
- **Evidência:** `[PENDENTE — payloads redigidos, respostas, saldos/contagens antes e depois]`
- **Console:** `[PENDENTE — client/server, sem stack trace]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

### RTB-LIM-01 — Limites por operação e canal

- **ID:** `RTB-LIM-01`
- **Pré-condição:** saldo suficiente; limites efetivos em `1.000.000`; sessões válidas de ATM e agência.
- **Passos:** para saque, depósito e transferência, testar `999.999`, `1.000.000` e `1.000.001` em ATM e agência, restaurando saldos entre cenários; usar chave nova por intenção.
- **Resultado esperado:** dois primeiros valores seguem o fluxo normal se houver saldo; `1.000.001` retorna `transaction_limit`; limite é determinado pelo canal da sessão; nenhum teste diário é exigido.
- **Evidência:** `[PENDENTE — matriz 3 operações × 2 canais × 3 valores, respostas e SQL]`
- **Console:** `[PENDENTE]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

### RTB-FEE-01 — Taxa zero e arredondamento

- **ID:** `RTB-FEE-01`
- **Pré-condição:** primeiro rodar com taxa oficial `0`; teste opcional de `1,5%` somente em staging autorizado, com snapshot e restauração.
- **Passos:** transferir `101`; registrar débito/crédito, resposta e ledger. No cenário opcional, configurar `1.5`, reiniciar na ordem correta e repetir com chave nova.
- **Resultado esperado:** taxa zero debita/credita `101`; com `1,5%`, `floor(1,515) = 1`, remetente debita `102`, destinatário recebe `101`, resposta/metadata registram taxa `1`; INV-B-02 respeitado.
- **Evidência:** `[PENDENTE — configuração, saldos, response, Q-B-06/Q-B-07 e restauração]`
- **Console:** `[PENDENTE]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

## Operações financeiras básicas

### RTB-DEP-01 — Depósito confirmado

- **ID:** `RTB-DEP-01`
- **Pré-condição:** A com wallet suficiente; sessão autenticada; valor inteiro dentro do limite.
- **Passos:** registrar Q-B-02; depositar `100`; capturar resposta; executar Q-B-02/Q-B-03/Q-B-06; atualizar NUI.
- **Resultado esperado:** wallet `-100`, bank `+100`; `ok/confirmed = true`; correlationId única; INV-B-01, INV-B-03 e INV-B-05 atendidos.
- **Evidência:** `[PENDENTE — vídeo, resposta redigida e queries]`
- **Console:** `[PENDENTE]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

### RTB-WDR-01 — Saque confirmado

- **ID:** `RTB-WDR-01`
- **Pré-condição:** A com bank suficiente; sessão autenticada; valor inteiro dentro do limite.
- **Passos:** registrar Q-B-02; sacar `100`; capturar resposta; executar Q-B-02/Q-B-03/Q-B-06; atualizar NUI.
- **Resultado esperado:** bank `-100`, wallet `+100`; sucesso confirmado e referência consistente; total preservado.
- **Evidência:** `[PENDENTE]`
- **Console:** `[PENDENTE]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

### RTB-TRF-01 — Transferência confirmada

- **ID:** `RTB-TRF-01`
- **Pré-condição:** A e B online; A com bank suficiente; taxa conhecida; server ID de B válido.
- **Passos:** registrar Q-B-02; transferir `100` de A para B; capturar resposta/notificação; executar Q-B-02/Q-B-03/Q-B-06/Q-B-07.
- **Resultado esperado:** A debita `100 + taxa`; B credita `100`; uma linha idempotente; duas linhas de ledger com o mesmo external_ref; notificação única para B.
- **Evidência:** `[PENDENTE — duas telas, resposta e queries]`
- **Console:** `[PENDENTE]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

### RTB-FUNDS-01 — Saldo insuficiente

- **ID:** `RTB-FUNDS-01`
- **Pré-condição:** preparar separadamente wallet insuficiente para depósito e bank insuficiente para saque/transferência.
- **Passos:** tentar cada operação com chave válida nova; capturar resposta; conferir Q-B-02/Q-B-03/Q-B-06.
- **Resultado esperado:** `not_enough_wallet` ou `not_enough_bank`; nenhum saldo muda; nenhuma confirmação idempotente ou ledger é criada.
- **Evidência:** `[PENDENTE]`
- **Console:** `[PENDENTE]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

### RTB-REC-01 — Autotransferência

- **ID:** `RTB-REC-01`
- **Pré-condição:** sessão de A; usar o próprio server ID como destino.
- **Passos:** transferir valor válido; conferir resposta, saldo e ausência de linhas.
- **Resultado esperado:** `self_transfer`; nenhuma movimentação, idempotência ou ledger.
- **Evidência:** `[PENDENTE]`
- **Console:** `[PENDENTE]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

### RTB-REC-02 — Destinatário inválido e offline

- **ID:** `RTB-REC-02`
- **Pré-condição:** harness autorizado; IDs decimal, texto, inexistente e de jogador que acabou de sair.
- **Passos:** tentar cada destino com valor/chave válidos; conferir saldo e tabelas.
- **Resultado esperado:** formato inválido retorna `recipient_invalid`; ID válido sem player retorna `recipient_offline`; nenhuma transferência offline nova, idempotência ou ledger.
- **Evidência:** `[PENDENTE]`
- **Console:** `[PENDENTE]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

## Idempotência, replay e resposta ambígua

### RTB-IDEM-01 — Chave ausente ou inválida

- **ID:** `RTB-IDEM-01`
- **Pré-condição:** sessão válida; harness autorizado.
- **Passos:** repetir cada operação sem chave, com chave curta, longa e contendo caractere fora de `[A-Za-z0-9_-]`.
- **Resultado esperado:** `idempotency_required` ou `invalid_idempotency_key`; nenhuma movimentação/linha.
- **Evidência:** `[PENDENTE]`
- **Console:** `[PENDENTE]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

### RTB-IDEM-02 — Mesma chave e mesmo payload

- **ID:** `RTB-IDEM-02`
- **Pré-condição:** operação normal concluída e chave capturada de forma segura.
- **Passos:** reenviar exatamente a mesma operação/valor/destino e chave após o cooldown; comparar respostas e executar Q-B-02/Q-B-03/Q-B-04/Q-B-06.
- **Resultado esperado:** segunda resposta `ok = true`, `confirmed = true`, `replayed = true`; mesma correlationId; saldo e ledger não mudam novamente; notificação do destinatário não se repete.
- **Evidência:** `[PENDENTE — duas respostas, uma linha idempotente e contagem de ledger]`
- **Console:** `[PENDENTE]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

### RTB-IDEM-03 — Mesma chave com payload conflitante

- **ID:** `RTB-IDEM-03`
- **Pré-condição:** chave já confirmada.
- **Passos:** reutilizar a chave mudando valor, destino e depois tipo de operação; conferir saldos e tabelas.
- **Resultado esperado:** `idempotency_conflict`; resultado original preservado; nenhuma segunda movimentação ou correlationId.
- **Evidência:** `[PENDENTE]`
- **Console:** `[PENDENTE]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

### RTB-UI-01 — Duplo clique/Enter

- **ID:** `RTB-UI-01`
- **Pré-condição:** NUI aberta; saldo suficiente; captura de requests habilitada.
- **Passos:** acionar confirmar rapidamente por clique duplo, Enter repetido e clique+Enter em depósito, saque e transferência.
- **Resultado esperado:** interface entra em busy; no máximo uma intenção alcança commit; se houver duas respostas, a posterior é busy/rate limited ou replay da mesma chave; somente uma movimentação e uma correlationId.
- **Evidência:** `[PENDENTE — vídeo, requests/chaves redigidas e Q-B-02/Q-B-03]`
- **Console:** `[PENDENTE]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

### RTB-TIME-01 — Timeout após commit

- **ID:** `RTB-TIME-01`
- **Pré-condição:** fault injector autorizado capaz de descartar/atrasar apenas a resposta client-side depois de confirmar Q-B-03; preservar a chave no client.
- **Passos:** enviar operação; provocar timeout depois do commit; confirmar saldo/linha; reenviar a mesma intenção/chave; conferir ledger.
- **Resultado esperado:** primeira UI informa indisponibilidade/timeout; retry recupera sucesso com mesma correlationId e `replayed = true`; saldo movimentado uma vez; ledger no máximo uma vez.
- **Evidência:** `[PENDENTE — cronologia, timeout, respostas e queries]`
- **Console:** `[PENDENTE — timestamps client/server/SQL]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

### RTB-OVR-01 — Overview/extrato falha depois do sucesso

- **ID:** `RTB-OVR-01`
- **Pré-condição:** fault injector autorizado que faça somente o refresh complementar falhar após o core retornar sucesso; não alterar o commit.
- **Passos:** executar uma operação; negar o overview/extrato posterior; capturar resposta e depois restaurar/refrescar normalmente.
- **Resultado esperado:** `ok = true`, `confirmed = true`, correlationId presente e `data.refreshError`; saldo/linha idempotente confirmados; refresh posterior mostra o saldo correto.
- **Evidência:** `[PENDENTE — resposta completa redigida, SQL e tela após recuperação]`
- **Console:** `[PENDENTE]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

## Concorrência, desconexão e restart

### RTB-CON-01 — Dois callbacks concorrentes com a mesma chave

- **ID:** `RTB-CON-01`
- **Pré-condição:** harness autorizado dispara dois callbacks simultâneos idênticos.
- **Passos:** enviar os dois sem aguardar; recolher ambas as respostas; conferir Q-B-02/Q-B-03/Q-B-04/Q-B-06.
- **Resultado esperado:** uma única movimentação e linha; uma resposta pode ser `operation_busy`, mas retry recupera o resultado; nenhuma duplicidade/negativo.
- **Evidência:** `[PENDENTE — timestamps, respostas e queries]`
- **Console:** `[PENDENTE]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

### RTB-CON-02 — Operações concorrentes com chaves diferentes

- **ID:** `RTB-CON-02`
- **Pré-condição:** A com saldo preparado; duas intenções válidas diferentes (saque+transferência ou depósito+transferência).
- **Passos:** disparar simultaneamente; aguardar/repetir somente as que retornarem busy/rate limit com suas próprias chaves; conferir invariantes.
- **Resultado esperado:** locks serializam commits; nenhuma perda de atualização ou saldo negativo; cada operação confirmada possui chave/correlationId própria; operação negada não cria linha.
- **Evidência:** `[PENDENTE]`
- **Console:** `[PENDENTE — logs de lock/account_busy]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

### RTB-DISC-01 — Disconnect e reconnect durante operação

- **ID:** `RTB-DISC-01`
- **Pré-condição:** chave conhecida; operação pronta; capacidade de desconectar A imediatamente após envio.
- **Passos:** enviar e desconectar antes da resposta; registrar se houve commit; reconectar o mesmo personagem, abrir nova sessão e reenviar a mesma intenção/chave.
- **Resultado esperado:** estado é binário/reconciliável: ou nada foi persistido e retry executa uma vez, ou saldo+linha foram confirmados e retry recupera; nunca saldo duplicado ou linha sem saldo.
- **Evidência:** `[PENDENTE — cronologia, Q-B-02/Q-B-03 antes/depois e resposta pós-reconnect]`
- **Console:** `[PENDENTE]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

### RTB-RST-01 — Restart do `mz_bank`

- **ID:** `RTB-RST-01`
- **Pré-condição:** operação enviada com chave preservada; permissão de restart em staging.
- **Passos:** reiniciar `mz_bank` após o commit e antes de usar a resposta; reabrir sessão; reenviar mesma intenção/chave.
- **Resultado esperado:** sessão antiga inválida, mas resultado permanece no core; nova sessão recupera mesma correlationId sem nova movimentação.
- **Evidência:** `[PENDENTE]`
- **Console:** `[PENDENTE — stop/start e readiness]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

### RTB-RST-02 — Restart do `mz_core` durante operação

- **ID:** `RTB-RST-02`
- **Pré-condição:** snapshot; operador autorizado; chave conhecida; `mz_bank` parado/reiniciado conforme dependência depois do core.
- **Passos:** reiniciar o core em ponto controlado durante a operação; aguardar prepare/readiness; conferir SQL; reconectar/reabrir e reenviar a mesma chave.
- **Resultado esperado:** transação SQL está inteira ou revertida; se inteira, saldo e linha existem juntos e replay recupera; se revertida, ambos ausentes e retry executa uma vez; cache recarrega do SQL.
- **Evidência:** `[PENDENTE — timestamps, prepare, queries e resposta]`
- **Console:** `[PENDENTE]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

### RTB-SQL-01 — Falha SQL durante persistência

- **ID:** `RTB-SQL-01`
- **Pré-condição:** fault injector SQL autorizado que force falha em um statement da transação, sem corromper schema/dados.
- **Passos:** registrar saldos; provocar falha no insert idempotente ou em um update; enviar operação; restaurar DB; conferir Q-B-02/Q-B-03/Q-B-06 e retry com a mesma chave.
- **Resultado esperado:** resposta `database_error`/falha controlada; transação reverte tudo; cache não muda; sem linha/ledger parcial; após restauração, retry pode confirmar uma única vez.
- **Evidência:** `[PENDENTE — método de falha, rollback, queries e restauração]`
- **Console:** `[PENDENTE — erro SQL completo sem segredo]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

## Cache, persistência, ledger e ausência de paralelo

### RTB-CACHE-01 — Cache versus persistência após reconnect

- **ID:** `RTB-CACHE-01`
- **Pré-condição:** uma operação confirmada; saldos e correlationId registrados.
- **Passos:** comparar NUI com Q-B-02; desconectar/reconectar; abrir banco e comparar novamente; reiniciar somente `mz_bank` e repetir.
- **Resultado esperado:** mesmos saldos no SQL e NUI antes/depois; nenhuma reconstrução a partir de idempotência ou ledger; INV-B-06 atendido.
- **Evidência:** `[PENDENTE — screenshots e Q-B-02 em cada etapa]`
- **Console:** `[PENDENTE]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

### RTB-ECON-01 — `mz_economy` indisponível

- **ID:** `RTB-ECON-01`
- **Pré-condição:** parar somente `mz_economy` em staging; core e banco prontos; snapshot; valor/chave válidos.
- **Passos:** executar depósito, saque ou transferência; conferir resposta, Q-B-02/Q-B-03 e ausência em Q-B-06; iniciar economy; reenviar mesma chave e abrir extrato.
- **Resultado esperado:** saldo e idempotência confirmados mesmo sem economy; resposta não vira falha por extrato; replay não movimenta novamente e não fabrica ledger atrasado; ausência do evento fica registrada como limitação desta fase sem outbox.
- **Evidência:** `[PENDENTE — estados dos resources, resposta e queries antes/depois]`
- **Console:** `[PENDENTE — log de ledger ignorado/indisponível]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

### RTB-LEDGER-01 — Ledger e correlationId

- **ID:** `RTB-LEDGER-01`
- **Pré-condição:** `mz_economy` pronto; uma operação de cada tipo confirmada com keys distintas.
- **Passos:** capturar correlationId das respostas; executar Q-B-03/Q-B-06/Q-B-07 para cada uma; repetir uma chave e consultar novamente.
- **Resultado esperado:** igualdade definida em INV-B-05; duas entradas por operação; direção/conta/saldo antes/depois coerentes; replay não aumenta contagem; `transaction_id` pode diferir entre as pontas, mas `external_ref` é comum.
- **Evidência:** `[PENDENTE — respostas e resultados SQL redigidos]`
- **Console:** `[PENDENTE]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

### RTB-NOPAR-01 — Nenhum saldo paralelo

- **ID:** `RTB-NOPAR-01`
- **Pré-condição:** operações confirmadas; presença/ausência de tabelas legadas registrada por Q-B-08.
- **Passos:** executar Q-B-02/Q-B-05/Q-B-08; comparar contagem exata autorizada das tabelas legadas antes/depois; buscar nos logs qualquer escrita fora do core.
- **Resultado esperado:** saldo somente em `mz_player_accounts`/cache oficial; result_json sem snapshots; nenhuma escrita operacional em tabelas legadas; ledger não é usado como saldo.
- **Evidência:** `[PENDENTE — queries e busca de logs]`
- **Console:** `[PENDENTE]`
- **Resultado real:** `[NÃO EXECUTADO — PASSOU/FALHOU/BLOQUEADO]`

## Encerramento da rodada

- **Todos os casos preenchidos:** `[NÃO]`
- **Invariantes conferidos:** `[PENDENTE]`
- **Falhas encontradas:** `[PENDENTE]`
- **Testes que precisam repetição:** `[PENDENTE]`
- **Configuração de taxa/limites restaurada:** `[PENDENTE]`
- **Resources restaurados e prontos:** `[PENDENTE]`
- **Backup/snapshot preservado:** `[PENDENTE]`
- **Decisão runtime do Lote B:** `[NÃO APROVADO — checklist não executado]`
- **Fase 0 `[S]`:** `[NÃO MARCADA]`
