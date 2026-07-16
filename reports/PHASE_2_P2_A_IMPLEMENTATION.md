# MZ Bank — Implementação do Lote P2-A da Fase 2

Data: 2026-07-15  
Escopo: fundação de persistência da identidade bancária pública  
Estado: **P2-A `[S]` — VALIDADO ESTATICAMENTE**  
Runtime MySQL/FiveM: **NÃO EXECUTADO**

## 1. Resultado

O Lote P2-A implementa exclusivamente:

- migration versionada `003` para `mz_bank_accounts`;
- schema sem saldo e sem relação com tabelas legadas;
- agência padrão `0001`;
- formato de conta com oito dígitos;
- dígito verificador módulo 11;
- estados `active`, `blocked`, `frozen` e `closed`;
- constraints de unicidade por titular/tipo e por rota pública;
- validação de versão, charset, nulabilidade, defaults, índices e readiness;
- política desativada por padrão, sem integração aos fluxos atuais.

Não foram implementados criação de conta, geração aleatória, backfill, lookup de destinatário, DTO público, alteração da NUI, transferência por conta, phone ou conta empresarial.

## 2. Arquivos alterados

| Arquivo | Alteração |
|---|---|
| `sql/003_mz_bank_accounts.sql` | nova migration aditiva e idempotente |
| `server/account_identity.lua` | política pura de formato, estados e cálculo/validação do DV |
| `server/migrations.lua` | versão esperada `3`, registro da migration e validação completa do novo schema |
| `config.lua` | fundação `Config.PublicAccount`, com feature desligada |
| `fxmanifest.lua` | carrega o módulo de identidade antes do runner |
| `SCHEMA_AND_STARTUP.md` | documenta v3, ausência de FK/saldo e rollback funcional |
| `BANK_ROADMAP.md` | Fase 2 `[~]` e P2-A `[S]`, sem aprovar a fase completa |
| `reports/PHASE_2_P2_A_IMPLEMENTATION.md` | este relatório |

Arquivos deliberadamente não alterados:

- `server/repository.lua`;
- `server/service.lua`;
- bridge, callbacks, client e NUI;
- qualquer arquivo do `mz_core`;
- migrations `000`, `001` e `002`;
- tabelas ou fluxo de legado.

## 3. Schema final

```sql
CREATE TABLE IF NOT EXISTS mz_bank_accounts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  citizenid VARCHAR(32) NOT NULL,
  branch CHAR(4) NOT NULL DEFAULT '0001',
  account_number CHAR(8) NOT NULL,
  check_digit CHAR(1) NOT NULL,
  account_type VARCHAR(24) NOT NULL DEFAULT 'personal',
  status VARCHAR(16) NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  closed_at TIMESTAMP NULL,
  metadata_json LONGTEXT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_mz_bank_accounts_owner_type (citizenid, account_type),
  UNIQUE KEY uq_mz_bank_accounts_route (branch, account_number),
  KEY idx_mz_bank_accounts_route_lookup
    (branch, account_number, check_digit, account_type),
  KEY idx_mz_bank_accounts_owner_status (citizenid, status),
  KEY idx_mz_bank_accounts_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

Não existem colunas `wallet`, `bank`, `balance`, `dirty` ou equivalentes.

## 4. Índices e constraints

### Constraints efetivas

- `PRIMARY KEY (id)`;
- `UNIQUE (citizenid, account_type)`: uma conta pessoal por personagem/tipo durante toda a vida do registro;
- `UNIQUE (branch, account_number)`: nenhuma rota pode ser reutilizada, inclusive após encerramento;
- campos essenciais `NOT NULL`;
- defaults persistidos para agência `0001`, tipo `personal` e estado `active`.

A unicidade de `(branch, account_number)` é mais forte que a tripla `(branch, account_number, check_digit)`: como o DV é determinístico, o mesmo número não pode existir com outro DV.

### Índices de consulta

- `idx_mz_bank_accounts_route_lookup` para rota completa e tipo;
- `idx_mz_bank_accounts_owner_status` para titular/estado;
- `idx_mz_bank_accounts_status` para operações administrativas futuras por estado.

### Foreign key

Nenhuma foreign key foi criada.

O schema real confirma `mz_players.citizenid VARCHAR(32) UNIQUE`, mas o DDL atual do core não fixa engine, charset ou collation. A compatibilidade de FK não é garantida em todos os ambientes e `ON DELETE CASCADE` também destruiria a reserva histórica da rota. A decisão segue o desenho aprovado.

### Estados

O módulo server-side aceita somente:

```text
active
blocked
frozen
closed
```

A migration mantém `VARCHAR(16)` por compatibilidade entre versões reais ainda não informadas de MySQL/MariaDB. Não foi adicionado `CHECK` que possa ser ignorado por um dos engines. A allowlist será obrigatória em todo repository/service futuro.

## 5. Algoritmo implementado

`server/account_identity.lua` implementa cálculo e validação, mas não cria contas.

Contrato:

```lua
MZBankAccountIdentity.CalculateCheckDigit(branch, accountNumber)
MZBankAccountIdentity.ValidateRoute(branch, accountNumber, checkDigit)
MZBankAccountIdentity.IsValidStatus(status)
MZBankAccountIdentity.ValidateConfiguration()
```

Regras:

1. agência é string com quatro dígitos;
2. conta é string com oito dígitos;
3. `00000000` é reservado;
4. concatenar agência e conta;
5. percorrer da direita para a esquerda com pesos cíclicos `2` a `9`;
6. somar os produtos;
7. `candidate = 11 - (sum % 11)`;
8. candidatos `10` ou `11` viram `0`;
9. DV final é uma string de um dígito.

Vetor confirmado pelo harness:

```text
0001 + 12345678 -> DV 7
0001 / 12345678-7 -> válido
0001 / 12345678-8 -> invalid_check_digit
0001 / 00000000-x -> reserved_account_number
```

Nenhum gerador de conta foi adicionado. A confirmação de uma fonte criptograficamente segura e a criação idempotente pertencem ao próximo lote; `math.random` não foi usado para emitir números públicos.

## 6. Readiness e migration

O runner agora espera a versão `3` e executa, na ordem:

```text
001 mz_bank_cards
002 mz_bank_legacy_reports
003 mz_bank_accounts
```

Antes de migrar, ele valida a configuração da identidade. Depois da migration, confere:

- tabela InnoDB;
- charset `utf8mb4` pela collation real;
- tipos e comprimentos;
- nulabilidade;
- defaults `0001`, `personal` e `active`;
- `BIGINT UNSIGNED` do ID;
- auto increment;
- `ON UPDATE CURRENT_TIMESTAMP` de `updated_at`;
- todos os índices e suas unicidades;
- versão final exatamente `3`.

Tabela ausente, coluna divergente, charset incorreto, default incompatível ou índice ausente mantém `ready = false` com erro `schema_invalid:*`.

O arquivo SQL é a única fonte executável de DDL. Não existe `MZBankRepository.prepare()`.

## 7. Aplicação idempotente

- a migration usa `CREATE TABLE IF NOT EXISTS`;
- a versão só é registrada depois da validação do objeto;
- a segunda execução encontra a versão e revalida o schema;
- nenhum DDL de `mz_bank_accounts` existe no repository;
- nenhuma linha de conta é criada por esta migration;
- nenhuma tabela existente é alterada ou excluída.

## 8. Decisões e diferenças em relação ao desenho

### Decisões preservadas

- `citizenid VARCHAR(32)` compatível em comprimento com o core;
- uma conta `personal` por `citizenid`;
- rota única e nunca reutilizada;
- InnoDB/utf8mb4;
- `metadata_json LONGTEXT`;
- ausência de saldo e FK;
- feature desativada até lotes posteriores.

### Diferenças controladas

1. O prompt desta implementação definiu a migration como P2-A, embora o plano de lotes do desenho original colocasse migration/readiness em P2-B. A instrução explícita mais recente foi aplicada sem avançar criação, backfill ou transferência.
2. `branch` recebeu também `DEFAULT '0001'` no banco. O desenho já definia `0001` como agência padrão, mas o SQL ilustrativo não declarava o default.
3. Não foram adicionados `CHECK` SQL de regex/enum porque a versão real de MySQL/MariaDB não foi fornecida. Isso segue a ressalva de portabilidade do próprio desenho.

## 9. Validações estáticas executadas

### Lua

- `luac -p` aprovado para todos os Lua do `mz_bank`;
- `config.lua` aprovado após normalizar somente hash literals com crase do FiveM para o parser local;
- módulo carregado com configuração isolada e testado por harness.

### Algoritmo

- configuração padrão aprovada;
- agência `0001` preservada como string;
- vetor `0001/12345678-7` aprovado;
- DV divergente negado;
- número reservado negado;
- quatro estados aceitos e estado desconhecido negado.

### SQL e fonte única

- estrutura do SQL conferida: campos, defaults, timestamps, índices, engine e charset presentes;
- um único `CREATE TABLE IF NOT EXISTS mz_bank_accounts` em arquivos executáveis;
- zero foreign keys;
- zero `DROP`, `TRUNCATE`, `DELETE`, DML de saldo ou referência a `mz_player_accounts` na migration;
- migrations atuais numeradas `000` a `003`;
- `sql/*.sql` já está incluído no `fxmanifest`;
- ausência confirmada de `repository.prepare()`.

### Harness do runner

Um harness Lua com MySQL simulado executou o runner real e confirmou:

```text
instalação limpa -> versão 3 / ready
segunda execução -> versão 3 / sem reaplicar 003
schema mz_bank_accounts ausente com versão registrada -> fail-closed
```

Esse harness valida a lógica do runner, não substitui uma execução contra MySQL/MariaDB real.

### Limite da validação SQL

Não havia cliente MySQL/MariaDB nem daemon Docker acessível no ambiente local. A migration recebeu validação estrutural e passou pelo runner simulado, mas a execução real do DDL permanece pendente e não foi inventada.

## 10. Testes runtime pendentes

Executar em staging antes de qualquer aprovação runtime:

1. banco limpo: iniciar o resource e conferir versões `1`, `2` e `3`;
2. upgrade real de schema v2 para v3 preservando dados anteriores;
3. segundo restart: confirmar ausência de erro e de duplicidade no registry;
4. conferir `SHOW CREATE TABLE mz_bank_accounts`;
5. conferir engine/collation, colunas, defaults e nulabilidade em `information_schema`;
6. conferir unicidade de owner/type e rota com transações descartáveis;
7. remover/renomear a tabela somente em banco descartável e confirmar readiness fail-closed;
8. adulterar índice/default/charset somente em banco descartável e confirmar erro explícito;
9. reiniciar com pacote compatível com schema v3 e feature desligada;
10. confirmar que wallet, bank, dirty, cartões e legado permaneceram inalterados.

Não marcar esses casos como aprovados sem resultado real fornecido.

## 11. Riscos

- aplicar v3 e voltar ao pacote v2 causa `schema_newer_than_resource`; rollback deve usar pacote compatível com v3;
- ausência de FK exige que o futuro serviço derive/valide o titular server-side;
- estados/formato ainda não possuem CRUD, portanto não há escrita de contas neste lote;
- geração segura de números permanece bloqueada até confirmar uma primitiva adequada;
- a tabela vazia não substitui o server ID nem muda a NUI atual;
- `mz_bank.zip` está defasado e não deve ser usado como rollback após aplicar v3;
- execução SQL real ainda está pendente.

## 12. Próximo lote recomendado

Somente após a migration v3 passar em MySQL/FiveM staging, preparar o P2-B com escopo restrito a:

- repository de identidade pública;
- confirmação da fonte de aleatoriedade segura;
- criação idempotente de uma conta pessoal;
- retry de colisão e concorrência;
- consulta própria server-side.

Ainda não incluir backfill, resolução pública, transferência por conta ou phone nesse próximo passo sem prompt específico.

## 13. Estado final

```text
Fase 2: [~] Em implementação
P2-A: [S] Validado estaticamente
Runtime P2-A: NÃO EXECUTADO
Fase 2 completa: NÃO APROVADA
```
