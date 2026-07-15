# MZ Bank — Guia de execução da Fase 1 em staging

Data de preparação: 2026-07-15  
Pré-requisito confirmado: Fase 0 `[S]`  
Estado: **GUIA PREPARADO; TESTES NÃO EXECUTADOS**

Este documento orienta o preenchimento de `mz_bank/RUNTIME_REPORT_PHASE_1.md`. Ele não concede aprovação runtime, não executa migrations manualmente e não implementa funcionalidades de fases posteriores.

## 1. Regras de segurança da rodada

1. Execute somente em staging isolado, com backup restaurável e personagens descartáveis.
2. Não use produção para falha SQL, restart durante operação, payload adulterado ou taxa experimental.
3. Mantenha console do servidor, F8, captura visual e acesso SQL somente leitura disponíveis durante toda a rodada.
4. Registre pacote/hash, versões, configuração e migrations antes do primeiro caso.
5. Use uma chave de idempotência nova por intenção; reutilize a mesma chave apenas nos casos de replay.
6. Não publique tokens, chaves completas, `citizenid`, license ou `card_uid`.
7. Não altere `mz_bank` durante uma rodada. Correção exige encerrar a rodada, registrar bug, implantar novo pacote e repetir casos afetados.
8. Um teste `BLOQUEADO` não passa. Um resultado visual sem queries e console não prova invariantes financeiras.
9. Os SQLs deste guia são de leitura. Qualquer preparação de cartão/inventário deve usar ferramenta administrativa real e autorizada, com comando registrado no relatório.
10. Não crie outbox, conta pública, transferência offline ou saldo paralelo para facilitar os testes.

## 2. Pré-condições comuns

- Dois jogadores, A e B, com personagens carregados e contas oficiais em `mz_player_accounts`.
- A e B com saldos descartáveis suficientes para os valores planejados.
- Um cartão próprio ativo de A, um cartão de B, um cartão bloqueado e um revogado.
- Um ATM do catálogo e uma agência de `Config.Branches` conhecidos no mapa implantado.
- Snapshot do banco anterior à rodada.
- Harness temporário autorizado apenas para chamar os callbacks/exports reais ou controlar entrega de resposta.
- Relógios do host, banco e servidor sincronizados para correlacionar evidências.
- `Config.DailyTransactionLimit = false` e `Config.TransferFeePercent = 0`, salvo cenário opcional explicitamente isolado.

## 3. Comandos Cfx autorizados

### 3.1 Start controlado na ordem oficial

Executar no console de staging. Paradas prévias devem respeitar o plano do operador e não ser usadas se houver outra rodada ativa.

```cfg
stop mz_bank
stop mz_inventory
stop mz_economy
stop mz_core
ensure oxmysql
ensure ox_lib
ensure mz_core
ensure mz_economy
ensure mz_inventory
ensure mz_bank
```

### 3.2 Falhas e recuperação de resources

O bloco abaixo é um catálogo; execute somente o comando ou a sequência indicada pelo caso, nunca todas as linhas como uma única rotina.

```cfg
stop mz_economy
start mz_economy
restart mz_bank
restart mz_core
restart mz_economy
restart mz_inventory
ensure mz_economy
ensure mz_inventory
ensure mz_bank
```

Depois de `restart mz_core`, reinicie `mz_economy`, `mz_inventory` e `mz_bank` nessa ordem; apenas `ensure` não reinicializa um resource que continuou marcado como iniciado. Não presuma recuperação do cache sem reconectar e conferir `Q-ACC-01`.

### 3.3 Readiness

Não existe comando de console próprio no resource. Use um harness server-side temporário autorizado para chamar o export real:

```lua
local state = exports['mz_bank']:GetReadiness()
```

Registre o DTO redigido. Não adicione esse harness ao resource avaliado.

## 4. Fault injection permitido

| ID | Objetivo | Mecanismo autorizado | Restauração obrigatória |
|---|---|---|---|
| FI-01 | Ledger/extrato indisponível | `stop mz_economy` | `start mz_economy`; conferir readiness/extrato |
| FI-02 | Restart do banco | `restart mz_bank` | aguardar schema ready; abrir sessão nova |
| FI-03 | Restart do core | `restart mz_core` | garantir dependentes na ordem; reconnect |
| FI-04 | Disconnect | saída normal/forçada de A ou B em staging | reconnect e recarga oficial do personagem |
| FI-05 | Token/payload adulterado | harness client temporário chamando apenas os seis callbacks reais | remover harness após captura |
| FI-06 | Timeout após commit | proxy/harness entrega a chamada ao servidor e suprime somente a resposta ao client | remover regra e reenviar mesma chave |
| FI-07 | Falha de overview após commit | parar `mz_economy` para degradar extrato; para falha total de overview, harness deve falhar somente o refresh posterior sem impedir o commit | restaurar mecanismo e validar nova consulta |
| FI-08 | Concorrência | duas corrotinas/clients enviam callbacks reais na mesma janela | aguardar ambas e reconciliar SQL/cache |
| FI-09 | Falha SQL transacional | mecanismo de DBA/proxy autorizado que faça a transação real retornar erro antes do commit | restaurar banco e confirmar saúde antes de repetir |
| FI-10 | Falha de entrega de item | ferramenta real de staging que provoque inventário cheio/limite sem alterar o banco avaliado | restaurar inventário descartável |

Não há comando de fault injection SQL implementado no repositório. O operador deve registrar no relatório o mecanismo externo, comando exato, janela e restauração. Sem mecanismo seguro, marque o caso `BLOQUEADO`.

## 5. Catálogo de queries de conferência

Substitua placeholders somente no console SQL seguro. Redija identificadores nas evidências públicas.

### Q-MIG-01 — Versão das migrations

```sql
SELECT version, name, applied_at
FROM mz_bank_schema_migrations
ORDER BY version;
```

Esperado: exatamente versões `1/mz_bank_cards` e `2/mz_bank_legacy_reports`.

### Q-SCHEMA-01 — Tabelas e engine

```sql
SELECT table_name, engine
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name IN (
    'mz_bank_schema_migrations', 'mz_bank_cards', 'mz_bank_legacy_reports',
    'mz_player_accounts', 'mz_account_idempotency', 'mz_economy_transactions'
  )
ORDER BY table_name;
```

Esperado: tabelas existentes e InnoDB. Use `SHOW COLUMNS`/`SHOW INDEX` quando o caso exigir evidência detalhada.

### Q-ACC-01 — Saldos oficiais

```sql
SELECT citizenid, wallet, bank, dirty, updated_at
FROM mz_player_accounts
WHERE citizenid IN ('<CID_A>', '<CID_B>');
```

### Q-CARD-01 — Credenciais de cartão

```sql
SELECT card_uid, citizenid, last4, status, issued_at, updated_at, blocked_at
FROM mz_bank_cards
WHERE citizenid IN ('<CID_A>', '<CID_B>')
ORDER BY citizenid, issued_at, id;
```

### Q-ITEM-01 — Item físico

```sql
SELECT owner_type, owner_id, inventory_type, slot, item, amount,
       metadata, instance_uid, updated_at
FROM mz_inventory_items
WHERE owner_type = 'player'
  AND owner_id IN ('<CID_A>', '<CID_B>')
  AND item = 'bank_card'
ORDER BY owner_id, slot;
```

### Q-IDEM-01 — Resultado idempotente por chave

```sql
SELECT source_resource, actor_citizenid, idempotency_key, operation,
       request_fingerprint, correlation_id, result_json, created_at
FROM mz_account_idempotency
WHERE source_resource = 'mz_bank'
  AND actor_citizenid = '<CID_A>'
  AND idempotency_key = '<KEY>';
```

### Q-IDEM-02 — Duplicidades proibidas

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

Esperado: zero linhas.

### Q-IDEM-03 — Ausência de snapshot de saldo

```sql
SELECT correlation_id,
       result_json LIKE '%"balances"%' AS has_balances,
       result_json LIKE '%"wallet"%' AS has_wallet,
       result_json LIKE '%"bank"%' AS has_bank
FROM mz_account_idempotency
WHERE correlation_id = '<CORRELATION_ID>';
```

Esperado: os três indicadores iguais a zero.

### Q-LEDGER-01 — Ledger pela referência oficial

```sql
SELECT transaction_id, citizenid, account, amount, balance_before,
       balance_after, direction, category, reason, source_resource,
       source_type, related_citizenid, external_ref, created_at
FROM mz_economy_transactions
WHERE external_ref = '<CORRELATION_ID>'
ORDER BY id;
```

Com `mz_economy` disponível, esperado: duas linhas por operação atual compartilhando `external_ref`. Durante degradação, ausência de ledger é limitação conhecida desta fase e não reverte o saldo oficial.

### Q-LEDGER-02 — Delta

```sql
SELECT external_ref,
       SUM(CASE WHEN direction = 'in' THEN amount ELSE -amount END) AS net_delta,
       COUNT(*) AS entries
FROM mz_economy_transactions
WHERE external_ref = '<CORRELATION_ID>'
GROUP BY external_ref;
```

Esperado: `net_delta = 0` com taxa zero; com taxa, `net_delta = -taxa`; `entries = 2`.

### Q-LEGACY-01 — Legado sem escrita

```sql
SELECT table_name, table_rows
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name IN ('bank_accounts', 'bank_transactions');
```

Se existirem, capture contagem exata autorizada antes/depois. O fluxo normal não deve modificá-las.

### Q-NOPAR-01 — Ausência de tabela de saldo paralela

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name IN ('mz_bank_accounts', 'mz_financial_outbox');
```

Esperado nesta fase: zero linhas.

## 6. Ordem recomendada da execução

1. Preencher ambiente, versões, snapshot e baseline.
2. Executar `RT-INIT` antes de criar operações financeiras.
3. Executar `RT-SESSION` e `RT-CARD` com saldos registrados, mas sem depender de falhas SQL.
4. Restaurar cartões/itens e executar `RT-CASH`.
5. Restaurar saldos conhecidos e executar `RT-TRANSFER`.
6. Executar `RT-RETRY` por último, pois envolve timeout, restart e resposta ambígua.
7. Repetir `Q-ACC-01`, `Q-IDEM-02`, `Q-LEGACY-01` e `Q-NOPAR-01` no encerramento.
8. Registrar bugs e não corrigir durante a mesma rodada.

## 7. Procedimentos RT-INIT

### RT-INIT-01 — Start, readiness e contratos

- Pré-condição: snapshot pronto; resources parados conforme plano.
- Passos: executar 3.1; capturar console; consultar `GetReadiness`; abrir agência e ATM apenas até confirmar que callbacks existem.
- Queries: `Q-MIG-01`, `Q-SCHEMA-01`.
- Esperado: ordem oficial, schema v2, `ready = true`, nenhum export/callback ausente ou stack trace.
- Evidência: comandos/timestamps, DTO de readiness, console e queries.

### RT-INIT-02 — Migration idempotente

- Pré-condição: RT-INIT-01 passou; snapshot das tabelas de banco.
- Passos: registrar `Q-MIG-01`; `restart mz_bank`; aguardar ready; repetir queries e contar cartões/relatórios.
- Esperado: mesmas duas versões, sem perda/duplicação de dados, sem DDL destrutivo.

### RT-INIT-03 — Dependência rígida

- Pré-condição: escolher uma dependência rígida por vez; sem operação em andamento.
- Passos: parar a dependência autorizada; tentar readiness/abertura; restaurar na ordem; reiniciar banco quando o console solicitar.
- Esperado: fail-closed, `dependency_stopped`/`dependency_missing`, nenhuma sessão nova.
- Não use esse caso para `mz_economy`, que pertence a RT-INIT-05.

### RT-INIT-04 — Item e superfícies

- Pré-condição: core pronto.
- Passos: confirmar definição `bank_card`, item real via `Q-ITEM-01`, abertura e chamadas normais.
- Esperado: item disponível; seis callbacks client-facing respondem; exports consumidos não geram erro.

### RT-INIT-05 — Economia degradável

- Pré-condição: saldos conhecidos, sessão válida e chave nova.
- Passos: `stop mz_economy`; consultar readiness; realizar depósito pequeno e capturar confirmação; abrir extrato; consultar SQL; `start mz_economy`; consultar readiness/extrato novamente.
- Esperado: `ready = true`, `degraded = true` enquanto parado; operação confirma no core; extrato indisponível; retorno restaura consulta sem restart do banco.
- Observação: o ledger da operação feita offline pode não ser recriado nesta fase; isso não pode alterar o saldo.

### RT-INIT-06, RT-INIT-07 e RT-INIT-08 — Restarts e ausência de paralelo

- Banco: capturar saldos/token, `restart mz_bank`, confirmar saldos e negar token antigo.
- Core: capturar saldos, `restart mz_core`, restaurar dependentes, reconnect e comparar NUI/`Q-ACC-01`.
- Paralelo/legado: executar `Q-NOPAR-01` e `Q-LEGACY-01` antes/depois.
- Esperado: persistência preservada e nenhuma escrita/tabela indevida.

## 8. Procedimentos RT-SESSION

### RT-SESSION-01 e RT-SESSION-02 — Pontos físicos

- Pré-condição: coordenadas reais do mapa registradas.
- Passos: abrir agência/ATM válidos; depois usar harness FI-05 com coordenada falsa, ponto distante e ATM fora do catálogo.
- Esperado: válidos abrem; falsos retornam `too_far` ou `atm_invalid`; nenhum token útil nos casos negados.

### RT-SESSION-03 — Canal e payload adulterados

- Passos: chamar `openSession` com `phone`, coordenada arbitrária e campos extras; depois enviar `channel`, `source`, `citizenid` e `recipientType` em callbacks posteriores.
- Esperado: phone negado; extras descartados; sessão/token determinam canal e identidade.

### RT-SESSION-04 — Tokens

- Passos: testar sem token, token aleatório, token de A usado por B e token após 120 s; testar também token antigo após nova sessão.
- Esperado: `invalid_session`/`session_expired`; nenhuma conta ou saldo exposto.

### RT-SESSION-05 e RT-SESSION-06 — Estado físico/identidade

- Passos: afastar além do limite, morrer, entrar em veículo, trocar personagem e desconectar; tentar callback com token antigo após cada ação.
- Esperado: NUI fecha, foco/tarefas liberados, sessão não revive, conta anterior inacessível.

### RT-SESSION-07 e RT-SESSION-08 — UX preservada

- Passos: gravar abertura ATM, alinhamento, cenário, autenticação, recusa, retirada, fechamento e restart.
- Esperado: amarelo ao aguardar, verde autenticado, vermelho em recusa/retirada; `PROP_HUMAN_ATM` termina sem ped preso.

## 9. Procedimentos RT-CARD

### RT-CARD-01, RT-CARD-02 e RT-CARD-03 — Autenticação

- Preparar cada estado com ferramenta real e registrar `Q-CARD-01`/`Q-ITEM-01`.
- Testar ATM sem cartão, próprio ativo, outro titular, bloqueado e revogado.
- Esperado: somente próprio ativo autentica; demais retornam códigos estáveis e não expõem conta.

### RT-CARD-04 — Bloqueio durante sessão

- Autenticar cartão ativo, bloquear pela superfície server-side autorizada de agência e tentar refresh/operação com token anterior.
- Esperado: próxima chamada negada, sessão invalidada, slot vermelho/fechamento, saldo intacto.

### RT-CARD-05 — Substituição

- Pré-condição: agência válida e inventário com espaço.
- Passos: autenticar cartão anterior, pedir segunda via pelo export real autorizado, conferir item/credencial e tentar token/cartão anterior.
- Esperado: novo item ativo, anterior revogado, sessão antiga inválida, sem saldo paralelo.

### RT-CARD-06 — Remoção do item

- Remover o item autenticado com ferramenta administrativa real, preservando a linha da credencial; tentar nova ação.
- Esperado: `card_not_found`/`card_invalid`, sessão eliminada e nenhuma movimentação.

### RT-CARD-07 — Emissão e falha de inventário

- Testar primeira visita à agência sem cartão; depois repetir em personagem descartável com FI-10.
- Esperado: sucesso cria item e linha coerentes; falha de entrega revoga a credencial nova e preserva o cartão anterior quando aplicável.

## 10. Procedimentos RT-CASH

### RT-CASH-01 e RT-CASH-02 — Fluxos válidos

- Registrar `Q-ACC-01`; depositar `100` com chave nova; capturar resposta e queries.
- Restaurar baseline; sacar `100` com outra chave; repetir conferência.
- Esperado: deltas opostos entre wallet/bank, total preservado, idempotência e ledger com mesma referência.

### RT-CASH-03 — Limites de saldo

- Testar movimentar exatamente o saldo permitido dentro do teto e depois valor maior que o disponível.
- Esperado: primeiro segue fluxo; insuficiente não muda cache/SQL/idempotência/ledger.

### RT-CASH-04 e RT-CASH-05 — Contrato de valores

- Via FI-05, enviar `1.5`, `0`, `-1`, texto, texto numérico, `null`, NaN e infinito quando o harness suportar.
- Em ATM e agência, testar `999999`, `1000000` e `1000001` para saque/depósito.
- Esperado: somente inteiro positivo dentro do limite segue; não há teste diário porque a função não existe.

### RT-CASH-06 — Duplo clique/concorrência

- Enviar mesma intenção/chave simultaneamente e depois chaves distintas disputando saldo.
- Esperado: mesma chave movimenta uma vez; chaves distintas respeitam locks/saldo e nunca produzem valor negativo.

### RT-CASH-07 — Persistência e ledger

- Após operação confirmada, comparar NUI, `Q-ACC-01`, `Q-IDEM-01` e `Q-LEDGER-01`; reconnect e repetir.
- Esperado: cache/persistência convergem; referência única; sem snapshot de saldo no resultado idempotente.

## 11. Procedimentos RT-TRANSFER

### RT-TRANSFER-01 — Transferência válida

- Registrar A/B; transferir `100` de A para B com chave nova; capturar resposta e queries.
- Esperado: A `-100`, B `+100`, taxa zero, mesma `correlationId` no response/idempotência/ledger.

### RT-TRANSFER-02 — Destino inválido

- Testar server ID inexistente, offline e o próprio source.
- Esperado: `recipient_invalid`, `recipient_offline` ou `self_transfer`; nenhuma linha financeira nova.

### RT-TRANSFER-03 — Taxa

- Cenário obrigatório: taxa `0`, transferir `101`.
- Cenário opcional somente em staging: alterar configuração para `1.5`, reiniciar na ordem e transferir `101`; depois restaurar `0`.
- Esperado opcional: `floor(1.515) = 1`; A debita `102`, B recebe `101`.

### RT-TRANSFER-04 e RT-TRANSFER-05 — Concorrência

- Usar FI-08 para transferências A→B e B→A simultâneas; depois várias chaves de A disputando o mesmo saldo.
- Esperado: sem deadlock, commit atômico, nenhuma ponta negativa e somente operações cobertas confirmadas.

### RT-TRANSFER-06 — Disconnect

- Desconectar remetente ou destinatário em janela controlada antes/depois do commit; registrar timestamps.
- Esperado: duas pontas persistidas ou nenhuma; reconnect reconcilia cache; jamais apenas uma ponta.

### RT-TRANSFER-07 — Falha SQL

- Usar FI-09 somente com autorização e snapshot; capturar saldos/cache antes; provocar erro na transação; restaurar banco.
- Esperado: remetente, destinatário e idempotência revertem; cache não muda; replay após restauração pode executar uma única vez com chave ainda não confirmada.

## 12. Procedimentos RT-RETRY

### RT-RETRY-01 — Chaves inválidas

- Enviar chave ausente, curta, longa e com caractere proibido.
- Esperado: `idempotency_required`/`invalid_idempotency_key`; nenhuma chamada financeira persistida.

### RT-RETRY-02 — Replay igual

- Confirmar operação, guardar resposta e reenviar mesma chave/payload após cooldown e nova sessão quando necessário.
- Esperado: mesma `correlationId`, `replayed = true`, uma linha idempotente e um único delta.

### RT-RETRY-03 — Conflito

- Reenviar a chave confirmada mudando valor, operação ou destinatário.
- Esperado: `idempotency_conflict`; operação original permanece única.

### RT-RETRY-04 — Timeout após commit

- Usar FI-06; comprovar por SQL que o commit ocorreu sem resposta; remover bloqueio e reenviar mesma chave.
- Esperado: resultado anterior recuperado, sem segundo movimento.

### RT-RETRY-05 — Refresh posterior falha

- Com operação válida, degradar apenas extrato usando FI-01 ou o mecanismo controlado de FI-07.
- Esperado: `ok = true`, `confirmed = true`, `correlationId` preservada e `refreshError` quando o overview completo não puder ser obtido.

### RT-RETRY-06 — Restart na resposta ambígua

- Confirmar commit, reiniciar `mz_bank` antes de consumir a resposta, abrir sessão nova e reenviar mesma chave/payload.
- Esperado: resultado persistido recuperado; restart não duplica saldo.

## 13. Critério de conclusão da rodada

A rodada só pode seguir para decisão quando:

- todos os 43 casos possuem status e evidência;
- nenhum caso obrigatório está `BLOQUEADO`;
- todas as invariantes foram conferidas;
- bugs foram corrigidos em etapa própria e testes afetados repetidos;
- queries finais não mostram duplicidade, saldo paralelo ou escrita no legado;
- o relatório preserva resultados reais, inclusive falhas;
- a decisão final é emitida pelo prompt específico posterior, nunca por este guia.
