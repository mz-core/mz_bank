# Fase 2 — Aprovação runtime do Lote P2-A

## 1. Decisão

```text
Fase 2: [~] Em implementação
P2-A: [R] Aprovado em runtime
```

O usuário informou em 2026-07-15 que os testes executáveis de `PHASE_2_P2_A_RUNTIME_CHECKLIST.md` foram realizados manualmente no MySQL/FiveM staging e que todos passaram após o reteste do readiness.

Esta decisão aprova somente a fundação de persistência do P2-A. Não aprova a Fase 2 completa, não implementa o P2-B e não ativa contas públicas nos fluxos bancários.

## 2. Ambiente informado

| Campo | Resultado registrado |
|---|---|
| Ambiente | MySQL/FiveM staging |
| Executor | Usuário; execução manual |
| Data | 2026-07-15 |
| Migration esperada | Versão 3 — `mz_bank_accounts` |
| Tabela de versões real | `mz_bank_schema_migrations` |
| Build FXServer | Não fornecido |
| Versão MySQL/MariaDB | Não fornecida |
| Evidências externas anexadas | Não foram fornecidos arquivos externos; resultados e saídas foram informados na conversa |

## 3. Resultado consolidado

| Métrica | Quantidade |
|---|---:|
| Total de casos | 28 |
| Aprovados | 27 |
| Falhas pendentes | 0 |
| Bloqueados | 0 |
| Não executados | 0 |
| Não aplicáveis | 1 |

O caso `P2A-DV-04` permaneceu `NÃO APLICÁVEL`, porque o P2-A não implementa gerador de contas. Esse teste deve ser retomado no lote que implementar a geração oficial.

## 4. Evidências fornecidas

### 4.1 Migration e versionamento

O usuário forneceu o registro real de migrations:

```text
1  mz_bank_cards          2026-07-15 19:06:12
2  mz_bank_legacy_reports 2026-07-15 19:06:12
3  mz_bank_accounts       2026-07-15 19:11:42
```

Foi confirmada uma única entrada para a versão 3, sem duplicação de versão.

### 4.2 Schema

O `SHOW CREATE TABLE mz_bank_accounts` fornecido confirmou:

- `ENGINE=InnoDB`;
- charset `utf8mb4`;
- 11 campos previstos;
- `id BIGINT UNSIGNED AUTO_INCREMENT`;
- agência padrão `0001`;
- conta com oito dígitos;
- dígito com um caractere;
- tipo padrão `personal`;
- status padrão `active`;
- timestamps e `ON UPDATE`;
- `closed_at` e `metadata_json` anuláveis;
- nenhuma coluna de saldo.

O usuário também forneceu a listagem dos índices, confirmando:

- `PRIMARY(id)`;
- `uq_mz_bank_accounts_owner_type(citizenid, account_type)`;
- `uq_mz_bank_accounts_route(branch, account_number)`;
- `idx_mz_bank_accounts_route_lookup`;
- `idx_mz_bank_accounts_owner_status`;
- `idx_mz_bank_accounts_status`.

### 4.3 Unicidade

Os inserts controlados produziram duas linhas válidas para titulares e rotas diferentes:

```text
P2A_RT_OWNER_A  0001  11111111  9  personal  active
P2A_RT_OWNER_B  0001  22222222  9  personal  active
```

O usuário confirmou que o bloco de unicidade passou. Um resíduo de teste causado pelo modo de transação/autocommit do cliente SQL foi identificado e removido pelo prefixo exclusivo `P2A_RT_`; o usuário confirmou a limpeza posterior. Isso não foi classificado como defeito do schema.

### 4.4 Readiness

Na primeira execução houve um falso negativo de compatibilidade:

```text
[mz_bank] unavailable error=migration_failed:schema_invalid:mz_bank_accounts:default:branch
```

O schema fornecido estava correto. O MariaDB representava defaults textuais de forma diferente da comparação literal do readiness. O comparador foi normalizado sem alterar migration ou dados, e a sintaxe Lua foi validada.

No reteste, o usuário forneceu:

```text
[mz_bank] ready schema_version=3; balances are provided exclusively by mz_core
```

O banco abriu normalmente após o reteste. Readiness versão 3 foi aprovado.

### 4.5 Ausência de saldo paralelo

O usuário confirmou que os testes passaram:

- `mz_bank_accounts` não contém `balance`, `wallet`, `bank`, `money` ou `amount`;
- nenhum saldo foi criado ou copiado;
- `mz_player_accounts` permaneceu como persistência oficial;
- `player.money.wallet` e `player.money.bank` permaneceram sob o `mz_core`;
- não houve backfill nem importação de legado.

A saída específica da query negativa de colunas não foi anexada; a confirmação registrada é a declaração do usuário após a execução manual.

### 4.6 Idempotência

O usuário confirmou a reexecução/restart sem duplicação de migration, tabela, colunas, índices ou constraints. A versão permaneceu em 3 e os dados existentes foram preservados.

### 4.7 Não regressão

O usuário confirmou em runtime:

- abertura normal do banco;
- ATM e agência funcionando;
- depósito aprovado;
- saque aprovado;
- transferência atual aprovada entre jogadores online;
- saldo e persistência preservados;
- NUI, animação e slot preservados;
- reconnect e reinícios previstos sem alteração indevida de saldo.

A transferência testada continuou usando o server ID numérico do jogador online, como previsto no escopo do P2-A. Os `citizenid` alfanuméricos foram usados somente para conferência server-side/SQL.

## 5. Confirmações obrigatórias

| Gate | Resultado |
|---|---|
| Migration 003 aplicada | APROVADO |
| Idempotência | APROVADO |
| Schema, índices e constraints | APROVADO |
| Readiness fail-closed e recuperação | APROVADO após correção e reteste |
| Ausência de saldo em `mz_bank_accounts` | APROVADO conforme confirmação do usuário |
| Preservação de `mz_player_accounts` | APROVADO conforme confirmação do usuário |
| Ausência de backfill/importação de legado | APROVADO conforme confirmação do usuário |
| Não regressão financeira | APROVADO conforme execução manual |
| Reinícios | APROVADO conforme execução manual |
| Geração versus validação de DV | NÃO APLICÁVEL no P2-A |

## 6. Limitações preservadas

- `Config.PublicAccount.Enabled` continua `false`.
- Não existe criação automática de contas públicas.
- Não existe resolução de destinatário por agência, conta e dígito.
- O painel ainda usa o server ID numérico no fluxo antigo.
- `citizenid` não deve ser enviado pela NUI nem usado como identificador bancário público.
- Não foram implementados P2-B, phone, transferência offline, conta empresarial, PIX ou QR Code.
- A aprovação não cobre funcionalidades ainda inexistentes.

## 7. Decisão final

Com base nos resultados reais informados pelo usuário após execução manual no MySQL/FiveM staging:

```text
P2-A: [R] Aprovado em runtime
27 aprovados
0 falhas pendentes
0 bloqueados
1 não aplicável
```

A Fase 2 permanece `[~] Em implementação`.
