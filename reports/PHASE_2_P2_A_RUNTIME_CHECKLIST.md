# Fase 2 — Checklist runtime do Lote P2-A

## 1. Escopo e decisão atual

Este documento prepara a validação runtime da fundação de persistência da identidade bancária pública criada no Lote P2-A.

O checklist foi elaborado inicialmente sem execução. Em 2026-07-15, o usuário informou que os testes executáveis foram realizados manualmente no MySQL/FiveM staging e passaram. Os campos abaixo preservam as queries, logs esperados e observações originais; os resultados registram somente essa confirmação fornecida pelo usuário.

```text
Fase 2: [~] Em implementação
P2-A: [R] Aprovado em runtime
Runtime P2-A: APROVADO
```

Fora do escopo deste checklist:

- P2-B e lotes posteriores;
- criação automática, backfill, resolução pública e CRUD de contas;
- troca do destino atual de transferência por conta pública;
- aplicativo ou canal `phone`;
- transferência offline;
- contas empresariais, PIX, QR Code e produtos financeiros;
- qualquer alteração em `wallet`, `bank`, `dirty` ou `mz_player_accounts`.

## 2. Base real confirmada

- Migration: `sql/003_mz_bank_accounts.sql`.
- Registro real de versões: `mz_bank_schema_migrations`.
- Versão esperada pelo runner: `3`.
- Export somente leitura de readiness: `exports['mz_bank']:GetReadiness()`.
- Tabela pública sem saldo: `mz_bank_accounts`.
- Agência padrão: `0001`.
- Número da conta: oito dígitos.
- Tipo inicial: `personal`.
- Estados configurados: `active`, `blocked`, `frozen` e `closed`.
- DV: módulo 11 sobre `branch .. account_number`, com pesos `2..9` da direita para a esquerda; resultados 10 e 11 tornam-se `0`.
- Unicidade do titular/tipo: `(citizenid, account_type)`.
- Unicidade da rota no schema real: `(branch, account_number)`. Essa constraint é mais forte que incluir o DV, pois também impede o mesmo número com DV diferente.
- Não há foreign key, saldo, backfill ou importação de legado na migration 003.

Limitações conhecidas que devem ser preservadas na interpretação dos resultados:

- `status` é `VARCHAR(16)`. Os quatro estados são validados pela configuração e pelo módulo Lua; não existe `CHECK`/`ENUM` no banco. Uma escrita SQL direta com estado arbitrário não prova um fluxo de produto válido.
- `metadata_json` é `LONGTEXT NULL`; o banco não valida JSON nativamente.
- P2-A implementa cálculo e validação do DV, mas não implementa geração de conta nem API pública para isso.
- `Config.PublicAccount.Enabled` permanece `false`; o schema/readiness é carregado, mas os fluxos bancários atuais ainda não usam a identidade pública.

## 3. Regras de execução e segurança

Executar exclusivamente em FiveM staging com banco descartável ou clone restaurável. Os testes de ausência de tabela, concorrência e inserts controlados não podem ser executados em produção.

Antes do primeiro teste, registrar:

| Campo | Valor real |
|---|---|
| Servidor/ambiente | MySQL/FiveM staging; identificação detalhada não fornecida |
| Build FiveM/FXServer | PENDENTE |
| Versão `mz_bank` | PENDENTE |
| Versão `mz_core` | PENDENTE |
| Versão `oxmysql` | PENDENTE |
| MySQL/MariaDB | PENDENTE |
| Schema/database | PENDENTE |
| Backup/snapshot | PENDENTE |
| Jogador A / personagem | PENDENTE |
| Jogador B / personagem | PENDENTE |
| Responsável | Usuário; execução manual |
| Data | 2026-07-15 |

Estados permitidos:

- `NÃO EXECUTADO`
- `APROVADO`
- `FALHOU`
- `BLOQUEADO`
- `NÃO APLICÁVEL`

Regras de preenchimento:

- só usar `APROVADO` após executar todos os passos e anexar as evidências indicadas;
- falha de preparação ou ausência de acesso deve ser `BLOQUEADO`, não aprovada por inferência;
- preservar o resultado real e o erro bruto de SQL/console;
- substituir os campos `PENDENTE` sem apagar pré-condições, passos ou resultado esperado;
- restaurar o pacote/configuração e o banco de staging após cada fault injection.

## 4. Queries de conferência manual

### 4.1 Antes da migration

```sql
SELECT VERSION();

SHOW TABLES LIKE 'mz_bank_schema_migrations';
SHOW TABLES LIKE 'mz_bank_accounts';

-- Executar somente se mz_bank_schema_migrations já existir.
SELECT version, name, applied_at
FROM mz_bank_schema_migrations
ORDER BY version;
```

Em um banco totalmente limpo, a tabela de versões pode ainda não existir. O runner cria primeiro `mz_bank_schema_migrations` pela migration 000 e depois aplica as versões 1, 2 e 3.

### 4.2 Depois da migration

```sql
SHOW CREATE TABLE mz_bank_accounts;
SHOW INDEX FROM mz_bank_accounts;
SHOW COLUMNS FROM mz_bank_accounts;
SELECT * FROM mz_bank_accounts ORDER BY id;

SELECT version, name, applied_at
FROM mz_bank_schema_migrations
ORDER BY version;

SELECT ENGINE, TABLE_COLLATION
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name = 'mz_bank_accounts';

SELECT column_name, data_type, column_type, character_maximum_length,
       is_nullable, column_default, extra
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name = 'mz_bank_accounts'
ORDER BY ordinal_position;

SELECT index_name, non_unique,
       GROUP_CONCAT(column_name ORDER BY seq_in_index SEPARATOR ',') AS columns_in_order
FROM information_schema.statistics
WHERE table_schema = DATABASE()
  AND table_name = 'mz_bank_accounts'
GROUP BY index_name, non_unique
ORDER BY index_name;

SELECT constraint_name, constraint_type
FROM information_schema.table_constraints
WHERE table_schema = DATABASE()
  AND table_name = 'mz_bank_accounts'
ORDER BY constraint_name;
```

### 4.3 Proibição de saldo paralelo

```sql
SELECT column_name
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name = 'mz_bank_accounts'
  AND LOWER(column_name) IN ('balance', 'wallet', 'bank', 'money', 'amount');
```

Resultado obrigatório: zero linhas.

### 4.4 Snapshot financeiro e legado

Registrar os valores exatos dos personagens usados no teste, antes e depois:

```sql
SELECT citizenid, wallet, bank, dirty, created_at, updated_at
FROM mz_player_accounts
WHERE citizenid IN ('<CITIZENID_A>', '<CITIZENID_B>')
ORDER BY citizenid;

SELECT COUNT(*) AS total_rows,
       COALESCE(SUM(wallet), 0) AS total_wallet,
       COALESCE(SUM(bank), 0) AS total_bank,
       COALESCE(SUM(dirty), 0) AS total_dirty
FROM mz_player_accounts;

SELECT table_name, table_rows
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name IN ('bank_accounts', 'bank_transactions')
ORDER BY table_name;
```

As somas globais são apoio; a comparação decisiva usa os valores exatos dos personagens e as operações executadas.

## 5. Casos de teste

### P2A-INIT-01 — Pré-migration em banco limpo

- **test_id:** `P2A-INIT-01`
- **Pré-condições:** clone descartável sem `mz_bank_accounts`; backup registrado; `mz_bank` parado.
- **Passos:** executar as queries de 4.1; confirmar versão do servidor SQL; registrar se `mz_bank_schema_migrations` existe e suas versões; confirmar ausência de `mz_bank_accounts`.
- **Resultado esperado:** ambiente inicial conhecido; `mz_bank_accounts` ausente; nenhuma alteração realizada.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** saída de `SELECT VERSION()`, `SHOW TABLES` e registro de versões.
- **Evidência de console:** N/A antes do start; anexar confirmação de resource parado.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** não remover tabela de ambiente compartilhado para simular banco limpo.

### P2A-INIT-02 — Aplicação da migration 003 e start normal

- **test_id:** `P2A-INIT-02`
- **Pré-condições:** `P2A-INIT-01` concluído; dependências oficiais iniciadas; arquivos SQL 000–003 presentes.
- **Passos:** iniciar `mz_bank`; aguardar bootstrap; executar queries de 4.2; consultar `GetReadiness` por contexto server-side autorizado.
- **Resultado esperado:** migrations pendentes aplicadas em ordem; linha `3 / mz_bank_accounts` registrada; tabela criada; console informa `ready schema_version=3`; readiness contém `ready=true`, `migration.ready=true`, `currentVersion=3`, `expectedVersion=3` e `error=nil`.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** `SHOW CREATE TABLE`, registro de versões e `SELECT *` inicialmente vazio.
- **Evidência de console:** linha de ready e retorno integral de `GetReadiness`.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** não inventar export client-side; `GetReadiness` é server-side.

### P2A-IDEM-01 — Segunda execução da migration

- **test_id:** `P2A-IDEM-01`
- **Pré-condições:** migration 003 aplicada e tabela válida; snapshot de schema e dados capturado.
- **Passos:** executar novamente o conteúdo real de `003_mz_bank_accounts.sql` no clone; reiniciar `mz_bank`; repetir queries de schema, índices, versões e dados.
- **Resultado esperado:** nenhuma exceção; nenhuma coluna, índice ou constraint duplicada; somente uma versão 3; readiness permanece true.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** resultados antes/depois de `SHOW CREATE TABLE`, `SHOW INDEX`, contagem de versões e conteúdo da tabela.
- **Evidência de console:** start sem `migration_failed` ou `schema_invalid`; ready na versão 3.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** a reexecução manual testa o `CREATE TABLE IF NOT EXISTS`; o restart testa o runner versionado.

### P2A-IDEM-02 — Preservação de dados existentes

- **test_id:** `P2A-IDEM-02`
- **Pré-condições:** inserir em staging uma linha válida de controle e registrar todos os seus campos.
- **Passos:** reexecutar a migration 003 e reiniciar `mz_bank`; consultar a linha pelo `id` e pela rota.
- **Resultado esperado:** linha e valores permanecem intactos; nenhuma linha adicional é criada; timestamps só mudam se houver update explícito.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** linha antes/depois e contagens por owner/rota.
- **Evidência de console:** ausência de erro de migration/readiness.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** usar identificador de teste e limpar somente após capturar a evidência.

### P2A-SCHEMA-01 — Engine e charset

- **test_id:** `P2A-SCHEMA-01`
- **Pré-condições:** migration 003 aplicada.
- **Passos:** consultar `information_schema.tables` e `SHOW CREATE TABLE`.
- **Resultado esperado:** `ENGINE=InnoDB`; charset derivado da collation é `utf8mb4`.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** `ENGINE`, `TABLE_COLLATION` e DDL completo.
- **Evidência de console:** readiness true na versão 3.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** a collation específica pode variar, mas deve começar por `utf8mb4_`.

### P2A-SCHEMA-02 — Campos, tipos, nulabilidade e defaults

- **test_id:** `P2A-SCHEMA-02`
- **Pré-condições:** migration 003 aplicada.
- **Passos:** executar `SHOW COLUMNS` e consulta detalhada de `information_schema.columns`; comparar com a migration.
- **Resultado esperado:** 11 campos: `id BIGINT UNSIGNED AUTO_INCREMENT`, `citizenid VARCHAR(32)`, `branch CHAR(4) DEFAULT '0001'`, `account_number CHAR(8)`, `check_digit CHAR(1)`, `account_type VARCHAR(24) DEFAULT 'personal'`, `status VARCHAR(16) DEFAULT 'active'`, `created_at`, `updated_at ON UPDATE`, `closed_at NULL`, `metadata_json LONGTEXT NULL`; somente `closed_at` e `metadata_json` são anuláveis.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** listagem completa ordenada por `ordinal_position`.
- **Evidência de console:** ausência de `schema_invalid:*:column*`, `nullable`, `default`, `unsigned`, `extra` ou `auto_increment`.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** `metadata_json` não possui validação JSON no banco.

### P2A-SCHEMA-03 — Índices e constraints

- **test_id:** `P2A-SCHEMA-03`
- **Pré-condições:** migration 003 aplicada.
- **Passos:** executar `SHOW INDEX`, consulta agrupada de `information_schema.statistics` e `table_constraints`.
- **Resultado esperado:** `PRIMARY(id)`; unique `uq_mz_bank_accounts_owner_type(citizenid,account_type)`; unique `uq_mz_bank_accounts_route(branch,account_number)`; índices `route_lookup(branch,account_number,check_digit,account_type)`, `owner_status(citizenid,status)` e `status(status)`; nenhuma foreign key.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** nomes, ordem de colunas e `non_unique` de todos os índices.
- **Evidência de console:** readiness true; nenhum `schema_invalid:mz_bank_accounts:index*`.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** a unicidade real da rota não inclui DV e por isso também rejeita a mesma agência/número com outro DV.

### P2A-SCHEMA-04 — Estados previstos e validação de configuração

- **test_id:** `P2A-SCHEMA-04`
- **Pré-condições:** deployment descartável; configuração original salva; acesso ao restart.
- **Passos:** confirmar os quatro estados no `Config.PublicAccount.AllowedStatuses`; iniciar com configuração original; em cópia de staging adicionar temporariamente `revoked=true`, reiniciar, capturar fail-closed; restaurar configuração e reiniciar.
- **Resultado esperado:** configuração original passa; estado extra causa `public_account_config_invalid:unexpected_account_status:revoked` e readiness false; após restauração volta a ready. O banco continua usando `VARCHAR(16)` sem `CHECK/ENUM`.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** `SHOW COLUMNS ... LIKE 'status'` e DDL.
- **Evidência de console:** erro explícito com estado inesperado, seguido de ready após restauração.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** não classificar a aceitação de string arbitrária por SQL direto como regressão do P2-A; fluxos futuros deverão chamar a validação Lua.

### P2A-UNIQ-01 — Uma conta pessoal por titular/tipo

- **test_id:** `P2A-UNIQ-01`
- **Pré-condições:** tabela válida; owner de teste inexistente; banco descartável.
- **Passos:** inserir `P2A_RT_OWNER_A / personal / 0001 / 11111111-9`; tentar inserir o mesmo owner e tipo com `22222222-9`; consultar contagem; limpar dados de teste.
- **Resultado esperado:** primeira linha aceita; segunda falha por `uq_mz_bank_accounts_owner_type`; permanece uma linha para owner/tipo.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** inserts, erro bruto de duplicate key e `COUNT(*)` por owner/tipo.
- **Evidência de console:** N/A, salvo se SQL for executado por harness autorizado.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** não usar citizenid real nem apagar dados fora do prefixo de teste.

### P2A-UNIQ-02 — Unicidade da agência/número

- **test_id:** `P2A-UNIQ-02`
- **Pré-condições:** rota `0001/12345678` livre em staging.
- **Passos:** inserir owner A com `0001/12345678-7`; tentar owner B com a mesma agência, número e DV; tentar novamente com DV diferente; consultar rota; limpar teste.
- **Resultado esperado:** apenas a primeira linha é aceita; ambas as tentativas seguintes falham por `uq_mz_bank_accounts_route`; não existe duplicidade de rota.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** erro bruto e contagem por `(branch,account_number)`.
- **Evidência de console:** N/A, salvo harness autorizado.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** o segundo insert com DV diferente confirma a constraint mais forte do schema real.

### P2A-UNIQ-03 — Titulares diferentes com rotas diferentes

- **test_id:** `P2A-UNIQ-03`
- **Pré-condições:** owners e rotas de teste livres.
- **Passos:** inserir owner A em `0001/11111111-9` e owner B em `0001/22222222-9`; consultar ambas; limpar teste.
- **Resultado esperado:** duas linhas aceitas, cada uma com owner e rota exclusivos.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** resultado das duas linhas e contagens de unicidade.
- **Evidência de console:** N/A, salvo harness autorizado.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** este teste não representa criação pelo produto; é validação exclusiva das constraints.

### P2A-UNIQ-04 — Concorrência termina em constraint

- **test_id:** `P2A-UNIQ-04`
- **Pré-condições:** duas sessões SQL independentes; chaves exclusivas de teste; timeout conhecido; banco descartável.
- **Passos:** nas duas sessões tentar concorrencialmente inserir o mesmo owner/tipo ou a mesma rota; confirmar uma transação; observar a outra; consultar resultado final; limpar dados.
- **Resultado esperado:** no máximo uma linha confirmada; concorrente aguarda e termina em duplicate key/constraint, nunca em duas linhas.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** timestamps das sessões, commits/erros brutos e consulta final.
- **Evidência de console:** N/A, salvo execução por harness.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** não considerar lock wait momentâneo como duplicidade; registrar eventual timeout como `BLOQUEADO` ou `FALHOU` conforme causa.

### P2A-DV-01 — Vetor oficial 0001/12345678-7

- **test_id:** `P2A-DV-01`
- **Pré-condições:** executar o arquivo real `server/account_identity.lua` em harness controlado do próprio resource/deployment, com a configuração real; sem criar export de produto.
- **Passos:** chamar `CalculateCheckDigit('0001','12345678')`; chamar `ValidateRoute('0001','12345678','7')`.
- **Resultado esperado:** cálculo retorna `'7'`; validação retorna `true`.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** N/A; DV não é calculado pelo banco.
- **Evidência de console:** entrada e retornos do módulo real.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** não validar com implementação reescrita que possa repetir o mesmo erro.

### P2A-DV-02 — Vetores adicionais

- **test_id:** `P2A-DV-02`
- **Pré-condições:** mesmo harness controlado de `P2A-DV-01`.
- **Passos:** calcular e validar `0001/00000001-7`, `0001/11111111-9`, `0001/22222222-9`, `0001/87654321-0` e `0001/99999999-9`.
- **Resultado esperado:** todos os DVs coincidem com os valores esperados e todas as rotas válidas retornam true.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** N/A.
- **Evidência de console:** tabela de entrada, DV calculado e retorno de validação.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** incluir ao menos um resultado convertido para zero, coberto por `87654321-0`.

### P2A-DV-03 — DV inválido e entradas inválidas

- **test_id:** `P2A-DV-03`
- **Pré-condições:** mesmo harness controlado dos testes de DV.
- **Passos:** validar `0001/12345678-6`; calcular com agência não numérica, número curto, número com letra e `00000000`.
- **Resultado esperado:** DV errado retorna `false, invalid_check_digit`; formatos inválidos retornam `invalid_branch` ou `invalid_account_number`; número reservado retorna `reserved_account_number`.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** N/A; a tabela não possui CHECK de DV.
- **Evidência de console:** erros exatos retornados pelo módulo real.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** um insert SQL direto com DV inválido pode ser aceito; isso não substitui a validação de serviço exigida nos lotes futuros.

### P2A-DV-04 — Consistência entre geração e validação

- **test_id:** `P2A-DV-04`
- **Pré-condições:** existência de gerador oficial de contas.
- **Passos:** gerar amostra de contas e validar cada rota pelo módulo oficial.
- **Resultado esperado:** todo DV gerado é aceito pelo mesmo contrato de validação.
- **Resultado real:** não aplicável: P2-A não implementa geração de contas.
- **Evidência SQL:** N/A.
- **Evidência de console:** N/A.
- **Status:** `NÃO APLICÁVEL`
- **Executado por:** N/A.
- **Data:** 2026-07-15.
- **Observações:** repetir obrigatoriamente no P2-B quando o gerador existir; não é aprovação runtime de geração.

### P2A-READY-01 — Fail-closed com versão 3 registrada e tabela ausente

- **test_id:** `P2A-READY-01`
- **Pré-condições:** clone descartável com migration 3 registrada; snapshot restaurável; `mz_bank` parado.
- **Passos:** no clone, tornar `mz_bank_accounts` indisponível sem alterar o pacote (por exemplo, renomear a tabela preservando-a); iniciar `mz_bank`; consultar readiness server-side; não abrir operações bancárias; restaurar após evidência.
- **Resultado esperado:** resource não anuncia ready; `migration.ready=false`; erro explícito inclui `migration_failed:schema_invalid:mz_bank_accounts:engine`; `MZBankService` permanece indisponível.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** versão 3 presente e `SHOW TABLES LIKE 'mz_bank_accounts'` vazio durante a falha.
- **Evidência de console:** linha `[mz_bank] unavailable error=...` e retorno completo de readiness.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** em banco limpo normal o runner aplica a migration automaticamente; por isso o fail-closed exige falha controlada/estado inconsistente. Nunca fazer em produção.

### P2A-READY-02 — Recuperação após aplicação/restauração do schema

- **test_id:** `P2A-READY-02`
- **Pré-condições:** falha de `P2A-READY-01` capturada; resource parado.
- **Passos:** restaurar a tabela ou aplicar a migration 003 no clone; confirmar schema; reiniciar `mz_bank`; consultar readiness.
- **Resultado esperado:** tabela válida; versão final 3; resource anuncia ready; erro anterior não permanece no novo bootstrap.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** DDL, índices e registro da versão 3.
- **Evidência de console:** ready versão 3 e readiness íntegro.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** não editar o registro de versões em ambiente real.

### P2A-NR-01 — Schema e saldos oficiais preservados

- **test_id:** `P2A-NR-01`
- **Pré-condições:** snapshots de `mz_player_accounts` e dos jogadores A/B antes da migration/restart.
- **Passos:** aplicar migration/start; repetir `SHOW CREATE TABLE mz_player_accounts`, valores exatos A/B e agregados.
- **Resultado esperado:** estrutura de `mz_player_accounts` inalterada; `wallet`, `bank` e `dirty` dos personagens permanecem iguais; nenhum saldo é copiado.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** DDL e snapshots antes/depois.
- **Evidência de console:** mensagem de ready declara saldos exclusivamente no `mz_core`; nenhum erro financeiro.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** divergência de qualquer saldo bloqueia o P2-A.

### P2A-NR-02 — Ausência de saldo e backfill em mz_bank_accounts

- **test_id:** `P2A-NR-02`
- **Pré-condições:** migration aplicada sem inserts de teste ativos.
- **Passos:** executar query de proibição de saldo; listar colunas; consultar todas as linhas.
- **Resultado esperado:** zero colunas `balance`, `wallet`, `bank`, `money` ou `amount`; zero linhas criadas automaticamente; nenhum backfill.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** query de 4.3 e `SELECT *`.
- **Evidência de console:** ausência de logs de criação/backfill.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** remover/rollback dos inserts controlados antes desta conferência.

### P2A-NR-03 — Tabelas legadas não importadas

- **test_id:** `P2A-NR-03`
- **Pré-condições:** contagem/ausência das tabelas `bank_accounts` e `bank_transactions` registrada antes; legado apply desabilitado.
- **Passos:** aplicar migration e reiniciar; comparar existência e contagens; confirmar `mz_bank_accounts` vazio sem inserts de teste.
- **Resultado esperado:** tabelas legadas não são alteradas nem apagadas; nenhuma linha é importada; eventual log apenas detecta legado.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** existência e contagens antes/depois.
- **Evidência de console:** nenhum apply/import; somente aviso de detecção, se aplicável.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** não executar comandos de aplicação do legado neste checklist.

### P2A-NR-04 — ATM e agência continuam abrindo

- **test_id:** `P2A-NR-04`
- **Pré-condições:** resource ready; jogador válido; ATM e agência oficiais; cartão válido para ATM.
- **Passos:** abrir agência, fechar corretamente; abrir ATM, autenticar e fechar; observar NUI, animação, alinhamento e slot.
- **Resultado esperado:** fluxos atuais abrem e fecham sem regressão; NUI, animação e slot preservados; identidade pública não é exigida.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** snapshot de saldos antes/depois, sem mudança causada apenas pela abertura.
- **Evidência de console:** ausência de erro; logs relevantes de sessão.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** anexar captura de ATM e agência.

### P2A-NR-05 — Depósito atual

- **test_id:** `P2A-NR-05`
- **Pré-condições:** sessão válida; valor inteiro permitido; saldos antes registrados.
- **Passos:** depositar valor controlado; fechar/reabrir ou atualizar; consultar persistência.
- **Resultado esperado:** `wallet` diminui e `bank` aumenta exatamente pelo valor; total preservado; resultado confirmado uma única vez.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** `mz_player_accounts` antes/depois e referência/correlationId disponível no fluxo atual.
- **Evidência de console:** retorno da operação sem erro.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** este é teste de não regressão, não implementação de conta pública.

### P2A-NR-06 — Saque atual

- **test_id:** `P2A-NR-06`
- **Pré-condições:** sessão válida; saldo bancário suficiente; valores antes registrados.
- **Passos:** sacar valor controlado; atualizar; consultar persistência.
- **Resultado esperado:** `bank` diminui e `wallet` aumenta exatamente pelo valor; total preservado; uma única movimentação.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** saldo antes/depois e referência/correlationId.
- **Evidência de console:** retorno da operação sem erro.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** preservar limites e contrato financeiro já aprovado.

### P2A-NR-07 — Transferência atual por destino legado

- **test_id:** `P2A-NR-07`
- **Pré-condições:** dois jogadores online; destino atual válido; saldo suficiente; snapshots de ambas as pontas.
- **Passos:** transferir valor controlado pelo fluxo atual; atualizar ambas as contas; consultar persistência.
- **Resultado esperado:** remetente debitado e destinatário creditado uma vez; totais preservados conforme taxa atual; nenhum uso obrigatório de `mz_bank_accounts` nesta etapa.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** saldos de A/B antes/depois e ledger/correlationId disponível.
- **Evidência de console:** retorno confirmado sem erro.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** P2-A não substitui ainda o server ID/fluxo atual.

### P2A-RST-01 — Restart de mz_bank

- **test_id:** `P2A-RST-01`
- **Pré-condições:** schema versão 3 válido; snapshots financeiros e de `mz_bank_accounts` capturados.
- **Passos:** executar `restart mz_bank`; aguardar bootstrap; consultar readiness, schema e dados; abrir uma agência ou ATM.
- **Resultado esperado:** ready versão 3; dados intactos; saldos inalterados; sessão nova abre normalmente.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** versões, dados públicos e saldos antes/depois.
- **Evidência de console:** stop/start e ready sem erro.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** sessões anteriores podem ser limpas conforme contrato atual.

### P2A-RST-02 — Restart de mz_core e recuperação do mz_bank

- **test_id:** `P2A-RST-02`
- **Pré-condições:** resources ready; snapshots capturados; ordem oficial conhecida.
- **Passos:** reiniciar `mz_core`; observar que `mz_bank` fica indisponível quando dependência obrigatória para; depois reiniciar `mz_bank` na ordem correta; consultar readiness e saldos.
- **Resultado esperado:** `mz_bank` não permanece falsamente ready durante dependência parada; após restart na ordem correta fica ready versão 3; cache/persistência e saldos permanecem coerentes.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** saldos e versões antes/depois.
- **Evidência de console:** `dependency_stopped:mz_core` e ready após recuperação.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** o código exige restart do `mz_bank` após dependência obrigatória voltar.

### P2A-RST-03 — Restart completo do servidor

- **test_id:** `P2A-RST-03`
- **Pré-condições:** estado persistente capturado; ordem oficial de resources configurada; backup disponível.
- **Passos:** reiniciar o servidor staging; aguardar carregamento completo; consultar readiness, migration version, schema, dados públicos e saldos; repetir abertura simples de ATM/agência.
- **Resultado esperado:** migrations não duplicam; versão 3; readiness true; contas públicas de controle e saldos oficiais intactos; fluxos atuais funcionam.
- **Resultado real:** APROVADO conforme resultado de execução manual informado pelo usuário.
- **Evidência SQL:** comparativo completo antes/depois.
- **Evidência de console:** sequência de startup e ready do `mz_bank`.
- **Status:** `APROVADO`
- **Executado por:** usuário, em execução manual no MySQL/FiveM staging.
- **Data:** 2026-07-15.
- **Observações:** registrar a ordem efetiva de `oxmysql`, `ox_lib`, `mz_core`, `mz_economy`, `mz_inventory` e `mz_bank`.

## 6. Resumo de execução

Resultado consolidado informado pelo usuário após execução manual:

| Métrica | Quantidade |
|---|---:|
| Total de casos | 28 |
| NÃO EXECUTADO | 0 |
| APROVADO | 27 |
| FALHOU | 0 |
| BLOQUEADO | 0 |
| NÃO APLICÁVEL | 1 |

Caso previamente classificado como não aplicável: `P2A-DV-04`, porque a geração de contas pertence ao P2-B.

## 7. Gate runtime do P2-A

O P2-A recebeu decisão runtime porque o usuário confirmou que:

- os 27 casos executáveis passaram;
- nenhum caso ficou `FALHOU` ou `BLOQUEADO`;
- migration, idempotência, schema, constraints e fail-closed passaram;
- `mz_player_accounts`, wallet, bank e dirty foram preservados;
- não existe saldo ou backfill em `mz_bank_accounts`;
- ATM, agência, depósito, saque e transferência não regrediram;
- os reinícios previstos passaram.

O caso `P2A-DV-04` permanece `NÃO APLICÁVEL`, pois geração de conta não existe no P2-A. A aprovação deste lote não aprova a Fase 2 inteira e não implementa nem aprova o P2-B.
