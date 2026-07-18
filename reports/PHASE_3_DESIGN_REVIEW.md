# MZ Bank — Revisão de desenho da Fase 3

Data: 2026-07-17  
Fase: 3 — Idempotência, outbox e auditoria  
Estado: **DESENHO CONCLUÍDO; IMPLEMENTAÇÃO NÃO INICIADA; RUNTIME NÃO EXECUTADO**

## 1. Escopo desta revisão

Esta etapa define a arquitetura e os lotes de implementação da Fase 3. Nenhum código, migration,
schema, configuração, saldo, ledger ou fluxo bancário foi alterado.

Foram confrontados com os arquivos reais atuais:

- os gates da Fase 3 em `BANK_ROADMAP.md`;
- `mz_core/server/accounts/service.lua`, `repository.lua`, `exports.lua` e `prepare.lua`;
- os fluxos reais de contas organizacionais e payroll do `mz_core`;
- `mz_economy/server/prepare.lua`, `repository.lua`, `service.lua` e `main.lua`;
- os contratos financeiros e metadados usados pelo `mz_bank`;
- a ordem real `mz_core -> mz_economy -> mz_bank` em `mz_starter/cfg/resources.cfg`.

Não foi usado Git ou histórico como fonte principal. Phone, transferência offline, PIX, QR Code,
conta empresarial e novos produtos financeiros não pertencem a esta etapa.

## 2. Diagnóstico real atual

### 2.1 O que já é seguro

Os dois serviços de transferência usados pelo banco já possuem locks no `mz_core`. Quando recebem
uma chave idempotente válida, eles gravam na mesma `MySQL.transaction.await`:

- a alteração de `mz_player_accounts`;
- a confirmação em `mz_account_idempotency`;
- o `correlationId` e o resultado recuperável.

O escopo real da chave é:

```text
source_resource + actor_citizenid + idempotency_key
```

Há unicidade adicional de `correlation_id`. O `mz_bank` já exige chave nas operações financeiras
repetíveis e fornece `external_ref`, canal server-side e contexto. Essa fundação deve ser
preservada, não substituída.

### 2.2 Falha estrutural atual

Depois do commit do saldo, `recordLedgerChange()` chama `mz_economy:RecordTransaction`. Se o
`mz_economy` estiver parado ou a inserção falhar, o core apenas registra o erro e segue. Portanto:

```text
saldo confirmado -> crash/economy offline -> extrato ausente sem retry persistente
```

Além disso, `mz_economy_transactions.transaction_id` é único, mas é gerado novamente em cada
chamada quando não é fornecido. Um retry ingênuo pode criar outro lançamento. `external_ref`, hoje,
não possui constraint de unicidade.

### 2.3 Cobertura idempotente incompleta

`TransferMoneyBetweenAccounts` e `TransferBankBetweenPlayers` suportam confirmação persistente. Já
`SetMoney`, `AddMoney` e `RemoveMoney` usam update simples e ledger posterior. Taxas de cartão,
ajustes, contas organizacionais e payroll também possuem caminhos best effort.

Os fluxos organizacionais e de payroll ainda fazem alterações relacionadas em comandos SQL
separados e compensações manuais. Eles não podem ser declarados atomicamente protegidos pela Fase 3
sem uma revisão própria. A aprovação final da fase exige incorporá-los ou classificá-los
formalmente fora do canal financeiro liberado.

### 2.4 Fontes oficiais preservadas

Permanecem como únicas fontes de saldo pessoal:

- `player.money.wallet` e `player.money.bank` em memória;
- `mz_player_accounts.wallet` e `mz_player_accounts.bank` no banco;
- serviços, locks e transações oficiais do `mz_core`.

A outbox guarda fatos de movimentação e snapshots de auditoria; nunca saldo disponível e nunca uma
fonte para autorizar operações.

## 3. Decisões arquiteturais

1. `mz_core` é dono de `mz_financial_outbox` e a insere na mesma transação SQL do saldo.
2. `mz_bank` fornece contexto e chave idempotente, mas não grava outbox nem ledger diretamente.
3. Uma linha de outbox representa uma operação/correlationId, inclusive quando há duas pernas.
4. As pernas do ledger ficam em um envelope versionado dentro de `metadata_json`.
5. O dispatcher fica no `mz_core`, que possui a outbox e controla claim, lease, ACK e retry.
6. O `mz_economy` expõe um consumidor **server-side privado**, aceitando somente o invocador
   `mz_core`.
7. O consumo grava recibo e todas as pernas do ledger em uma única transação SQL no `mz_economy`.
8. A idempotência financeira continua em `mz_account_idempotency`; a outbox não cria um segundo
   mecanismo de resultado financeiro.
9. Nenhum evento de rede, callback NUI ou export client-facing será criado.
10. Phone continua fora do escopo até a Fase 3 ser aprovada em runtime.

## 4. Modelo proposto: `mz_financial_outbox`

O schema abaixo é contratual para o P3-A; ainda não é uma migration executável.

| Campo | Tipo proposto | Regra |
|---|---|---|
| `id` | `BIGINT UNSIGNED` | PK auto increment |
| `correlation_id` | `VARCHAR(128)` | obrigatório e único |
| `idempotency_key` | `VARCHAR(64)` | nullable para operações internas não migradas |
| `event_type` | `VARCHAR(64)` | allowlist server-side |
| `source_citizenid` | `VARCHAR(64)` | nullable; nunca client-facing |
| `target_citizenid` | `VARCHAR(64)` | nullable; nunca client-facing |
| `account` | `VARCHAR(32)` | conta principal ou `multi` |
| `amount` | `BIGINT UNSIGNED` | inteiro positivo da operação |
| `fee` | `BIGINT UNSIGNED` | inteiro, default zero |
| `reason` | `VARCHAR(128)` | motivo normalizado |
| `source_resource` | `VARCHAR(100)` | derivado de `GetInvokingResource` |
| `source_channel` | `VARCHAR(32)` | allowlist; sessão server-side no banco |
| `payload_version` | `SMALLINT UNSIGNED` | inicialmente `1` |
| `metadata_json` | `LONGTEXT` | envelope validado e limitado |
| `status` | `VARCHAR(24)` | `pending`, `processing`, `processed`, `dead_letter` |
| `attempts` | `SMALLINT UNSIGNED` | default zero |
| `next_retry_at` | `TIMESTAMP` | elegibilidade de claim |
| `claim_token` | `VARCHAR(64)` | nullable, opaco e server-side |
| `claimed_at` | `TIMESTAMP NULL` | início do lease |
| `lease_expires_at` | `TIMESTAMP NULL` | recuperação de worker interrompido |
| `created_at` | `TIMESTAMP` | criação do fato |
| `processed_at` | `TIMESTAMP NULL` | ACK final |
| `last_error` | `VARCHAR(255)` | erro sanitizado, sem payload/PII |

### 4.1 Índices e constraints

```text
PRIMARY KEY (id)
UNIQUE (correlation_id)
UNIQUE (source_resource, source_citizenid, idempotency_key)
INDEX (status, next_retry_at, id)
INDEX (lease_expires_at, status)
INDEX (created_at)
INDEX (source_resource, created_at)
```

No MySQL/MariaDB, valores `NULL` não colidem no índice único composto. Operações sem chave não
ganham uma promessa falsa de idempotência; os serviços bancários repetíveis continuam obrigados a
fornecê-la.

Não será criada foreign key nesta primeira versão. A compatibilidade de engine/collation entre os
schemas reais não foi comprovada em todos os ambientes, e a outbox precisa sobreviver de forma
independente ao ciclo dos resources. O serviço valida referências e formato.

O schema deve usar `ENGINE=InnoDB` e `utf8mb4`. Como a versão exata do MySQL/MariaDB continua não
registrada, enums e checks serão aplicados pelo serviço/readiness, sem depender de `CHECK` que possa
ser ignorado pelo engine.

## 5. Envelope do evento v1

Uma operação gera uma linha de outbox e uma ou mais pernas:

```json
{
  "version": 1,
  "operation": "bank_transfer",
  "correlationId": "mzbank-...",
  "entries": [
    {
      "leg": 1,
      "citizenid": "SERVER_ONLY",
      "account": "bank",
      "direction": "out",
      "amount": 100,
      "balanceBefore": 500,
      "balanceAfter": 400,
      "category": "bank_transfer",
      "reason": "branch_public_account_transfer",
      "relatedCitizenid": "SERVER_ONLY",
      "countsAsIncome": false,
      "countsAsExpense": false
    }
  ],
  "context": {
    "sourceResource": "mz_bank",
    "sourceChannel": "branch"
  }
}
```

Transferência entre jogadores possui duas pernas; transferência wallet/bank também possui duas.
Taxa pode ser incorporada à perna de saída ou representada por uma perna própria, conforme o
contrato financeiro real, mas nunca contabilizada duas vezes.

O envelope não pode conter license, source FiveM, token de sessão/resolução, PIN, UID completo de
cartão, coordenada precisa, segredo, payload NUI cru ou metadata arbitrária. O tamanho deve ter
limite configurado e a allowlist deve ser construída no core.

`balanceBefore` e `balanceAfter` são snapshots de auditoria do commit; não são consultados como
saldo atual.

## 6. Escrita atômica no `mz_core`

Para uma transferência bancária idempotente, a mesma transação deve conter, nesta ordem lógica:

```text
INSERT mz_account_idempotency
UPDATE saldo do remetente
UPDATE saldo do destinatário
INSERT mz_financial_outbox
COMMIT
```

Para transferência entre contas do mesmo personagem:

```text
INSERT mz_account_idempotency
UPDATE wallet/bank na mesma linha
INSERT mz_financial_outbox
COMMIT
```

Qualquer falha no insert da outbox aborta o saldo. O cache só muda depois do commit, como já ocorre.
Replay encontra `mz_account_idempotency`, devolve o mesmo resultado e não cria saldo ou outbox de
novo.

O `correlationId` usado no resultado, idempotência, outbox e comprovante é exatamente o mesmo. Não
há geração independente pelo worker ou pelo `mz_economy`.

## 7. Consumo idempotente no `mz_economy`

### 7.1 Recibo proposto

Nova tabela de propriedade do `mz_economy`:

```text
mz_economy_outbox_receipts
```

Campos mínimos:

```text
id BIGINT UNSIGNED PK
outbox_id BIGINT UNSIGNED UNIQUE
correlation_id VARCHAR(128) UNIQUE
payload_version SMALLINT UNSIGNED
entry_count SMALLINT UNSIGNED
processed_at TIMESTAMP
metadata_json LONGTEXT NULL
```

Sem foreign key entre resources. O recibo e todas as linhas de `mz_economy_transactions` são
gravados na mesma transação. Cada lançamento usa `transaction_id` determinístico e curto:

```text
mzoutbox:<outbox_id>:<leg>
```

Isso cabe no `VARCHAR(64)` real e aproveita a unicidade já existente, sem alterar o schema atual da
tabela de extrato.

Se o core repetir a entrega após um crash entre o commit do economy e o ACK da outbox, o consumidor
encontra o recibo/correlationId e retorna sucesso com `replayed=true`; não insere outro ledger.

### 7.2 Contrato privado proposto

```lua
exports['mz_economy']:ConsumeFinancialOutbox(event)
```

Regras:

- `GetInvokingResource()` deve ser exatamente `mz_core`;
- nenhum source/citizenid é aceito do client;
- validar versão, correlationId, outbox ID, número de pernas, inteiros, contas e direções;
- não resolver identidade pelo source FiveM;
- retornar apenas `ok`, `replayed`, `correlationId` e erro técnico normalizado;
- falha de validação é permanente; indisponibilidade/SQL é retryable.

O export atual `RecordTransaction` permanece durante a migração dos produtores legados, mas não é
o consumidor da outbox e não deve ser chamado para os mesmos lançamentos, evitando ledger duplo.

## 8. Claim, lease, retry e dead letter

O dispatcher no `mz_core` usa claim atômico por token, sem depender de entidade networked ou de
`SELECT ... FOR UPDATE SKIP LOCKED`, cuja compatibilidade não foi confirmada.

Fluxo:

1. recuperar leases expirados para `pending`;
2. gerar `claim_token` opaco do worker;
3. `UPDATE ... ORDER BY id LIMIT batch` apenas em eventos elegíveis;
4. selecionar somente linhas com esse token;
5. entregar ao consumidor privado;
6. ACK somente com `WHERE id = ? AND claim_token = ? AND status = 'processing'`;
7. em falha transient, limpar lease, retornar a `pending` e agendar `next_retry_at`;
8. após o máximo, mover para `dead_letter` com erro sanitizado.

Configuração inicial recomendada:

| Parâmetro | Valor inicial |
|---|---:|
| poll | 1 segundo |
| batch | 25 |
| lease | 30 segundos |
| máximo de tentativas | 10 |
| backoff inicial | 5 segundos |
| backoff máximo | 15 minutos |

Backoff: exponencial com jitter server-side limitado. Um erro permanente de envelope pode ir para
dead letter imediatamente; indisponibilidade do `mz_economy` não consome tentativa enquanto nenhum
claim for feito.

## 9. Readiness e rollout

### 9.1 Fonte de schema

O projeto real usa `mz_core/server/prepare.lua` e `mz_economy/server/prepare.lua` como fontes de
schema desses resources. O P3-A deve seguir esse ownership e adicionar readiness estrutural
explícito. Não se deve duplicar as tabelas nas migrations do `mz_bank`.

### 9.2 Feature flags

O rollout deve começar desativado. Quando a escrita atômica for ativada:

- schema de outbox ausente ou inválido torna a mutação financeira indisponível, antes do saldo;
- `mz_economy` offline não bloqueia o commit, pois o evento já está persistido;
- worker indisponível gera health warning/backlog, sem apagar evento;
- o caminho best effort antigo é desligado para operações migradas.

Ativação deve ser por operação, não um cutover global cego.

## 10. Auditoria, métricas e privacidade

Métricas mínimas, sem PII:

- quantidade `pending`, `processing` e `dead_letter`;
- idade do evento pendente mais antigo;
- tentativas e falhas por `event_type`/`source_resource`;
- latência p50/p95 de processamento;
- leases expirados e replays do consumer;
- divergências de reconciliação.

Reprocessamento administrativo exige:

- ACE específica;
- console/server-side;
- preview;
- correlationId ou ID explícito;
- confirmação forte de uso único;
- justificativa;
- auditoria antes/depois;
- nunca alterar saldo;
- nunca editar manualmente o payload para “fazer passar”.

Comando de reprocesso apenas move um dead letter válido para `pending`. Corrigir payload ou criar
lançamento compensatório exige procedimento financeiro separado e auditado.

Retenção inicial proposta:

- processados: 90 dias, purge somente após reconciliação e relatório;
- dead letters: sem purge automático enquanto não resolvidos;
- ledger: conforme a política permanente do `mz_economy`;
- idempotência: não remover antes da janela máxima de replay definida para o produto.

## 11. Reconciliação

O reconciliador é read-only por padrão e compara:

- outbox `processed` sem recibo;
- recibo sem quantidade esperada de pernas no ledger;
- outbox pendente além do SLA;
- correlationId repetido ou divergente;
- ledger `mzoutbox:*` sem recibo;
- dead letters por tipo e idade.

Não é possível reconstruir com segurança um ledger ausente apenas pelo saldo atual. A correção usa
o envelope imutável da outbox e o consumer idempotente. Reconciliação nunca soma ou recalcula saldo.

## 12. Alternativas descartadas

| Alternativa | Motivo |
|---|---|
| outbox no `mz_bank` | não participa da transação que persiste o saldo |
| chamada síncrona ao `mz_economy` como garantia | falha depois do commit continua perdendo evento |
| uma outbox por perna | conflita com a unicidade oficial por correlationId e complica resultado |
| usar apenas `external_ref` do ledger | hoje não é único e não prova consumo completo de duas pernas |
| gerar novo correlationId no worker | quebra comprovante, replay e reconciliação |
| usar saldo da outbox | criaria fonte financeira paralela |
| expor endpoint de consulta/reprocesso ao client | amplia enumeração e superfície de fraude |
| liberar phone antes da aprovação | viola o gate explícito do roadmap |

## 13. Riscos e bloqueadores conhecidos

1. `AddMoney`, `RemoveMoney` e `SetMoney` ainda não compartilham idempotência/outbox atômica.
2. Taxas e rollback de cartão usam múltiplas operações e compensação.
3. Contas organizacionais e payroll ainda não são uma transação única entre todas as pontas.
4. A versão exata de MySQL/MariaDB não está registrada; SQL deve permanecer portátil.
5. Ativar outbox e manter `recordLedgerChange` para a mesma operação duplica extrato.
6. Payload grande ou com PII cria risco operacional; allowlist e limite são obrigatórios.
7. Claim sem token/lease permite dois workers; claim com lease sem consumer idempotente ainda duplica.
8. Purge antecipado elimina a evidência necessária à reconciliação.

## 14. Validação estática planejada

- localizar toda escrita em `mz_player_accounts` e `mz_org_accounts`;
- garantir insert de outbox na mesma lista de `MySQL.transaction.await`;
- garantir cache somente após commit;
- provar que operação migrada não chama o ledger best effort;
- validar unicidade e readiness das duas tabelas novas;
- validar envelope, tamanhos, inteiros, estados e allowlists;
- conferir invocador privado do consumer;
- buscar eventos/callbacks/NUI/exports indevidos;
- provar ausência de `balance` como fonte na outbox;
- validar ACK por claim token e recuperação de lease;
- validar que logs não contêm citizenid completo, token ou payload bruto.

## 15. Validação runtime planejada

1. migration/schema em banco limpo e segunda inicialização idempotente;
2. depósito, saque e transferência com uma outbox e ledger esperado;
3. `mz_economy` offline durante commit e processamento após retorno;
4. replay da mesma chave sem novo saldo, outbox ou ledger;
5. conflito da mesma chave com payload diferente;
6. dois workers concorrentes sem duplo consumo;
7. crash após claim e recuperação depois do lease;
8. crash após commit do ledger e antes do ACK, com replay do recibo;
9. falhas até dead letter, visibilidade e reprocesso auditado;
10. correlationId igual em resposta, idempotência, outbox, recibo, ledger e comprovante;
11. restart de `mz_core`, `mz_economy`, `mz_bank` e servidor;
12. backlog, métricas, retenção e reconciliação;
13. regressão de ATM, agência, NUI, animação, slot, cartão e estados;
14. conferência de cache/persistência e zero saldo paralelo.

Nenhum desses testes foi executado nesta revisão.

## 16. Plano de implementação em pequenos lotes

### P3-A — schema e readiness, feature desligada

- criar `mz_financial_outbox` no ownership do `mz_core`;
- criar `mz_economy_outbox_receipts` no ownership do `mz_economy`;
- readiness estrutural, estados/config e documentação;
- nenhuma mutação financeira usa a outbox ainda.

### P3-B — envelope e escrita atômica dos fluxos bancários atuais

- migrar `TransferMoneyBetweenAccounts` e `TransferBankBetweenPlayers`;
- preservar locks, idempotência e resultado atuais;
- desligar ledger best effort somente nesses caminhos;
- cobrir depósito, saque e transferência do `mz_bank`.

### P3-C — consumer idempotente no `mz_economy`

- contrato privado `mz_core -> mz_economy`;
- recibo + todas as pernas na mesma transação;
- replay seguro e IDs determinísticos de ledger.

### P3-D — dispatcher, claim, lease e retry

- worker do `mz_core`;
- backoff, lease expirado, ACK e health metrics;
- economy offline sem perda.

### P3-E — dead letter, administração e reconciliação

- preview/reprocesso com ACE e confirmação forte;
- auditoria sem PII;
- métricas, relatório de divergência e retenção.

### P3-F — cobertura dos produtores restantes

- `AddMoney`, `RemoveMoney`, `SetMoney`, taxas e compensações;
- revisão transacional separada de organizações/payroll;
- nenhuma aprovação total enquanto houver produtor financeiro best effort em escopo.

### P3-G — revisão estática e runtime final

- checklist completo, fault injection e concorrência;
- decisão final da Fase 3;
- somente depois disso avaliar liberação de novo canal financeiro.

## 17. Decisão final desta etapa

```text
Fase 3: [~] Em planejamento
Desenho: concluído
Implementação: não iniciada
Runtime: não executado
Próximo lote: P3-A — schema e readiness com feature desligada
```

O P3-A não deve antecipar escrita financeira, worker, consumer, dead letter ou phone.
