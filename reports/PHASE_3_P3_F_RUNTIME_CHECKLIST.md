# Fase 3 — Checklist runtime do P3-F

Data de criação: 2026-07-19  
Ambiente esperado: MySQL/FiveM staging restaurável  
Estado geral: **APROVADO EM RUNTIME — 16/16 CASOS APROVADOS**

## 1. Regra de execução

Este checklist valida somente os produtores P3-F. Não executar em produção, não editar saldo por SQL
para simular sucesso e não aprovar por inferência. Registrar resultado real, console, queries,
executor e data. Estados: `NÃO EXECUTADO`, `APROVADO`, `FALHOU`, `BLOQUEADO`, `NÃO APLICÁVEL`.

Manter ligados no staging os gates já aprovados de writes, consumer e dispatcher. Todos os runners
antigos devem permanecer desligados.

Para P3F-04, P3F-05 e a parte interna de P3F-06:

```text
set mz_core_p3f_runtime_runner 1
restart mz_core
mz_core_p3f_runtime_test
```

Esperado: seis `PASS`, `failed=0`, `sql_writes=0` e `real_balances=false`. Depois:

```text
set mz_core_p3f_runtime_runner 0
restart mz_core
```

O comando deve deixar de existir. O runner não substitui os casos reais de SQL/outbox abaixo.

### Execução real consolidada e controlada

Para reduzir repetição manual, o runner também oferece um teste real único. Ele somente é registrado
quando o runner está ligado e exige uma segunda flag de escrita. É exclusivo do console, usa apenas
`bank`, limita o valor ao intervalo inteiro de `1` a `100` e restaura o saldo inicial antes de
retornar `PASS`.

```text
set mz_core_p3f_runtime_runner 1
set mz_core_p3f_runtime_real_writes 1
restart mz_core
mz_core_p3f_runtime_real <source_online> 10
```

O resultado obrigatório é `PASS P3F-REAL` com `initial` igual a `final`, quatro eventos, quatro
recibos, quatro linhas de ledger, `replay=true`, `conflict=true` e `noop_outbox=0`. O comando valida
em uma execução real `AddMoney`, `RemoveMoney`, aumento/redução/no-op de `SetMoney`, idempotência,
dispatcher, recibos e ledger. Ele não cobre organização, payroll, indisponibilidade do economy,
restart/backlog ou smoke físico.

Teardown obrigatório imediatamente depois:

```text
set mz_core_p3f_runtime_real_writes 0
set mz_core_p3f_runtime_runner 0
restart mz_core
```

Após o restart, `mz_core_p3f_runtime_real` e `mz_core_p3f_runtime_test` não devem existir.

Para P3F-10, o mesmo runner disponibiliza um comando real específico de jogador ↔ organização. Ele
exige as duas flags, console, personagem online e permissão real sobre a organização. Executa um
depósito seguido de saque do mesmo valor e só retorna `PASS` quando ambos os saldos voltam ao valor
inicial e duas outboxes `org_transfer` possuem dois recibos e quatro pernas de ledger:

```text
set mz_core_p3f_runtime_runner 1
set mz_core_p3f_runtime_real_writes 1
restart mz_core
ensure mz_economy
mz_core_p3f_runtime_org <source_online> <org> 10
```

Resultado obrigatório: `PASS P3F-ORG` com `player_initial=player_final`,
`org_initial=org_final`, `events=2`, `receipts=2` e `ledger=4`. O valor é limitado a `1..100`; não
existe evento de rede, callback NUI ou export adicional. Fazer o mesmo teardown das duas flags.

Para concluir P3F-11 e P3F-14 em uma única execução controlada:

```text
set mz_core_p3f_runtime_runner 1
set mz_core_p3f_runtime_real_writes 1
restart mz_core
ensure mz_economy
mz_core_p3f_runtime_final <source_online> police
```

O fault injection substitui temporariamente somente a chamada repository do citizen/org alvo e
retorna `database_error` antes da transação; chamadas alheias continuam usando o método real. O
teste exige zero delta de banco/organização e zero outbox nessa falha. Depois dispara 20 chamadas
concorrentes com a mesma chave, 10 com chaves distintas e uma compensação controlada. Resultado
obrigatório:

```text
PASS P3F-FINAL detail=fault_before_commit=true fault_writes=0 concurrent_calls=30
same_key=20 unique_keys=10 events=12 receipts=12 ledger=12
cache_sql_equal=true initial=<n> final=<n>
```

O saldo final deve ser idêntico ao inicial. Fazer o teardown das duas convars imediatamente depois.

### P3F-08 — fault controlado da entrega do cartão

O teste final usa o fluxo real de segunda via na agência. A falha ocorre somente na entrega do item,
depois da cobrança e criação da credencial; o código deve revogar a credencial nova e devolver a
taxa. Duas convars server-side restringem o fault ao source indicado:

```text
set mz_bank_p3f_runtime_runner 1
set mz_bank_p3f_fail_card_delivery_source <source_online>
restart mz_bank
```

Abrir uma agência e solicitar segunda via. Esperado: operação recusada por inventário cheio/falha
de entrega, nenhum cartão novo utilizável e saldo bancário final igual ao inicial. Taxa e refund
devem ter correlações distintas, valor `250`, o mesmo `external_ref`, duas outboxes processadas, dois
recibos e duas pernas de ledger. Teardown imediato:

```text
set mz_bank_p3f_fail_card_delivery_source 0
set mz_bank_p3f_runtime_runner 0
restart mz_bank
```

O fault não registra evento, callback ou export e não aceita input do client; com qualquer convar
desligada, o bridge executa somente o contrato normal do inventário.

### Resultado real do runner interno — fornecido pelo usuário

Execução manual no console do FiveM staging em 2026-07-19:

```text
PASS P3F-INT-01 detail=add=10 event=add_money
PASS P3F-INT-02 detail=remove=3 event=remove_money
PASS P3F-INT-03 detail=set=120 noop_outbox=0
PASS P3F-INT-04 detail=invalid_vectors=3 writes=0
PASS P3F-INT-05 detail=replay=true conflict=true duplicate=false
PASS P3F-INT-06 detail=outboxes=4 one_leg=true
SUMMARY executed=6 passed=6 failed=0 sql_writes=0 real_balances=false
```

Decisão da subsuíte: **APROVADA**. Esta evidência confirma os contratos internos em memória, mas
não comprova commit MySQL, dispatcher, receipt/ledger, organização, payroll ou smoke físico.

## 2. Snapshots comuns

Antes/depois de cada mutação, consultar os personagens e organização usados:

```sql
SELECT citizenid, wallet, bank, dirty, updated_at
FROM mz_player_accounts
WHERE citizenid IN ('<CITIZEN_A>', '<CITIZEN_B>');

SELECT oa.org_id, o.code, oa.balance, oa.updated_at
FROM mz_org_accounts oa
JOIN mz_orgs o ON o.id = oa.org_id
WHERE o.code = '<ORG_TESTE>';

SELECT id, correlation_id, idempotency_key, event_type, account, amount, status,
       attempts, created_at, processed_at, last_error
FROM mz_financial_outbox
ORDER BY id DESC LIMIT 30;

SELECT transaction_id, citizenid, account, direction, amount, balance_before,
       balance_after, category, related_org_code, external_ref, created_at
FROM mz_economy_transactions
WHERE transaction_id LIKE 'mzoutbox:%'
ORDER BY id DESC LIMIT 40;
```

Invariantes: delta exato, uma outbox por operação nova, uma linha por perna, recibo correspondente,
cache igual ao SQL, nenhum saldo escrito pelo consumer e nenhuma linha duplicada.

## 3. Casos

| ID | Teste | Passos essenciais | Resultado esperado | Status |
|---|---|---|---|---|
| P3F-01 | startup e readiness | reiniciar `mz_core`, `mz_economy` e dependentes na ordem real | resources ready; backlog processa; sem erro de evento novo | APROVADO |
| P3F-02 | `AddMoney` | usar `mz_money_add <source> bank 10 p3f_add` | banco `+10`; `add_money`; uma perna `in`; uma outbox/recibo/ledger | APROVADO |
| P3F-03 | `RemoveMoney`/taxa | executar compra/serviço controlado de valor inteiro | saldo `-valor`; `remove_money`; uma perna `out`; sem ledger duplicado | APROVADO |
| P3F-04 | `SetMoney` | runner/console interno controlado deve testar aumento, redução e mesmo valor | delta correto; `set_money` somente quando delta ≠ 0; no-op sem outbox | APROVADO |
| P3F-05 | valores inválidos | decimal, zero onde proibido, negativo, texto, NaN/infinito via runner | todos negados antes do SQL; zero saldo/outbox/ledger | APROVADO |
| P3F-06 | idempotência pessoal | mesma chave+payload duas vezes; depois mesma chave com payload diferente | replay não movimenta; conflito negado; correlationId original preservado | APROVADO |
| P3F-07 | economy offline | parar `mz_economy`, executar uma adição/remoção e iniciar novamente | saldo+pending confirmados; depois um recibo/ledger; sem duplicidade | APROVADO |
| P3F-08 | taxa e compensação | provocar falha controlada após taxa em fluxo que já possui refund | taxa e refund têm correlações distintas, mesmo `external_ref`; delta líquido esperado | APROVADO |
| P3F-09 | ajuste organizacional | `mzorg_deposit <org> 10` e `mzorg_withdraw <org> 10` | `org_account_adjustment`; uma perna; saldo/ledger exatos | APROVADO |
| P3F-10 | jogador ↔ organização | depósito e saque reais pela integração autorizada | banco+org mudam juntos; `org_transfer` com duas pernas; sem rollback separado | APROVADO |
| P3F-11 | falha SQL org | fault injection antes do commit de P3F-10 | nenhuma das duas pontas muda; nenhuma outbox/ledger parcial | APROVADO |
| P3F-12 | payroll | `mzpay_citizen <citizenid>` com org financiada | org `-salário`, banco `+salário`, `payroll_payment`, duas pernas | APROVADO |
| P3F-13 | replay payroll | repetir P3F-12 na mesma janela | resultado replay; zero novo saldo/outbox/ledger | APROVADO |
| P3F-14 | concorrência | 20 chamadas controladas com chaves iguais/diferentes | iguais uma vez; diferentes serializadas; cache=SQL; sem saldo negativo | APROVADO |
| P3F-15 | restart/backlog | criar pending, reiniciar core/economy/servidor e aguardar | evento recuperado, recibo único, nenhuma nova movimentação | APROVADO |
| P3F-16 | smoke físico | ATM/agência: abrir, depósito, saque, transferência, fechar | NUI/animação/slot e fluxos anteriores preservados | APROVADO |

## 4. Queries de unicidade e reconciliação

```sql
SELECT correlation_id, COUNT(*) total
FROM mz_financial_outbox
GROUP BY correlation_id HAVING COUNT(*) > 1;

SELECT transaction_id, COUNT(*) total
FROM mz_economy_transactions
WHERE transaction_id LIKE 'mzoutbox:%'
GROUP BY transaction_id HAVING COUNT(*) > 1;

SELECT o.id, o.event_type, o.status, r.entry_count,
       COUNT(t.id) AS ledger_entries
FROM mz_financial_outbox o
LEFT JOIN mz_economy_outbox_receipts r ON r.outbox_id = o.id
LEFT JOIN mz_economy_transactions t
  ON t.transaction_id LIKE CONCAT('mzoutbox:', o.id, ':%')
WHERE o.event_type IN (
  'add_money', 'remove_money', 'set_money',
  'org_account_adjustment', 'org_transfer', 'payroll_payment'
)
GROUP BY o.id, o.event_type, o.status, r.entry_count
ORDER BY o.id DESC;
```

Esperado para processados: `ledger_entries = entry_count`; uma perna nos eventos simples e duas em
`org_transfer`/`payroll_payment`.

## 5. Teardown

- desligar qualquer runner/fault injection temporário;
- restaurar configuração de staging;
- reiniciar resources na ordem oficial;
- executar smoke final;
- não apagar outbox, recibo ou ledger usados como evidência;
- remover somente fixtures explicitamente criadas e documentadas.

## 6. Consolidação

| Métrica | Resultado |
|---|---:|
| Casos definidos | 16 |
| Executados | 16 |
| Aprovados | 16 |
| Falhas | 0 |
| Bloqueados | 0 |
| Não executados | 0 |
| Subtestes internos executados | 6 |
| Subtestes internos aprovados | 6 |

```text
P3-F: [R] Aprovado em runtime
Runtime do P3-F: CONCLUÍDO — 16/16 aprovados; zero falhas e zero bloqueados
Fase 3: [~] Em implementação
```

P3-G pode começar após este registro. Este arquivo aprova somente o runtime do P3-F, não a Fase 3 inteira.

### Evidência runtime informada pelo usuário — P3F-02

Execução manual no console/MySQL do FiveM staging em 2026-07-19:

```text
mz_money_add 1 bank 10 p3f_add
[mz_core] mz_money_add OK: target=1 account=bank amount=10
```

O usuário confirmou também o acréscimo bancário de `10` e informou que a conferência no banco de
dados estava correta. Não foram acrescentados ao relatório valores SQL que não tenham sido
fornecidos textualmente.

Na primeira execução consolidada, o runner retornou `financial_outbox_writes_unavailable`; a
tentativa foi fail-closed e não alterou saldo. Após habilitar producer, dispatcher e consumer, uma
nova execução criou quatro outboxes e terminou com `initial=5360` e `final=5360`. Como o
`mz_economy` estava parado, as linhas 5–8 permaneceram `pending`, `attempts=0`, sem recibo ou ledger.
O `mz_core` foi reiniciado mantendo o backlog. Depois de `ensure mz_economy`, o consumer anunciou
`enabled=true consumer=true`, o dispatcher anunciou `economy=ready` e confirmou exatamente:

```text
ack id=5 type=add_money source_resource=p3f_runtime_real detail=consumer_replay=false
ack id=6 type=remove_money source_resource=p3f_runtime_real detail=consumer_replay=false
ack id=7 type=set_money source_resource=p3f_runtime_real detail=consumer_replay=false
ack id=8 type=set_money source_resource=p3f_runtime_real detail=consumer_replay=false
```

Essas evidências foram fornecidas pelo usuário após execução manual no MySQL/FiveM staging. Elas
aprovam os produtores pessoais, valores inválidos da subsuíte interna, replay/conflito, indisponibilidade
do economy e recuperação do backlog após restart. Não aprovam os casos organizacionais, payroll,
taxa/refund, concorrência real específica nem smoke físico.

### Evidência runtime informada pelo usuário — P3F-09

O usuário executou manualmente no FiveM staging:

```text
mzorg_balance police             -> 0
mzorg_deposit police 10          -> 10
mzorg_withdraw police 10         -> 0
mzorg_balance police             -> 0
```

Após iniciar novamente o `mz_economy`, o usuário confirmou que o processamento esperado das duas
outboxes `org_account_adjustment` passou corretamente. O saldo organizacional final foi igual ao
inicial; nenhuma evidência adicional não fornecida foi inferida.

### Evidência runtime informada pelo usuário — P3F-10

O usuário executou manualmente no MySQL/FiveM staging o comando consolidado
`mz_core_p3f_runtime_org` e informou o resultado como aprovado. O comando exige, para retornar
`PASS`, saldo bancário e organizacional finais iguais aos iniciais, duas outboxes `org_transfer`,
dois recibos e quatro pernas de ledger. A aprovação registra somente essa execução informada; não
antecipa payroll, fault injection, concorrência, taxa/refund ou smoke físico.

### Evidência runtime informada pelo usuário — P3F-12/P3F-13

Foi criada uma associação temporária `police/recruta`, duty ligado, com salário real de `1200`. A
organização recebeu `1200` por ajuste administrativo e `mzpay_citizen FVTXM23H` foi executado duas
vezes na mesma janela. Ambas as chamadas retornaram o contrato de pagamento; a conferência SQL
mostrou somente uma outbox:

```text
id=12 event_type=payroll_payment amount=1200 status=processed attempts=1
idempotency_key=payroll_1_991388 entry_count=2 ledger_entries=2
```

O dispatcher registrou `ack id=12 ... consumer_replay=false`. A ausência de uma segunda outbox,
recibo ou par de ledger comprova o replay idempotente da segunda chamada. A associação temporária
foi removida com sucesso depois da correção mínima do caminho console de `mzorg_remove`.

### Evidência runtime informada pelo usuário — P3F-16

O usuário informou que o smoke físico da versão atual passou integralmente no FiveM: agência e ATM,
depósito, saque, transferência, fechamento, saldos/extrato, NUI, animação, alinhamento e slot foram
confirmados como corretos. A evidência foi fornecida pelo usuário; nenhuma captura ou log adicional
foi inventado.

### Evidência runtime informada pelo usuário — P3F-11/P3F-14

O usuário executou o runner final no MySQL/FiveM staging com source `2` e organização `police`. O
resultado fornecido foi:

```text
PASS P3F-FINAL detail=fault_before_commit=true fault_writes=0 concurrent_calls=30
same_key=20 unique_keys=10 events=12 receipts=12 ledger=12
cache_sql_equal=true initial=6560 final=6560
```

O dispatcher confirmou os IDs 13–23 como `add_money` e o ID 24 como `remove_money`, todos com ACK
e `consumer_replay=false`. A falha dirigida terminou antes do commit sem saldo/outbox parcial; vinte
chamadas da mesma chave movimentaram uma vez, dez chaves distintas foram serializadas e a
compensação restaurou cache e SQL para `6560`.

### Evidência runtime informada pelo usuário — P3F-08

Em 2026-07-19, o usuário preparou o FiveM staging com `mz_economy`, `mz_inventory` e `mz_bank`
ativos, habilitou o fault server-side exclusivamente para o source `2` e executou manualmente o
fluxo real de segunda via/substituição de cartão na agência. O usuário confirmou que o resultado
observado correspondeu integralmente ao esperado: falha controlada na entrega, compensação da taxa,
saldo líquido preservado e ausência de cartão novo utilizável.

Esta aprovação registra somente a confirmação runtime fornecida pelo usuário. Nenhum log, valor SQL,
correlationId ou `external_ref` não fornecido textualmente foi acrescentado como evidência.
