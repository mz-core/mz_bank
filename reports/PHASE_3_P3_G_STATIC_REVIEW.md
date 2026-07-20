# Fase 3 — Revisão estática final P3-G

Data: 2026-07-19  
Escopo: idempotência, outbox, consumer, dispatcher, auditoria e produtores financeiros  
Estado: **APROVADO ESTATICAMENTE; DECISÃO RUNTIME PENDENTE**

## Resultado

A implementação atual de P3-A a P3-F foi relida sem usar os relatórios como única fonte. A revisão
não encontrou escrita de saldo paralela, ledger paralelo no `mz_bank`, endpoint de rede para a
outbox ou quebra estática da atomicidade implementada.

```text
P3-G estático: APROVADO
P3-G runtime final: PENDENTE
Fase 3: [~] Em implementação
```

## Evidência estática confirmada

- `mz_financial_outbox` pertence ao `mz_core`; saldo e outbox são incluídos na mesma transação dos
  produtores migrados;
- `mz_economy_outbox_receipts` e todas as pernas do ledger são persistidos por uma única transação;
- correlationId e escopo idempotente possuem índices únicos;
- claim usa token opaco, status condicionado, lease e seleção exclusiva pelo token;
- ACK, retry, dead letter e reprocesso usam updates condicionais;
- lease expirado volta a `pending` sem nova alteração de saldo;
- o consumer aceita somente `GetInvokingResource() == 'mz_core'`, valida envelope, operação,
  titulares, valores, pernas, saldos e contexto;
- replay usa recibo persistente e IDs determinísticos `mzoutbox:<outbox_id>:<leg>`;
- reprocesso administrativo exige ACE, preview, TTL, ator, frase forte e gate de aplicação;
- reconciliação e retenção são read-only; não existe purge automático;
- `AddMoney`, `RemoveMoney`, `SetMoney`, transferências, organizações e payroll usam as fontes
  oficiais do `mz_core` e suprimem o ledger best-effort quando a outbox foi persistida;
- nenhum evento de rede, callback NUI ou payload client-facing foi criado para outbox, recibos,
  claim tokens ou citizenids;
- os runners retornam antes de registrar comandos quando suas convars estão desligadas e os comandos
  disponíveis são console-only;
- o caminho legado de importação continua separado, desativado e não participa do fluxo financeiro
  normal.

## Validações executadas

- `luac -p`: 33 arquivos Lua de `mz_core`, `mz_economy` e `mz_bank`, zero falhas;
- `node --check mz_bank/server/account_rng.js`: aprovado;
- busca por eventos/callbacks client-facing nos módulos da Fase 3: zero ocorrências;
- busca por citizenid/outbox/claim no client e NUI do banco: zero ocorrência indevida;
- busca por ownership de outbox: somente `mz_core` escreve `mz_financial_outbox`; somente
  `mz_economy` escreve recibos e ledger consumido;
- revisão dos manifests confirmou a ordem interna repository → service → consumer/dispatcher.

## Observações preservadas

1. As flags de outbox, writes, dispatcher e consumer permanecem desligadas por padrão no repositório.
   Isso é seguro para rollout, mas o ambiente que liberar um novo canal financeiro deverá ativá-las
   de forma coerente e comprovar readiness.
2. Os runners permanecem carregáveis pelos manifests, porém inertes por padrão e sem superfície de
   rede. A remoção física deles pertence à limpeza final do projeto, depois de encerradas as fases.
3. Os contratos organizacionais históricos ainda normalizam alguns valores antes de chegar à camada
   transacional. A API compartilhada da Fase 4 deve expor DTO estrito; isso não altera a atomicidade
   da Fase 3 nem autoriza input financeiro do client.

## Evidência runtime já válida e não repetida

- schema/readiness e idempotência das migrations;
- depósito, saque, transferências e produtores pessoais;
- economy offline, backlog, restart e retomada;
- consumer, recibos, ledger e replay;
- dead letter, preview, bloqueio por apply e reprocesso auditado;
- organizações, player ↔ organização e payroll;
- falha antes do commit, concorrência dos produtores e cache igual ao SQL;
- taxa/refund de cartão;
- smoke físico completo de ATM, agência, NUI, animação e slot.

## Deltas runtime que não podem ser inferidos

Os próprios checklists P3-C/P3-D mantiveram sem execução integral:

1. dois claims concorrentes disputando os mesmos eventos;
2. recuperação real de evento abandonado em `processing` após expiração do lease;
3. falha repetida com backoff até `dead_letter` pelo dispatcher;
4. consumo commitado seguido de ACK ausente, com recuperação e replay do recibo;
5. rollback conjunto de recibo e pernas após falha SQL controlada no consumer.

Esses deltas serão reunidos em uma única execução P3-G. Não é necessário repetir os 16 casos P3-F
nem os testes financeiros já aprovados.

## Decisão

Não existe bloqueador estático conhecido. A Fase 3 ainda não recebe `[R]` porque os cinco deltas
runtime acima não possuem evidência registrada. O próximo passo é preparar um runner final,
server-side, console-only, desativado por padrão e sem alteração de saldo real.

