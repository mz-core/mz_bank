# Fase 2 — Checklist runtime do Lote P2-B

Data de criação: 2026-07-15  
Ambiente esperado: MySQL/FiveM staging  
Estado geral: **APROVADO — 13 de 13 casos**

```text
Fase 2: [~] Em implementação
P2-A: [R] Aprovado em runtime
P2-B: [R] Aprovado em runtime
Runtime específico do P2-B: APROVADO
```

## 1. Escopo

Este checklist valida somente os métodos internos e read-only adicionados no P2-B:

```lua
MZBankRepository.getPublicAccountByOwner(citizenid)
MZBankRepository.getPublicAccountByRoute(branch, accountNumber, checkDigit)
```

Também cobre readiness, privacidade, ausência de escrita, ausência de saldo paralelo e um smoke
test dos fluxos físicos atuais. Não valida nem implementa criação de conta, DTO público, backfill,
resolução pública, transferência por conta, `phone`, conta empresarial, PIX ou QR Code.

## 2. Limite de execução obrigatório

Os métodos do P2-B são internos ao `mz_bank` e, corretamente, não possuem export, evento de rede,
callback NUI ou comando público. Para executar os casos `P2B-REPO-*`, use somente um runner de teste
temporário carregado no contexto server-side do próprio `mz_bank`, exclusivamente em staging.

O runner deve:

- chamar os dois métodos reais sem copiar suas queries;
- ser acionável somente pelo console do servidor;
- não registrar evento de rede, NUI callback ou export;
- não aceitar `source` ou `citizenid` enviados pelo client;
- imprimir apenas resultado técnico controlado, sem dados de jogadores reais;
- ser removido ou permanecer fora do `fxmanifest.lua` após a execução.

O runner autorizado foi criado em `server/p2b_runtime_runner.lua`, permanece desativado por padrão
e é documentado em `reports/PHASE_2_P2_B_RUNTIME_RUNNER.md`. Se ele não for ativado exclusivamente
em staging, marque os casos `P2B-REPO-*` como `BLOQUEADO`. Executar apenas o SQL equivalente não
comprova o repository Lua.

Ativação temporária, somente pelo console do servidor:

```text
set mz_bank_p2b_runtime_runner 1
restart mz_bank
```

Execução, após a preparação SQL e o snapshot inicial:

```text
mz_bank_p2b_runtime_test
```

Desativação obrigatória após snapshots, smoke test e limpeza:

```text
set mz_bank_p2b_runtime_runner 0
restart mz_bank
```

Depois da desativação, o comando não deve mais estar registrado. Não persistir a convar em `.cfg`.

## 3. Estados e registro

Estados permitidos:

- `NÃO EXECUTADO`
- `APROVADO`
- `FALHOU`
- `BLOQUEADO`
- `NÃO APLICÁVEL`

Para cada caso, preservar:

- resultado real;
- saída SQL;
- saída integral do console, ocultando somente segredos;
- executor e data;
- observações e qualquer divergência.

Não marcar runtime como aprovado por inferência. Teste bloqueado ou não executado não é aprovado.

## 4. Ambiente

| Campo | Valor real |
|---|---|
| Servidor/ambiente | PENDENTE |
| Build FiveM/FXServer | PENDENTE |
| MySQL/MariaDB | PENDENTE |
| Versão `oxmysql` | PENDENTE |
| Versão `mz_core` | PENDENTE |
| Versão `mz_bank` | PENDENTE |
| Schema/database | PENDENTE |
| Backup/snapshot | PENDENTE |
| Personagem A | PENDENTE |
| Personagem B | PENDENTE |
| Responsável | PENDENTE |
| Data | PENDENTE |

## 5. Preparação SQL

Executar somente em staging. Antes de inserir, confirmar que os identificadores reservados para o
teste não existem:

```sql
SELECT id, citizenid, branch, account_number, check_digit, account_type, status,
       created_at, updated_at, closed_at
FROM mz_bank_accounts
WHERE citizenid IN ('P2B_RT_OWNER_A', 'P2B_RT_OWNER_B')
   OR (branch = '0001' AND account_number IN ('87654321', '99999999'))
ORDER BY id;
```

Resultado obrigatório antes da preparação: zero linhas. Se houver linhas, não sobrescrever nem
apagá-las sem confirmar que pertencem a uma execução anterior deste checklist.

Preparar duas identidades descartáveis, sem saldo e sem vínculo financeiro:

```sql
INSERT INTO mz_bank_accounts
  (citizenid, branch, account_number, check_digit, account_type, status, metadata_json)
VALUES
  ('P2B_RT_OWNER_A', '0001', '87654321', '0', 'personal', 'active', NULL),
  ('P2B_RT_OWNER_B', '0001', '99999999', '9', 'personal', 'blocked', NULL);

SELECT id, citizenid, branch, account_number, check_digit, account_type, status,
       created_at, updated_at, closed_at
FROM mz_bank_accounts
WHERE citizenid IN ('P2B_RT_OWNER_A', 'P2B_RT_OWNER_B')
ORDER BY citizenid;
```

Vetores reais de DV usados:

- `0001 / 87654321-0`;
- `0001 / 99999999-9`.

## 6. Snapshots obrigatórios

### 6.1 Identidades descartáveis

Executar antes e depois dos testes do repository:

```sql
SELECT id, citizenid, branch, account_number, check_digit, account_type, status,
       created_at, updated_at, closed_at, metadata_json
FROM mz_bank_accounts
WHERE citizenid IN ('P2B_RT_OWNER_A', 'P2B_RT_OWNER_B')
ORDER BY citizenid;
```

Os resultados antes e depois devem ser idênticos. Consultas read-only não podem alterar
`updated_at`, status ou metadata.

### 6.2 Saldos oficiais

Substituir pelos personagens reais usados no smoke test:

```sql
SELECT citizenid, wallet, bank, dirty, created_at, updated_at
FROM mz_player_accounts
WHERE citizenid IN ('<CITIZENID_A>', '<CITIZENID_B>')
ORDER BY citizenid;
```

O snapshot deve permanecer inalterado durante os testes exclusivamente read-only. No smoke test
financeiro, as diferenças devem corresponder exatamente às operações executadas pelos serviços
oficiais do `mz_core`.

### 6.3 Proibição de saldo paralelo

```sql
SELECT column_name
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name = 'mz_bank_accounts'
  AND LOWER(column_name) IN ('balance', 'wallet', 'bank', 'money', 'amount');
```

Resultado obrigatório: zero linhas.

## 7. Casos de teste

### P2B-INIT-01 — readiness com feature pública desligada

- **test_id:** `P2B-INIT-01`
- **Pré-condições:** migrations 000–003 aplicadas; `Config.PublicAccount.Enabled = false`.
- **Passos:** reiniciar `mz_bank`; aguardar bootstrap; consultar `GetReadiness()` por contexto server-side autorizado; conferir a versão em `mz_bank_schema_migrations`.
- **Resultado esperado:** resource inicia normalmente; `ready=true`; schema esperado e atual em versão 3; feature desligada não causa erro e nenhum fluxo público é ativado.
- **Resultado real:** runner informou `ready=true`, schema versão 3 e feature pública desligada.
- **Evidência SQL:** linha da migration 3.
- **Evidência de console:** mensagem `ready schema_version=3` e retorno de readiness.
- **Status:** `APROVADO`
- **Executado por/data:** usuário / 2026-07-16.
- **Observações:** resultado fornecido pelo usuário após execução no console do FiveM staging.

### P2B-REPO-01 — busca existente por titular

- **test_id:** `P2B-REPO-01`
- **Pré-condições:** preparação SQL concluída; runner interno disponível.
- **Passos:** chamar `getPublicAccountByOwner('P2B_RT_OWNER_A')` duas vezes.
- **Resultado esperado:** ambas retornam a mesma linha lógica de `0001/87654321-0`, tipo `personal`, status `active`; nenhum erro ou escrita.
- **Resultado real:** `PASS`; duas leituras consistentes da rota mascarada `0001/****4321-0`, status `active`.
- **Evidência SQL:** linha antes/depois conforme 6.1.
- **Evidência de console:** retorno controlado das duas chamadas.
- **Status:** `APROVADO`
- **Executado por/data:** usuário / 2026-07-16.
- **Observações:** não enviar o identificador ao client.

### P2B-REPO-02 — titular inexistente

- **test_id:** `P2B-REPO-02`
- **Pré-condições:** runner interno disponível; `P2B_RT_MISSING` inexistente.
- **Passos:** chamar `getPublicAccountByOwner('P2B_RT_MISSING')`.
- **Resultado esperado:** retorno `nil` sem exceção SQL e sem criar conta.
- **Resultado real:** `PASS`; titular inexistente retornou `nil`.
- **Evidência SQL:** contagem zero para o titular inexistente.
- **Evidência de console:** retorno técnico da chamada.
- **Status:** `APROVADO`
- **Executado por/data:** usuário / 2026-07-16.
- **Observações:** criação continua fora do escopo; conferência de ausência de escrita integra o snapshot ainda pendente.

### P2B-REPO-03 — titular interno inválido

- **test_id:** `P2B-REPO-03`
- **Pré-condições:** runner interno disponível.
- **Passos:** chamar por owner com string vazia, espaços periféricos, mais de 32 caracteres e valor não string.
- **Resultado esperado:** cada chamada retorna `nil, 'invalid_citizenid'` antes de consultar o MySQL.
- **Resultado real:** `PASS`; quatro vetores inválidos foram rejeitados.
- **Evidência SQL:** nenhuma linha criada ou alterada.
- **Evidência de console:** retorno de cada vetor e contador de queries do runner, se disponível.
- **Status:** `APROVADO`
- **Executado por/data:** usuário / 2026-07-16.
- **Observações:** log integral preservado na seção 10.

### P2B-REPO-04 — busca existente por rota completa

- **test_id:** `P2B-REPO-04`
- **Pré-condições:** preparação SQL concluída; runner interno disponível.
- **Passos:** chamar `getPublicAccountByRoute('0001', '87654321', '0')` e `getPublicAccountByRoute('0001', '99999999', '9')`.
- **Resultado esperado:** cada rota retorna somente seu titular e preserva tipo/status; nenhum efeito colateral.
- **Resultado real:** `PASS`; duas rotas mascaradas foram resolvidas corretamente.
- **Evidência SQL:** duas linhas preparadas e snapshot antes/depois.
- **Evidência de console:** retorno controlado de ambas as chamadas.
- **Status:** `APROVADO`
- **Executado por/data:** usuário / 2026-07-16.
- **Observações:** `citizenid` é evidência server-side e não pode alcançar NUI.

### P2B-REPO-05 — DV inválido e rota malformada

- **test_id:** `P2B-REPO-05`
- **Pré-condições:** runner interno disponível.
- **Passos:** consultar `0001/87654321-1`; depois testar agência curta, número curto, número `00000000`, DV com letra e valores não string.
- **Resultado esperado:** DV incorreto retorna `invalid_check_digit`; demais vetores retornam o erro de validação correspondente; nenhuma conta é retornada ou alterada.
- **Resultado real:** `PASS`; oito vetores de rota inválidos foram rejeitados.
- **Evidência SQL:** snapshot 6.1 sem mudanças.
- **Evidência de console:** erro exato de cada vetor.
- **Status:** `APROVADO`
- **Executado por/data:** usuário / 2026-07-16.
- **Observações:** a validação deve ocorrer antes da query de rota.

### P2B-REPO-06 — repetição e concorrência read-only

- **test_id:** `P2B-REPO-06`
- **Pré-condições:** runner interno capaz de disparar chamadas concorrentes; snapshots capturados.
- **Passos:** executar ao menos 20 buscas concorrentes por owner e 20 pela rota de OWNER_A; aguardar todas; repetir snapshot 6.1.
- **Resultado esperado:** todas retornam a mesma identidade lógica; zero insert/update/delete; timestamps e conteúdo permanecem iguais.
- **Resultado real:** `PASS`; 40 chamadas concluídas, zero falhas e zero escritas pelo runner.
- **Evidência SQL:** comparação integral dos snapshots e contagem de linhas.
- **Evidência de console:** quantidade de chamadas, sucessos e erros.
- **Status:** `APROVADO`
- **Executado por/data:** usuário / 2026-07-16.
- **Observações:** comparação SQL antes/depois permanece obrigatória em `P2B-FIN-01`.

### P2B-STATE-01 — estados preservados sem antecipar autorização

- **test_id:** `P2B-STATE-01`
- **Pré-condições:** OWNER_A `active` e OWNER_B `blocked`; runner interno disponível.
- **Passos:** buscar ambos por owner e rota; registrar o campo `status` retornado.
- **Resultado esperado:** repository retorna fielmente `active` e `blocked`; ele não altera estado nem decide permissões. Bloqueio de operações por estado pertence aos lotes consumidores posteriores.
- **Resultado real:** `PASS`; estados `active` e `blocked` foram preservados.
- **Evidência SQL:** status das duas linhas.
- **Evidência de console:** status retornado por cada chamada.
- **Status:** `APROVADO`
- **Executado por/data:** usuário / 2026-07-16.
- **Observações:** este teste não aprova semântica financeira de `blocked`, `frozen` ou `closed`.

### P2B-PRIV-01 — ausência de superfície client-facing

- **test_id:** `P2B-PRIV-01`
- **Pré-condições:** resource com os arquivos finais do P2-B.
- **Passos:** abrir banco físico e inspecionar payloads NUI/consoles; buscar estaticamente callbacks, eventos e exports ligados aos dois métodos.
- **Resultado esperado:** nenhuma linha interna, ID SQL ou `citizenid` chega ao client/NUI; não existe endpoint público P2-B.
- **Resultado real:** aprovado conforme confirmação do usuário; nenhum `citizenid` ou ID interno apareceu na tela/F8.
- **Evidência SQL:** N/A.
- **Evidência de console:** ausência de payload interno; registrar busca estática associada.
- **Status:** `APROVADO`
- **Executado por/data:** usuário / 2026-07-16.
- **Observações:** resultado declarado pelo usuário; nenhuma captura adicional foi anexada.

### P2B-FIN-01 — nenhuma alteração financeira pelas consultas

- **test_id:** `P2B-FIN-01`
- **Pré-condições:** snapshots 6.1 e 6.2 capturados; nenhuma operação financeira paralela ocorrendo.
- **Passos:** executar todos os testes `P2B-REPO-*`; repetir snapshots de identidade e saldos.
- **Resultado esperado:** wallet, bank, dirty, `mz_player_accounts` e as identidades permanecem inalterados; nenhuma coluna de saldo existe em `mz_bank_accounts`.
- **Resultado real:** aprovado conforme confirmação do usuário; os snapshots permaneceram iguais antes/depois das consultas.
- **Evidência SQL:** snapshots antes/depois e query 6.3.
- **Evidência de console:** ausência de operação financeira/correlationId causada pelas consultas.
- **Status:** `APROVADO`
- **Executado por/data:** usuário / 2026-07-16.
- **Observações:** resultado declarado pelo usuário; as saídas SQL integrais não foram anexadas.

### P2B-REG-01 — smoke test dos fluxos atuais

- **test_id:** `P2B-REG-01`
- **Pré-condições:** `mz_bank` ready; dois personagens de staging; saldos registrados.
- **Passos:** abrir ATM e agência; consultar overview/extrato; executar um depósito, um saque e uma transferência atual por server ID; fechar corretamente.
- **Resultado esperado:** NUI, animação, alinhamento e slot preservados; operações confirmadas pelos serviços oficiais do `mz_core`; nenhuma conta pública é criada ou usada.
- **Resultado real:** aprovado conforme confirmação do usuário; os fluxos físicos e operações atuais passaram corretamente.
- **Evidência SQL:** saldos/ledger correspondentes às operações reais.
- **Evidência de console:** readiness e correlationIds oficiais, sem erro P2-B.
- **Status:** `APROVADO`
- **Executado por/data:** usuário / 2026-07-16.
- **Observações:** resultado declarado pelo usuário; não aprova transferência por conta pública.

### P2B-RESTART-01 — restart após consultas

- **test_id:** `P2B-RESTART-01`
- **Pré-condições:** testes read-only concluídos; snapshots registrados.
- **Passos:** `restart mz_bank`; confirmar readiness; repetir uma busca por owner e rota via runner interno; abrir ATM/agência.
- **Resultado esperado:** versão 3 ready; mesmas identidades retornadas; nenhum dado ou saldo alterado; fluxo físico preservado.
- **Resultado real:** aprovado conforme confirmação fornecida pelo usuário após o restart do `mz_bank`; o resource retornou ready na versão 3 e o runner permaneceu habilitado para a revalidação.
- **Evidência SQL:** versões, identidades e saldos antes/depois.
- **Evidência de console:** restart, readiness e chamadas controladas.
- **Status:** `APROVADO`
- **Executado por/data:** usuário / 2026-07-16.
- **Observações:** a confirmação foi fornecida pelo usuário; nenhum log adicional do segundo resumo foi anexado nesta etapa.

### P2B-CLEAN-01 — limpeza controlada

- **test_id:** `P2B-CLEAN-01`
- **Pré-condições:** todos os casos anteriores registrados; IDs das duas linhas confirmados.
- **Passos:** remover somente as duas linhas descartáveis por `citizenid`; consultar novamente; reiniciar `mz_bank` e confirmar readiness.
- **Resultado esperado:** exatamente duas linhas removidas; nenhuma conta real afetada; buscas passam a retornar `nil`; resource continua ready.
- **Resultado real:** aprovado conforme confirmação do usuário; a limpeza retornou o resultado esperado e, após desativação/restart, o comando do runner deixou de existir.
- **Evidência SQL:** comandos e contagem afetada.
- **Evidência de console:** readiness após limpeza.
- **Status:** `APROVADO`
- **Executado por/data:** usuário / 2026-07-16.
- **Observações:** resultado declarado pelo usuário; saída SQL integral não anexada. Foram usados os identificadores exatos abaixo.

```sql
DELETE FROM mz_bank_accounts
WHERE citizenid IN ('P2B_RT_OWNER_A', 'P2B_RT_OWNER_B');

SELECT ROW_COUNT() AS deleted_test_rows;

SELECT COUNT(*) AS remaining_test_rows
FROM mz_bank_accounts
WHERE citizenid IN ('P2B_RT_OWNER_A', 'P2B_RT_OWNER_B');
```

Resultados esperados: `deleted_test_rows = 2` e `remaining_test_rows = 0`.

## 8. Invariantes obrigatórias

1. Os métodos P2-B nunca inserem, atualizam ou removem linhas.
2. Repetir ou concorrer uma consulta não muda identidade, timestamps ou saldo.
3. `account_type` é fixado como `personal` pelo servidor.
4. Rota inválida termina antes da consulta SQL correspondente.
5. Nenhum ID SQL ou `citizenid` chega ao client/NUI.
6. `mz_bank_accounts` não contém saldo.
7. `mz_player_accounts` continua sendo a persistência oficial de wallet/bank/dirty.
8. A feature pública permanece desligada e nenhum fluxo atual muda para conta pública.
9. ATM, agência, depósito, saque e transferência atual permanecem funcionais.
10. P2-C e lotes seguintes não são antecipados.

## 9. Resultado consolidado

| Métrica | Resultado |
|---|---:|
| Casos definidos | 13 |
| Executados | 13 |
| Aprovados | 13 |
| Falhas | 0 |
| Bloqueados | 0 |
| Não executados | 0 |

```text
P2-B runtime: APROVADO
P2-B: [R] Aprovado em runtime
Fase 2: [~] Em implementação
```

Todos os casos foram executados e registrados. A decisão correspondente foi consolidada em
`PHASE_2_P2_B_RUNTIME_APPROVAL.md`, que marca o P2-B como `[R]` sem aprovar a Fase 2 completa.

## 10. Evidência do runner

Estado: **RUNNER EXECUTADO E APROVADO; CASOS MANUAIS PENDENTES**

Evidência estática real já obtida — não substitui runtime:

```text
runner harness: reads=49 cases=8 summary_ok=true default_disabled=true console_only=true
forbidden surface/write scan: zero ocorrências
```

Colar aqui, sem inventar ou resumir falhas, todas as linhas de console entre:

```text
[mz_bank][p2b-runner] START fixed_test_vectors=true writes=disabled client_input=false
[mz_bank][p2b-runner] PASS P2B-INIT-01 detail=ready=true schema_version=3 feature_enabled=false
[mz_bank][p2b-runner] PASS P2B-REPO-01 detail=reads=2 route=0001/****4321-0 status=active
[mz_bank][p2b-runner] PASS P2B-REPO-02 detail=missing_owner=nil
[mz_bank][p2b-runner] PASS P2B-REPO-03 detail=vectors=4 rejected
[mz_bank][p2b-runner] PASS P2B-REPO-04 detail=routes=2 masked=0001/****4321-0,0001/****9999-9
[mz_bank][p2b-runner] PASS P2B-REPO-05 detail=vectors=8 rejected
[mz_bank][p2b-runner] PASS P2B-REPO-06 detail=calls=40 failures=0 writes=0_by_runner
[mz_bank][p2b-runner] PASS P2B-STATE-01 detail=states=active,blocked preserved
[mz_bank][p2b-runner] SUMMARY executed=8 passed=8 failed=0
[mz_bank][p2b-runner] END run SQL snapshots and manual cases; disable convar and restart mz_bank
```

### Execução intermediária com pré-condição ausente

O usuário forneceu também uma execução intermediária em que as linhas sintéticas não estavam
disponíveis para os lookups. O padrão `row_missing` foi preservado; os casos que não dependem dos
fixtures continuaram passando:

```text
[mz_bank][p2b-runner] PASS P2B-INIT-01 detail=ready=true schema_version=3 feature_enabled=false
[mz_bank][p2b-runner] FAIL P2B-REPO-01 detail=row_missing
[mz_bank][p2b-runner] PASS P2B-REPO-02 detail=missing_owner=nil
[mz_bank][p2b-runner] PASS P2B-REPO-03 detail=vectors=4 rejected
[mz_bank][p2b-runner] FAIL P2B-REPO-04 detail=row_missing
[mz_bank][p2b-runner] PASS P2B-REPO-05 detail=vectors=8 rejected
[mz_bank][p2b-runner] FAIL P2B-REPO-06 detail=calls=40 failures=40
[mz_bank][p2b-runner] FAIL P2B-STATE-01 detail=owner_a_status
[mz_bank][p2b-runner] SUMMARY executed=8 passed=4 failed=4
```

Classificação: execução inválida para aprovação dos quatro casos dependentes dos fixtures, pois a
pré-condição de duas linhas preparadas não estava satisfeita. A execução posterior, novamente com
as linhas disponíveis, retornou `executed=8 passed=8 failed=0`. O usuário ainda precisa confirmar
se essa última execução ocorreu após o restart exigido por `P2B-RESTART-01`.

Também registrar:

- snapshot SQL anterior: executado conforme confirmação do usuário; saída integral não anexada;
- snapshot SQL posterior: executado conforme confirmação do usuário; saída integral não anexada;
- comparação financeira: APROVADA conforme confirmação do usuário;
- smoke test físico completo: APROVADO conforme confirmação do usuário;
- limpeza das duas linhas sintéticas: APROVADA conforme confirmação do usuário;
- confirmação de convar `0` e comando ausente após restart: APROVADA conforme confirmação do usuário.
