# Fase 2 — Implementação do Lote P2-B

Data: 2026-07-15  
Estado: **P2-B `[S]` — VALIDADO ESTATICAMENTE**  
Runtime específico do repository P2-B: **NÃO EXECUTADO**

## 1. Diagnóstico

O plano formal de `PHASE_2_DESIGN_REVIEW.md` define o P2-B como:

- migration `003_mz_bank_accounts.sql`;
- schema/readiness versão 3;
- repository somente de identidade;
- feature pública desligada;
- validação de instalação limpa, upgrade e rollback funcional.

Uma instrução posterior classificou migration, schema, DV e readiness como P2-A. Essa fundação já estava implementada e foi aprovada em runtime antes deste lote. Recriá-la no P2-B duplicaria responsabilidades e a fonte de DDL.

A lacuna real restante do P2-B era o repository interno de identidade. O `server/repository.lua` possuía apenas cartões e relatórios do legado e não consultava `mz_bank_accounts`.

## 2. Escopo exato implementado

Foram adicionadas duas consultas internas e somente leitura:

```lua
MZBankRepository.getPublicAccountByOwner(citizenid)
MZBankRepository.getPublicAccountByRoute(branch, accountNumber, checkDigit)
```

### Consulta por titular

- recebe `citizenid` exclusivamente de código server-side;
- exige string não vazia, sem espaços periféricos e com até 32 caracteres;
- fixa `account_type = 'personal'` pela configuração server-side;
- usa query parametrizada;
- retorna no máximo uma linha por causa da constraint já aprovada.

### Consulta por rota

- exige agência explícita como string;
- valida agência, número e DV pelo módulo real `MZBankAccountIdentity.ValidateRoute` antes da query;
- fixa `account_type = 'personal'` no servidor;
- consulta a rota exata com parâmetros;
- não lista contas, não busca por prefixo e não consulta por nome.

As linhas internas contêm somente:

```text
id
citizenid
branch
account_number
check_digit
account_type
status
created_at
updated_at
closed_at
```

O repository não produz DTO público. `id` e `citizenid` continuam restritos ao servidor.

## 3. Arquivos alterados

| Arquivo | Alteração |
|---|---|
| `server/repository.lua` | duas consultas internas e read-only para identidade pública |
| `BANK_ROADMAP.md` | P2-B registrado como `[S]`, sem aprovar a Fase 2 |
| `reports/PHASE_2_P2_B_IMPLEMENTATION.md` | este relatório |

Não foram alterados:

- migrations e schemas;
- `config.lua`;
- `server/account_identity.lua`, `service.lua`, `main.lua` ou bridge;
- client, NUI, animação ou slot;
- `mz_core`, `mz_economy` ou `mz_inventory`;
- fluxo financeiro, cartões ou legado.

## 4. Contratos reais utilizados

### Schema do mz_bank

As consultas usam somente a tabela real criada pela migration 003:

```text
mz_bank_accounts
```

Elas dependem das constraints reais:

- `uq_mz_bank_accounts_owner_type(citizenid, account_type)`;
- `uq_mz_bank_accounts_route(branch, account_number)`;
- `idx_mz_bank_accounts_route_lookup(branch, account_number, check_digit, account_type)`.

### Política de identidade

O tipo é obtido de `Config.PublicAccount.AccountType`, validado pelo readiness como `personal`. A rota usa o contrato existente:

```lua
MZBankAccountIdentity.ValidateRoute(branch, accountNumber, checkDigit)
```

### MySQL

O repository preserva o padrão real já usado pelo resource:

```lua
MySQL.single.await(query, parameters)
```

Nenhum export do `mz_core` ou `mz_economy` é necessário para consultas de identidade. Nenhum contrato novo foi inventado fora do resource.

## 5. Decisões

### Repository read-only

Não foi criado método de insert/update/delete. Criação idempotente, RNG, retry de colisão e estados pertencem ao P2-C no desenho formal.

### Sem exposição pública

Não foram adicionados:

- exports;
- callbacks `lib`;
- eventos de rede;
- NUI callbacks;
- comandos administrativos.

Logo, `citizenid` e o ID SQL não alcançam client ou NUI.

### Tipo fixado no servidor

O caller não escolhe `account_type`. Somente `personal` é consultado. Isso preserva a cardinalidade da Fase 2 e não antecipa contas empresariais.

### Rota validada antes da query

Uma rota com formato ou DV inválido termina no módulo de identidade e não consulta o banco. Essa proteção é interna; rate limit, resposta pública mínima e token de resolução permanecem para o P2-E.

### Feature permanece desligada

`Config.PublicAccount.Enabled` continua `false`. Nenhum fluxo atual chama o novo repository, portanto ATM, agência e transferência por server ID permanecem inalterados.

## 6. Validações estáticas

### Lua e JavaScript

- `luac -p` aprovado para todos os Lua de `mz_bank/server`;
- `node --check` aprovado para `html/script.js`;
- nenhuma alteração foi feita em JavaScript.

### Harness do repository

Um harness isolado carregou os módulos reais e simulou `MySQL.single.await`:

```text
repository harness: ok reads=3 writes=0
```

Foram confirmados:

- busca válida por owner usa `citizenid` e `personal` parametrizados;
- chamada repetida devolve a mesma identidade lógica;
- owner com espaço periférico é negado antes do SQL;
- vetor `0001/12345678-7` alcança a consulta de rota;
- DV incorreto é negado antes do SQL;
- nenhuma função de escrita foi chamada.

### Concorrência e idempotência

O P2-B não cria nem altera linhas. Consultas concorrentes são read-only e não introduzem corrida de escrita. Repetir a mesma consulta não produz efeito colateral.

As garantias de unicidade, idempotência da migration e concorrência do startup pertencem ao schema/readiness v3 já aprovado em runtime no P2-A. A criação concorrente de contas permanece explicitamente fora deste lote.

### SQL e saldo paralelo

- nenhum arquivo SQL foi alterado;
- não existe DML de `mz_bank_accounts` em código executável;
- o repository não seleciona nem escreve saldo;
- não existe acesso a `mz_player_accounts` nesses métodos;
- não existe ledger, outbox ou cache financeiro novo.

### Superfície client-facing

Busca estática em `mz_bank/client` e `mz_bank/html` confirmou zero referências a:

- `citizenid`;
- `mz_bank_accounts`;
- `Config.PublicAccount`.

O contrato antigo de transferência permanece intacto e continua usando server ID até o lote de cutover previsto.

### Não regressão estrutural

- `service.lua`, `main.lua`, bridge, client e NUI não foram alterados;
- sessões, cartões, validações físicas, animação, alinhamento e slot não mudaram;
- depósito, saque e transferência continuam usando os serviços oficiais do `mz_core`.

## 7. Riscos

- O repository existe, mas não possui consumidor até lotes posteriores; regressão de integração só poderá ser avaliada quando houver serviço interno autorizado.
- A ausência de foreign key permanece a decisão aprovada do P2-A; futuros writers deverão derivar o titular de identidade real server-side.
- A query interna retorna `id` e `citizenid`; qualquer DTO futuro deverá mapear e remover esses campos antes de responder ao client.
- O lookup de rota ainda não possui rate limit, auditoria ou resposta pública uniforme porque não há endpoint público. Esses controles são obrigatórios no P2-E.
- Nenhum teste contra MySQL real foi executado nesta implementação específica; o schema e os índices subjacentes foram aprovados em runtime no P2-A.

## 8. Testes runtime pendentes

Executar antes de qualquer aprovação `[R]` do P2-B:

1. com feature desligada, reiniciar `mz_bank` e confirmar readiness versão 3;
2. confirmar que owner inexistente retorna `nil` sem erro SQL;
3. em staging, inserir linha descartável válida e confirmar busca por owner;
4. confirmar busca da mesma linha por rota completa e DV correto;
5. confirmar que DV incorreto não consulta/retorna conta;
6. repetir e concorrer consultas, confirmando zero inserts/updates;
7. confirmar que nenhum dado interno é enviado à NUI;
8. abrir ATM e agência;
9. testar depósito, saque e transferência atuais;
10. confirmar ausência de alteração em wallet, bank e `mz_player_accounts`;
11. remover a linha descartável e confirmar limpeza.

Nenhum desses testes foi marcado como executado neste relatório.

## 9. Itens explicitamente não implementados

- geração segura de número;
- criação/`EnsurePersonalAccount`;
- insert, retry de colisão ou transaction de criação;
- DTO próprio do titular;
- integração ao overview;
- aplicação dos estados aos fluxos;
- backfill, ACE, preview ou batches;
- resolução pública, rate limit, auditoria ou `resolutionToken`;
- transferência por conta pública;
- alteração do campo da NUI;
- remoção do server ID;
- phone, transferência offline, conta empresarial, PIX ou QR Code;
- qualquer saldo ou ledger paralelo.

## 10. Próximo lote recomendado

Seguir o desenho formal com o P2-C:

- confirmar a primitiva segura de aleatoriedade no runtime;
- implementar geração e criação idempotente;
- tratar concorrência e colisões sem `INSERT IGNORE`;
- criar DTO próprio sem identificadores internos;
- integrar somente ao overview autenticado;
- manter transferências atuais inalteradas.

O P2-C exige prompt e revisão próprios. Não foi antecipado neste lote.

## 11. Estado final

```text
Fase 2: [~] Em implementação
P2-A: [R] Aprovado em runtime
P2-B: [S] Validado estaticamente
P2-C e seguintes: NÃO IMPLEMENTADOS
Fase 2 completa: NÃO APROVADA
```
