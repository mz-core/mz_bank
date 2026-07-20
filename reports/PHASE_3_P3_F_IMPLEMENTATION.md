# MZ Bank — Implementação do Lote P3-F

Data: 2026-07-19  
Fase: 3 — Idempotência, outbox e auditoria  
Estado: **P3-F [S] VALIDADO ESTATICAMENTE; RUNTIME NÃO EXECUTADO**

## 1. Diagnóstico

Os produtores restantes ainda separavam a persistência do saldo do lançamento no `mz_economy`.
Também havia dois fluxos com mais de uma fonte oficial: jogador ↔ organização e organização →
jogador no payroll. Neles, updates independentes e compensações manuais permitiam estado parcial.

## 2. Escopo implementado

- `AddMoney`, `RemoveMoney` e `SetMoney` persistem saldo, idempotência opcional e outbox na mesma
  `MySQL.transaction.await`;
- valores desses três contratos agora exigem inteiro finito dentro do máximo seguro;
- replay da mesma chave não altera saldo nem cria nova outbox/linha de extrato;
- taxas e compensações que já usam esses exports passam pelo produtor atômico;
- correlação da outbox é única por mutação; o `external_ref` legado permanece no lançamento e pode
  agrupar taxa/compensação sem colidir com a unicidade da outbox;
- consumer privado aceita `add_money`, `remove_money` e `set_money` com uma perna;
- depósito e saque organizacional persistem saldo bancário, saldo da organização e outbox em uma
  única transação, removendo rollback financeiro manual;
- ajustes de saldo organizacional persistem saldo + outbox atomicamente;
- payroll persiste débito da organização, crédito bancário, idempotência e outbox na mesma transação;
- payroll usa janela derivada de `Config.Payroll.intervalMinutes` para impedir pagamento duplicado;
- consumer aceita `org_account_adjustment`, `org_transfer` e `payroll_payment` com validação própria;
- cache de jogador é alterado somente depois do commit;
- ledger best-effort permanece apenas como fallback quando a feature de outbox está desligada.

## 3. Arquivos alterados

| Arquivo | Alteração |
|---|---|
| `mz_core/server/accounts/repository.lua` | transações de uma conta, organização e jogador+organização |
| `mz_core/server/accounts/service.lua` | produtores pessoais, idempotência, envelope de uma perna e contratos internos |
| `mz_core/server/accounts/org_accounts.lua` | ajustes e transferências organizacionais atômicas |
| `mz_core/server/accounts/payroll.lua` | pagamento atômico e replay por janela |
| `mz_core/server/accounts/p3f_runtime_runner.lua` | testes internos e comandos reais consolidados para operações pessoais, org, fault e concorrência, todos com dupla flag e desligados por padrão |
| `mz_bank/server/service.lua` | taxa e refund de cartão compartilham referência comercial sem reutilizar correlationId |
| `mz_bank/bridge/server.lua` | fault de entrega P3-F restrito por runner e source, desligado por padrão |
| `mz_economy/server/outbox_consumer.lua` | validação/consumo dos seis eventos do P3-F |
| `mz_bank/BANK_ROADMAP.md` | estado estático e próximo gate |

Nenhuma migration, tabela, coluna, saldo ou ledger paralelo foi criado.

## 4. Contratos reais utilizados

- `MySQL.transaction.await` do `oxmysql`;
- `mz_player_accounts.wallet`, `bank` e `dirty` como persistência pessoal oficial;
- `mz_org_accounts.balance` como persistência organizacional já existente;
- `mz_account_idempotency` e `mz_financial_outbox` pertencentes ao `mz_core`;
- consumer privado `mz_core -> mz_economy` e recibo idempotente já aprovados no P3-C;
- `MZEconomyService.BuildTransactionPayload` e `MZEconomyRepository.consumeFinancialOutbox`;
- exports existentes `AddMoney`, `RemoveMoney`, `SetMoney` e contratos organizacionais/payroll.

Os helpers novos de envelope/lock são internos ao contexto server-side do `mz_core`. Não são exports,
eventos de rede, callbacks NUI ou comandos.

## 5. Eventos adicionados

| Evento | Pernas | Persistência atômica |
|---|---:|---|
| `add_money` | 1 `in` | saldo pessoal + idempotência opcional + outbox |
| `remove_money` | 1 `out` | saldo pessoal + idempotência opcional + outbox |
| `set_money` | 1 `adjustment` | saldo pessoal + idempotência opcional + outbox |
| `org_account_adjustment` | 1 `adjustment` | saldo organizacional + outbox |
| `org_transfer` | 2 | banco do jogador + organização + outbox |
| `payroll_payment` | 2 | organização + banco + idempotência + outbox |

Pernas organizacionais não usam `citizenid` sintético. O ledger aceita `citizenid` nulo e exige
`related_org_code`. Nenhum identificador novo alcança client/NUI.

## 6. Atomicidade e idempotência

Para produtores pessoais, uma chave é opcional para preservar os contratos atuais. Quando presente,
ela é validada e gravada na mesma transação; conflito de operação/fingerprint é negado. Sem chave,
cada chamada confirmada continua sendo uma operação nova.

No payroll a chave é server-side e formada pela organização e janela de pagamento, dentro do escopo
`mz_core + citizenid`. Repetir o tick na mesma janela recupera o resultado sem novo débito/crédito.

Depósito/saque organizacional não ganhou chave client-facing: nenhuma identidade, rota ou chave é
aceita do client nesta etapa. A operação, porém, não pode mais confirmar apenas uma das duas pontas.

## 7. Taxas e compensações

Taxa de cartão e refunds já existentes continuam sendo operações comerciais separadas. Cada perna
confirmada agora possui saldo + outbox atômicos e correlação própria, mantendo o `external_ref`
comercial no ledger. O P3-F não transformou o ciclo de cartão em uma nova saga nem mudou inventário.

## 8. Compatibilidade

- assinaturas e retornos booleanos de `AddMoney`, `RemoveMoney` e `SetMoney` foram preservados;
- exports organizacionais e payroll foram preservados;
- com outbox desligada, o ledger legado continua funcionando sem duplicar o caminho novo;
- com outbox ligada, o producer não chama `RecordTransaction` para o mesmo lançamento;
- wallet/bank/dirty e organização continuam sendo as únicas fontes de saldo;
- não houve mudança em ATM, agência, NUI, animação, slot, cartão ou phone.

## 9. Validações estáticas executadas

- `luac -p` aprovado nos cinco arquivos Lua alterados;
- busca por writes confirmou que as mutações P3-F ficam no repository transacional;
- busca confirmou fallback de ledger condicionado a `outboxPersisted ~= true`;
- busca confirmou ausência de evento de rede, NUI callback ou export novo nos contratos internos;
- consumer valida tipo, quantidade de pernas, conta, direção, valor, saldos antes/depois, titular,
  organização, categorias e metadados permitidos;
- cache é atualizado somente após retorno positivo da transação;
- nenhum SQL de saldo foi adicionado ao `mz_bank` ou `mz_economy`.

O runner P3-F não recebe input do client. A suíte padrão usa apenas memória. O comando real
consolidado é exclusivo do console, limita o valor, exige simultaneamente
`mz_core_p3f_runtime_runner=1` e `mz_core_p3f_runtime_real_writes=1`, restaura o saldo inicial e
confere outbox/recibo/ledger. Após o teste, ambas as convars devem voltar a `0` e o `mz_core` ser
reiniciado.

## 10. Limites e riscos

1. Runtime ainda deve provar MySQL transaction, consumer e dispatcher com os novos tipos.
2. O histórico `mz_org_account_transactions` continua sendo auditoria auxiliar posterior ao commit;
   sua falha não altera saldo nem substitui a outbox/ledger oficial.
3. A criação inicial com `Config.StarterMoney` não foi redesenhada: não é um dos produtores formais
   do P3-F e será reavaliada no inventário final P3-G.
4. Chamada pessoal sem idempotency key continua representando uma nova operação por contrato.
5. O fallback best-effort existe somente para compatibilidade com a feature desligada; a aprovação
   final exige testar a configuração real com writes, consumer e dispatcher ligados.
6. Taxa + compensação continua sendo uma sequência de negócio, embora cada mutação seja durável.

## 11. Não implementado

- P3-G ou aprovação completa da Fase 3;
- purge automático;
- novo saldo, ledger ou conta;
- phone/API bancária compartilhada;
- transferência offline;
- alteração do ciclo de cartão/inventário;
- mudança da criação inicial de personagem.

## 12. Decisão

```text
Fase 3: [~] Em implementação
P3-F: [S] Validado estaticamente
Runtime do P3-F: NÃO EXECUTADO
Próximo passo: PHASE_3_P3_F_RUNTIME_CHECKLIST.md
```
