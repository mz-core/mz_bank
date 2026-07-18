# MZ Bank — Implementação do Lote P3-A

Data: 2026-07-17  
Fase: 3 — Idempotência, outbox e auditoria  
Lote: P3-A — schema e readiness com feature desligada  
Estado: **VALIDADO ESTATICAMENTE; APROVADO EM RUNTIME EM 2026-07-17**

## 1. Resultado

O P3-A criou exclusivamente a fundação persistente definida em
`PHASE_3_DESIGN_REVIEW.md`:

- `mz_financial_outbox`, sob ownership do `mz_core`;
- `mz_economy_outbox_receipts`, sob ownership do `mz_economy`;
- readiness estrutural fail-closed para as duas tabelas;
- versão lógica de schema `1`;
- flags explicitamente desligadas.

Nenhuma movimentação financeira foi ligada à outbox. Não existe worker, claim, consumer, retry,
dead letter, reprocesso, reconciliação ou phone neste lote.

```text
Fase 3: [~] Em implementação
P3-A: [R] Aprovado em runtime
Runtime P3-A: 7 aprovados, 0 falhas, 0 bloqueados, 1 não aplicável
```

## 2. Arquivos alterados

| Arquivo | Alteração |
|---|---|
| `mz_core/config.lua` | adiciona `Config.FinancialOutbox`, desligada, schema v1 |
| `mz_core/server/prepare.lua` | cria e valida `mz_financial_outbox` |
| `mz_economy/shared/config.lua` | adiciona configuração do recibo/consumer desligada |
| `mz_economy/server/prepare.lua` | cria e valida `mz_economy_outbox_receipts` |
| `mz_bank/BANK_ROADMAP.md` | registra estado e próximo gate |
| `mz_bank/reports/PHASE_3_P3_A_IMPLEMENTATION.md` | este relatório |
| `mz_bank/reports/PHASE_3_P3_A_RUNTIME_CHECKLIST.md` | checklist sem execução |

Não foram alterados `mz_bank/server`, `mz_core/server/accounts`, `mz_economy/server/service.lua`,
saldo, ledger ou NUI.

## 3. Schema final do P3-A

### 3.1 `mz_financial_outbox`

Campos:

```text
id BIGINT UNSIGNED PK AUTO_INCREMENT
correlation_id VARCHAR(128) NOT NULL
idempotency_key VARCHAR(64) NULL
event_type VARCHAR(64) NOT NULL
source_citizenid VARCHAR(64) NULL
target_citizenid VARCHAR(64) NULL
account VARCHAR(32) NOT NULL
amount BIGINT UNSIGNED NOT NULL
fee BIGINT UNSIGNED NOT NULL DEFAULT 0
reason VARCHAR(128) NOT NULL
source_resource VARCHAR(100) NOT NULL
source_channel VARCHAR(32) NOT NULL
payload_version SMALLINT UNSIGNED NOT NULL DEFAULT 1
metadata_json LONGTEXT NOT NULL
status VARCHAR(24) NOT NULL DEFAULT 'pending'
attempts SMALLINT UNSIGNED NOT NULL DEFAULT 0
next_retry_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
claim_token VARCHAR(64) NULL
claimed_at TIMESTAMP NULL
lease_expires_at TIMESTAMP NULL
created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
processed_at TIMESTAMP NULL
last_error VARCHAR(255) NULL
```

Índices:

```text
PRIMARY (id)
UNIQUE uq_mz_financial_outbox_correlation (correlation_id)
UNIQUE uq_mz_financial_outbox_idempotency_scope
  (source_resource, source_citizenid, idempotency_key)
INDEX idx_mz_financial_outbox_dispatch (status, next_retry_at, id)
INDEX idx_mz_financial_outbox_lease (lease_expires_at, status)
INDEX idx_mz_financial_outbox_created (created_at)
INDEX idx_mz_financial_outbox_source (source_resource, created_at)
```

### 3.2 `mz_economy_outbox_receipts`

Campos e índices:

```text
id BIGINT UNSIGNED PK AUTO_INCREMENT
outbox_id BIGINT UNSIGNED NOT NULL UNIQUE
correlation_id VARCHAR(128) NOT NULL UNIQUE
payload_version SMALLINT UNSIGNED NOT NULL
entry_count SMALLINT UNSIGNED NOT NULL
processed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
metadata_json LONGTEXT NULL
INDEX (processed_at)
```

Ambas usam `ENGINE=InnoDB` e `utf8mb4`. Nenhuma foreign key foi criada, conforme a decisão do
desenho e a compatibilidade ainda não comprovada entre schemas/ambientes.

## 4. Fonte de verdade e idempotência do DDL

O projeto real não possui registry versionado para schemas do `mz_core` e `mz_economy`; ambos usam
seus respectivos `server/prepare.lua` como fonte atual. O P3-A preservou esse padrão e não duplicou
DDL em `mz_bank/sql`.

As duas tabelas usam `CREATE TABLE IF NOT EXISTS`. Uma segunda inicialização não recria ou apaga
dados. Se existir tabela incompatível, o readiness não tenta uma correção destrutiva: falha com erro
estrutural explícito.

## 5. Readiness implementado

Após o DDL, cada resource confere no `information_schema`:

- existência da tabela;
- `ENGINE=InnoDB`;
- collation de charset `utf8mb4`;
- todas as colunas obrigatórias;
- PK, índices únicos e índices operacionais.

Estados registrados:

```text
MZCoreState.financialOutbox.schemaVersion = 1
MZCoreState.financialOutbox.schemaReady = true|false
MZCoreState.financialOutbox.enabled = false
MZCoreState.financialOutbox.writesEnabled = false

MZEconomyState.financialOutbox.schemaVersion = 1
MZEconomyState.financialOutbox.schemaReady = true|false
MZEconomyState.financialOutbox.enabled = false
MZEconomyState.financialOutbox.consumerEnabled = false
```

Schema ausente é criado. Schema divergente em coluna, índice, engine ou charset impede readiness e
produz erro explícito no console.

## 6. Garantias de escopo

- `mz_financial_outbox` não possui wallet, bank ou saldo disponível;
- `mz_economy_outbox_receipts` não possui saldo;
- nenhuma linha é inserida por operação financeira neste lote;
- `mz_player_accounts` não foi alterada;
- `mz_account_idempotency` não foi alterada;
- `mz_economy_transactions` não foi alterada;
- `recordLedgerChange` e `RecordTransaction` continuam no comportamento anterior;
- nenhum callback, evento de rede, NUI callback ou export foi criado;
- nenhuma feature pode ser ativada por client;
- nenhuma funcionalidade de P3-B ou superior foi antecipada.

## 7. Validações estáticas executadas

O parser `luac -p` aprovou:

```text
PASS mz_core/config.lua
PASS mz_core/server/prepare.lua
PASS mz_economy/shared/config.lua
PASS mz_economy/server/prepare.lua
```

Busca estática confirmou ausência de:

```text
INSERT INTO mz_financial_outbox
UPDATE mz_financial_outbox
INSERT INTO mz_economy_outbox_receipts
ConsumeFinancialOutbox
```

fora do DDL. Isso comprova que não há escrita operacional ou consumer no P3-A.

Não há cliente MySQL/MariaDB instalado no ambiente local do Codex. O DDL recebeu inspeção estática,
mas criação real, segunda inicialização e fail-closed dependem do staging.

## 8. Testes runtime pendentes

1. iniciar/reiniciar `mz_core` e confirmar o log:

```text
[mz_core][outbox] schema ready version=1 enabled=false writes=false
```

2. iniciar/reiniciar `mz_economy` e confirmar:

```text
[mz_economy][outbox] receipt schema ready version=1 enabled=false consumer=false
[mz_economy] passive ledger ready
```

3. conferir as tabelas:

```sql
SHOW CREATE TABLE mz_financial_outbox;
SHOW INDEX FROM mz_financial_outbox;
SELECT COUNT(*) AS outbox_rows FROM mz_financial_outbox;

SHOW CREATE TABLE mz_economy_outbox_receipts;
SHOW INDEX FROM mz_economy_outbox_receipts;
SELECT COUNT(*) AS receipt_rows FROM mz_economy_outbox_receipts;
```

4. reiniciar novamente e confirmar idempotência/ausência de erro;
5. confirmar ambas as contagens em zero antes do P3-B;
6. abrir ATM e agência;
7. executar depósito, saque e transferência atuais;
8. confirmar saldo, cache, persistência, ledger, NUI, animação e slot preservados;
9. confirmar que as duas tabelas P3-A continuam com zero linhas;
10. em staging restaurável, provocar drift controlado e confirmar fail-closed; restaurar depois.

Nenhum teste acima foi executado ou aprovado por este relatório.

## 9. Riscos e limitações

- `CREATE TABLE IF NOT EXISTS` não corrige drift; o readiness apenas bloqueia e informa.
- tipos/defaults detalhados são definidos pelo DDL, mas o readiness P3-A confere presença,
  engine, charset e índices; a revisão estática final deve conferir tipos novamente.
- não há registry persistente de versão no core/economy; `schemaVersion=1` é estado lógico de código.
- o ledger continua best effort até os lotes que migrarem as transações reais.
- ativar manualmente a flag agora não produz outbox; `writesEnabled`/`consumerEnabled` permanecem
  falsos de propósito.

## 10. Itens explicitamente não implementados

- envelope de evento;
- insert atômico com saldo;
- consumer privado;
- worker/dispatcher;
- claim, lease, retry ou backoff;
- dead letter e reprocesso;
- métricas e reconciliação;
- mudanças em organizações/payroll;
- phone ou qualquer novo canal financeiro.

## 11. Próximo passo recomendado

Preparar e executar o checklist runtime exclusivo do P3-A. Somente depois de schema, segunda
inicialização, readiness e regressão serem aprovados deve começar o P3-B.

```text
Fase 3: [~] Em implementação
P3-A: [S] Validado estaticamente
P3-A runtime: PENDENTE
```
