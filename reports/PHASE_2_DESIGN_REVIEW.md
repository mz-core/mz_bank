# MZ Bank — Revisão de desenho da Fase 2

Data: 2026-07-15  
Fase: 2 — Identidade bancária pública  
Estado: **DESENHO PROPOSTO; NÃO IMPLEMENTADO; NÃO APROVADO**

## 1. Escopo e método

Esta revisão define a identidade bancária pública que substituirá o server ID como destino das transferências. Nenhum código, migration, schema ou configuração foi alterado.

Foram conferidos no estado real atual:

- `BANK_ROADMAP.md`, `reports/PHASE_0_STATIC_APPROVAL.md`, `RUNTIME_REPORT_PHASE_1.md` e `reports/PHASE_1_FINAL_DECISION.md`;
- todos os arquivos textuais atuais do `mz_bank`, seus SQLs `000` a `002`, client, NUI, bridge, repository, services, legado e relatórios;
- o conteúdo do artefato `mz_bank.zip`, apenas como inventário; ele não é carregado pelo `fxmanifest.lua` e está defasado em relação aos arquivos atuais;
- `mz_core/server/prepare.lua`, player repository/service/exports, accounts repository/service/exports e logs reais do core;
- as superfícies atuais consumidas pelo banco e o schema efetivamente preparado pelo `mz_core`.

Os relatórios anteriores foram usados como contexto. As decisões abaixo foram confrontadas com o código e os schemas atuais.

## 2. Diagnóstico real atual

### 2.1 Identidade e transferência atuais

O fluxo físico atual recebe `recipientValue` da NUI, limita-o a um server ID inteiro e resolve o jogador online em `MZBankService.ResolveRecipient`/`resolveServerIdRecipient`. Depois chama:

```lua
exports['mz_core']:TransferBankBetweenPlayers(source, target, amount, metadata)
```

O contrato real do core aceita `target` como source numérico ou `citizenid`. Nos dois casos o destinatário precisa estar no cache online. O core:

- resolve o destinatário;
- impede autotransferência;
- usa locks ordenados pelos dois `citizenid`;
- persiste as duas pontas em uma transação;
- atualiza o cache somente depois do commit;
- preserva `transactionRef`/`correlationId` e idempotência.

Logo, a Fase 2 deve substituir somente a resolução do destino:

```text
agência + conta + dígito
        ↓ mz_bank server-side
citizenid interno
        ↓ contrato real do mz_core
TransferBankBetweenPlayers
```

O `citizenid` nunca será aceito da NUI nem devolvido a ela.

### 2.2 Fontes oficiais preservadas

A identidade pública não terá saldo. Permanecem como únicas fontes financeiras:

- `player.money.wallet`;
- `player.money.bank`;
- `mz_player_accounts.wallet` e `mz_player_accounts.bank`;
- locks, idempotência, persistência e serviços financeiros oficiais do `mz_core`.

Não será criado ledger, outbox ou cache de saldo no `mz_bank_accounts`.

### 2.3 Schema real relacionado

O `mz_core` prepara atualmente:

```text
mz_players.citizenid         VARCHAR(32) UNIQUE NOT NULL
mz_players.license           VARCHAR(80) UNIQUE NOT NULL
mz_player_accounts.citizenid VARCHAR(32) UNIQUE NOT NULL
mz_player_accounts.bank      BIGINT NOT NULL
```

O DDL de `mz_players` não declara explicitamente engine, charset ou collation. Portanto, a compatibilidade necessária para foreign key não está comprovada no schema real de todos os ambientes.

As migrations atuais do banco terminam na versão `2`:

- `000`: registry `mz_bank_schema_migrations`;
- `001`: `mz_bank_cards`;
- `002`: `mz_bank_legacy_reports`.

Não existe atualmente `mz_bank_accounts`.

## 3. Decisões oficiais propostas

### 3.1 Natureza da conta pública

`mz_bank_accounts` será um diretório de identidade e roteamento. A linha significa “este endereço bancário público pertence internamente a este personagem”. Ela não representa, copia ou bloqueia diretamente o saldo do core.

Decisões:

- `citizenid` é chave interna server-side;
- o endereço público é `branch + account_number + check_digit`;
- `account_type = 'personal'` é o único tipo aceito na Fase 2;
- não serão armazenados nome, license, telefone, saldo, PIN ou segredo de cartão;
- o nome exibido será obtido server-side da identidade atual do `mz_core` somente quando necessário;
- `metadata_json` conterá apenas metadados internos versionados e não financeiros.

### 3.2 Cardinalidade

Política da Fase 2:

- cada `citizenid` pode possuir exatamente uma conta pública do tipo `personal` durante toda a vida do registro;
- essa conta é a conta padrão do personagem;
- criação repetida devolve a mesma linha;
- personagens diferentes, quando representados por `citizenid` diferentes, recebem contas diferentes;
- `license` não participa da cardinalidade nem da geração;
- uma conta `closed` permanece reservada e não gera automaticamente uma substituta;
- conta encerrada não é reaberta nem substituída nesta fase;
- número de conta encerrada nunca volta ao pool;
- novos tipos exigirão decisão de domínio, migration e constraint próprias.

O schema atual do core possui `license` único e pode limitar múltiplos personagens por licença. A identidade pública continuará correta se o core evoluir: a separação será sempre por `citizenid`, não por license.

Contas organizacionais não usarão `citizenid` pessoal de forma artificial. Uma fase futura deverá definir o dono oficial do saldo organizacional e então adotar `owner_type/owner_id` ou uma tabela própria. `account_type` não autoriza antecipadamente `organization`, `joint`, `savings` ou qualquer outro tipo.

### 3.3 Criação automática

A criação preguiçosa ocorrerá no primeiro acesso bancário autenticado que precisar do overview, não no simples callback de abertura e não a partir de dados livres do client.

Ordem proposta:

1. validar sessão, canal, posição, personagem e cartão conforme a política atual;
2. derivar o `citizenid` do player carregado no servidor;
3. executar `EnsurePersonalAccount`;
4. devolver o DTO próprio no overview;
5. continuar lendo saldo exclusivamente do core.

Isso evita criar contas a partir de tentativas físicas falsas. Backfill administrativo e criação preguiçosa poderão ocorrer simultaneamente porque as constraints serão a autoridade final.

## 4. Schema proposto

O SQL abaixo é apenas desenho. **Não é uma migration criada ou executada nesta etapa.**

```sql
CREATE TABLE IF NOT EXISTS mz_bank_accounts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  citizenid VARCHAR(32) NOT NULL,
  branch CHAR(4) NOT NULL,
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

### 4.1 Justificativa dos tipos

| Campo | Decisão |
|---|---|
| `id` | identificador SQL interno; nunca entra em DTO público |
| `citizenid` | `VARCHAR(32)` para coincidir com o schema real de `mz_players` e `mz_player_accounts` |
| `branch` | `CHAR(4)` para preservar zeros à esquerda |
| `account_number` | `CHAR(8)` para preservar zeros à esquerda e evitar coerção numérica |
| `check_digit` | `CHAR(1)`; somente dígito decimal nesta fase |
| `account_type` | `VARCHAR(24)` com allowlist server-side; somente `personal` |
| `status` | `VARCHAR(16)` com máquina de estados server-side |
| timestamps | criação, última atualização e encerramento explícito |
| `metadata_json` | `LONGTEXT` pela compatibilidade já adotada entre MySQL/MariaDB; JSON validado pelo serviço |

### 4.2 Constraints e invariantes

- `uq_mz_bank_accounts_owner_type` torna impossível criar duas contas pessoais para o mesmo `citizenid`.
- `uq_mz_bank_accounts_route` é mais forte que a unicidade mínima do roadmap em `(branch, account_number, check_digit)`: como o DV é determinístico, não pode existir o mesmo número com outro dígito.
- `check_digit` sempre deve corresponder ao cálculo do endereço.
- `closed_at` deve ser `NULL` fora de `closed` e preenchido ao entrar em `closed`.
- `metadata_json` não pode conter saldo, license, PIN, token, segredo de cartão ou cópia de dados pessoais.
- nenhuma atualização de estado pode apagar ou trocar `branch`, `account_number` ou `check_digit`.

Checks SQL para formato e enum somente deverão ser adicionados se a versão real de MySQL/MariaDB suportada for confirmada. Até lá, `NOT NULL`, índices únicos e validação server-side são o contrato portável. A migration não deve depender de um `CHECK` que algum ambiente ignore.

### 4.3 Foreign key

Não se propõe foreign key na primeira migration.

Motivos reais:

- o DDL atual de `mz_players` não fixa engine/charset/collation;
- a compatibilidade do banco implantado não foi provada;
- a tabela pertence a outro resource;
- `ON DELETE CASCADE` poderia apagar permanentemente um endereço bancário e permitir perda de auditoria.

A existência do titular será validada server-side contra `mz_players` no backfill e derivada do player autenticado na criação preguiçosa. Uma FK futura poderá ser avaliada apenas após versionamento compatível do schema do core; nunca deverá usar cascade para apagar contas.

## 5. Número da conta

### 5.1 Formato

- Agência padrão: `0001`.
- Número: oito dígitos decimais, de `00000001` a `99999999`.
- `00000000` é reservado e nunca será emitido.
- Dígito verificador: um dígito decimal.
- Apresentação completa ao titular: `0001 / 12345678-7`.
- Apresentação mascarada a terceiros: `0001 / ****5678-7`.

Todos os campos trafegam como strings. Conversão para número é proibida porque removeria zeros à esquerda.

### 5.2 Algoritmo do dígito verificador

Algoritmo proposto: módulo 11 sobre `branch .. account_number`.

1. concatenar os 4 dígitos da agência e os 8 da conta;
2. percorrer da direita para a esquerda;
3. aplicar pesos cíclicos `2, 3, 4, 5, 6, 7, 8, 9`;
4. somar os produtos;
5. calcular `candidate = 11 - (sum % 11)`;
6. se `candidate` for `10` ou `11`, usar `0`; caso contrário, usar `candidate`.

Vetor de teste:

```text
branch:         0001
account_number: 12345678
check_digit:    7
formatado:      0001 / 12345678-7
```

O DV detecta erros de digitação; ele não é autenticação nem proteção contra enumeração.

### 5.3 Geração e colisões

O número não será sequencial nem derivado de `id`, citizenid, license, telefone ou card UID.

Requisito de implementação:

- usar uma fonte criptograficamente segura de aleatoriedade confirmada no runtime;
- gerar por rejeição uniforme no intervalo de 1 a 99.999.999;
- nunca usar `math.random` como gerador definitivo da conta;
- se nenhuma primitiva segura for confirmada, o lote de geração fica bloqueado em vez de adotar fallback fraco.

Para cada candidato:

1. gerar oito dígitos;
2. calcular o DV;
3. tentar o insert protegido pelas duas constraints únicas;
4. se outra linha do mesmo titular/tipo já existir, relê-la e devolvê-la;
5. se o titular ainda não possuir conta, classificar como colisão de rota e gerar novo candidato;
6. limitar a dez tentativas por chamada;
7. após o limite, retornar erro estável `account_number_allocation_failed` e auditar.

Não será feito pre-check como única proteção: a constraint de banco resolve a corrida entre o check e o insert.

## 6. Estados da conta

Os estados controlam o uso do canal bancário no `mz_bank`; não alteram saldo no core.

| Estado | Leitura própria | Depósito/entrada | Saque/saída | Resolução como destino | Semântica |
|---|---:|---:|---:|---:|---|
| `active` | sim | sim | sim | sim | operação normal |
| `blocked` | sim | sim | não | sim | bloqueio do titular para saída; recebimentos permanecem permitidos |
| `frozen` | sim | não | não | não | congelamento total dos canais do banco; somente leitura própria |
| `closed` | não no fluxo normal | não | não | não | estado terminal; rota reservada para sempre |

Regras adicionais:

- `blocked` não equivale a cartão bloqueado; ambos devem ser validados separadamente;
- `frozen` e `closed` respondem a terceiros com o mesmo erro genérico de destinatário indisponível;
- `closed_at` é definido somente na transição para `closed`;
- `closed` não volta para outro estado nesta fase;
- mudanças de estado exigem superfície administrativa autenticada e auditada, fora da NUI pública;
- payroll, ação administrativa ou outro domínio que chame o `mz_core` diretamente não é automaticamente bloqueado por este status. Um bloqueio financeiro global exigiria contrato futuro no core.

Transições propostas:

```text
active  -> blocked | frozen | closed
blocked -> active  | frozen | closed
frozen  -> active  | blocked | closed
closed  -> nenhuma
```

## 7. Criação idempotente e concorrência

### 7.1 Contrato interno

`EnsurePersonalAccount` deverá receber identidade já derivada no servidor. A superfície client-facing recebe apenas token de sessão; nunca recebe `citizenid` para criação.

Resultado lógico:

```lua
{
  ok = true,
  created = false,
  account = <owner DTO>
}
```

### 7.2 Algoritmo transacional

1. validar serviço pronto e `citizenid` interno não vazio;
2. buscar `(citizenid, 'personal')`;
3. se existir, devolver a mesma conta, inclusive se estiver encerrada; o chamador aplica o estado;
4. gerar candidato e DV;
5. executar insert em transação curta;
6. em violação de unicidade, reler `(citizenid, 'personal')`;
7. se a conta do titular existir, devolver essa linha como sucesso idempotente;
8. caso contrário, tratar como colisão da rota e repetir com novo candidato;
9. não propagar mensagem SQL ou índice interno ao client.

A transação protege a unidade do insert e de qualquer auditoria local necessária; as constraints continuam sendo a garantia contra concorrência. Não se usará `INSERT IGNORE`, pois ele pode ocultar erro diferente de duplicidade.

### 7.3 Conta encerrada

Repetir `EnsurePersonalAccount` para um titular cuja conta está `closed` devolve a mesma identidade com `status = 'closed'`; não cria outra. O fluxo público retorna `account_closed`. Uma política de nova conta após encerramento exigiria outro modelo de cardinalidade e não faz parte desta fase.

## 8. Resolução segura do destinatário

### 8.1 Entrada aceita

Na Fase 2 o destinatário físico será somente:

```lua
{
  branch = '0001',
  accountNumber = '12345678',
  checkDigit = '7'
}
```

`accountType` não será escolhido livremente pelo client; o servidor fixa `personal`. Se um contrato futuro precisar do campo, ele deverá passar por allowlist de capacidades.

Validação antes da query:

- exatamente 4, 8 e 1 dígitos ASCII;
- nenhuma coerção de número;
- DV válido;
- sessão/capability autenticada;
- rate limit aprovado.

O client não envia `citizenid`, source de destino, account ID SQL, `recipientType` arbitrário ou card UID.

### 8.2 Fluxo de confirmação

1. NUI envia a rota completa para `ResolveTransferRecipient`.
2. Servidor valida sessão, formato, DV e rate limit.
3. Repository procura a rota exata e o tipo `personal`.
4. Servidor verifica se o estado permite recebimento.
5. Servidor resolve o nome atual internamente e impede autotransferência.
6. Servidor cria `resolutionToken` opaco, curto e associado a:
   - ator/citizenid remetente;
   - token/canal da sessão;
   - ID interno da conta alvo;
   - citizenid alvo;
   - rota normalizada;
   - expiração de 60 segundos.
7. NUI recebe somente confirmação mínima e mascarada.
8. Na confirmação, a NUI envia `resolutionToken`, valor e chave de idempotência.
9. Servidor revalida sessão, conta de origem, token e estado atual do alvo.
10. Servidor chama `TransferBankBetweenPlayers(source, targetCitizenid, amount, metadata)` usando o `citizenid` resolvido internamente.

Passar o `citizenid` interno estável ao core, em vez do source reciclável, também estabiliza o fingerprint de idempotência real do `mz_core`.

O token é invalidado após confirmação ou erro terminal. Em timeout ambíguo, o client pode resolver novamente e repetir a mesma chave idempotente; o core recuperará o resultado se o alvo interno e o payload forem os mesmos.

### 8.3 Destinatário offline

O serviço real do core exige o destinatário no cache online. A Fase 2 não mudará essa regra.

- conta pública válida com titular offline termina em erro genérico de destinatário indisponível;
- nenhuma escrita SQL direta no saldo do destinatário será criada;
- nenhuma fila ou transferência offline será adicionada;
- retry de uma operação já confirmada continua recuperável pela idempotência do core.

## 9. DTOs públicos

### 9.1 DTO próprio para NUI do banco

```lua
{
  branch = '0001',
  accountNumber = '12345678',
  checkDigit = '7',
  formatted = '0001 / 12345678-7',
  accountType = 'personal',
  accountTypeLabel = 'Conta pessoal',
  status = 'active'
}
```

É permitido mostrar a rota completa somente ao próprio titular em sessão autenticada.

### 9.2 DTO próprio para futuro aplicativo do telefone

O mesmo DTO próprio poderá ser usado pelo backend do `mz_phone`, desde que:

- o servidor do telefone apresente uma sessão/capability autenticada;
- o `mz_bank` derive o ator pelo source autenticado;
- a NUI do telefone não chame o `mz_core`;
- o telefone não envie citizenid livre.

Nenhuma integração phone é implementada na Fase 2 de desenho.

### 9.3 DTO de busca de destinatário

```lua
{
  found = true,
  resolutionToken = '<opaco>',
  recipient = {
    displayName = 'Joao S.',
    branch = '0001',
    accountMasked = '****5678-7',
    accountTypeLabel = 'Conta pessoal'
  },
  expiresIn = 60
}
```

O nome é confirmação parcial, não mecanismo de busca. Não existe pesquisa por nome.

### 9.4 DTO de comprovante

```lua
{
  correlationId = '<referencia oficial do core>',
  operation = 'transfer',
  status = 'confirmed',
  amount = 100,
  fee = 0,
  createdAt = '<timestamp>',
  sender = {
    displayName = 'Maria P.',
    branch = '0001',
    accountMasked = '****1234-5'
  },
  recipient = {
    displayName = 'Joao S.',
    branch = '0001',
    accountMasked = '****5678-7'
  }
}
```

O comprovante usa a referência oficial do core. Ele não cria ledger paralelo.

### 9.5 Campos proibidos em qualquer DTO público

- `citizenid`;
- license ou identificadores FiveM;
- source/server ID;
- `mz_bank_accounts.id`;
- `mz_player_accounts.id`;
- `card_uid`, owner metadata, PIN/hash ou instance UID;
- `metadata_json`;
- saldo de terceiros;
- estado interno detalhado de conta de terceiros;
- stack trace, SQL ou nome de constraint.

## 10. Privacidade, enumeração e abuso

### 10.1 Superfície mínima

- nenhuma listagem pública de contas;
- nenhuma busca por nome, telefone, prefixo ou últimos dígitos;
- somente lookup exato por agência, número e DV;
- resposta igual para formato válido inexistente, conta frozen/closed e titular indisponível;
- nenhuma distinção pública entre conta inexistente, encerrada ou congelada;
- somente o titular recebe o estado real da própria conta.

### 10.2 Rate limit proposto

Aplicar no servidor, cumulativamente:

- máximo de 5 resoluções por 60 segundos por citizenid/sessão;
- máximo de 20 resoluções por hora por citizenid;
- cooldown progressivo após falhas consecutivas;
- uma operação de transferência simultânea por sessão, preservando o lock atual;
- limites independentes para ATM, agência e futuro phone.

O contador curto pode ser em memória, mas seu reset em restart deve ser documentado. Tentativas e bloqueios serão auditados persistentemente pelo contrato real `mz_core:CreateDetailedLog`, sem registrar tokens completos ou expor dados no client.

### 10.3 Auditoria

Eventos mínimos:

- resolução aceita;
- resolução negada por formato/DV;
- resolução indisponível;
- rate limit;
- autotransferência;
- token expirado/adulterado;
- estado que bloqueou operação;
- transferência confirmada/replayed com `correlationId`.

Logs internos podem correlacionar citizenids, mas painéis e evidências públicas devem redigir esses campos. O nome completo e a rota completa de terceiros não devem ser gravados desnecessariamente.

## 11. Backfill de jogadores existentes

### 11.1 Estratégia

A estratégia oficial combina:

1. criação preguiçosa no primeiro acesso bancário autenticado;
2. comando administrativo de backfill para antecipar a cobertura antes do cutover da transferência.

Não se propõe hook automático no login nesta fase, evitando acoplamento adicional do `mz_core` com o banco. Um jogador sem acesso prévio recebe a conta no primeiro uso legítimo.

### 11.2 Comando administrativo proposto

Contrato conceitual:

```text
mz_bank_accounts_backfill preview <batch_size> <after_player_id>
mz_bank_accounts_backfill apply <run_ref> <batch_size> <after_player_id> <confirmation>
```

Regras:

- ACE dedicada, por exemplo `mz_bank.accounts.backfill`;
- preview obrigatório;
- batch padrão `100`, máximo `500`;
- paginação estável por `mz_players.id` crescente;
- somente leitura de `id` e `citizenid` de `mz_players`;
- não ler ou escrever `wallet`, `bank` ou `dirty`;
- usar a mesma função idempotente da criação preguiçosa;
- continuar o lote após erro individual controlado;
- retornar cursor, total lido, existentes, criadas, fechadas, colisões recuperadas e falhas;
- persistir resumo agregado por `CreateDetailedLog` com `run_ref` e cursor;
- não imprimir lista de citizenids ou números completos no console;
- falha/restart permite repetir o mesmo batch sem duplicar contas.

Cada conta é confirmada em transação curta própria. Não se recomenda uma única transação para centenas de jogadores, pois ampliaria locks e rollback.

### 11.3 Tratamento de falha

- erro de conexão/schema interrompe o lote e mantém cursor anterior;
- colisão de rota executa retry até o limite;
- corrida com lazy creation relê e classifica como existente;
- conta já `closed` é contabilizada, não substituída;
- falha individual é agregada por código e pode ser repetida em novo lote;
- relatório final informa zero alterações de saldo.

## 12. Migration, readiness e rollback

### 12.1 Migration futura

Próxima versão proposta:

```text
003_mz_bank_accounts.sql
```

Quando autorizada, a implementação deverá:

- elevar `EXPECTED_VERSION` de `2` para `3`;
- registrar a versão `3` na lista do runner;
- adicionar `mz_bank_accounts` ao `expectedSchemas`;
- validar engine, charset, colunas, comprimentos, auto increment e índices;
- validar a versão antes de liberar criação, resolução ou overview;
- manter o banco indisponível com erro explícito se o schema divergir;
- manter uma única fonte de DDL no arquivo SQL;
- não incluir `DROP`, `TRUNCATE`, `DELETE` ou alteração de saldo.

### 12.2 Aplicação idempotente

O padrão atual será preservado:

- `CREATE TABLE IF NOT EXISTS`;
- verificação do objeto antes de registrar a versão;
- `INSERT IGNORE` somente no registry de migration, não na criação de conta;
- reexecução valida o schema existente;
- conflito de nome/versão falha fechado.

### 12.3 Rollback seguro

A migration é aditiva e não terá down migration destrutiva. Rollback funcional significa desativar a feature e manter a tabela.

Limitação real: o runner atual da versão 2 recusa um banco cuja versão seja maior que `EXPECTED_VERSION`. Depois de aplicar a versão 3, voltar ao pacote atual v2 deixaria o `mz_bank` indisponível com `schema_newer_than_resource`.

Plano operacional obrigatório:

1. backup antes da migration;
2. deploy em staging com feature de conta pública desligada;
3. aplicar/validar schema v3;
4. manter como artefato de rollback um pacote compatível com schema v3 e feature desligada;
5. habilitar criação/backfill/resolução em lotes posteriores;
6. em rollback, desabilitar a feature sem remover tabela ou dados;
7. nunca reutilizar o `mz_bank.zip` atual como rollback após v3, pois ele está defasado e espera schema v2.

## 13. Contratos de serviço propostos

Estes nomes são propostas; não são exports existentes.

### 13.1 Internos do domínio

```lua
EnsurePersonalAccount(internalIdentity)
GetAccountByOwner(citizenid, accountType)
GetAccountByRoute(branch, accountNumber, checkDigit, accountType)
CalculateCheckDigit(branch, accountNumber)
CanAccountPerform(status, capability)
```

Funções que recebem `citizenid` ficam internas ao servidor/repository e não são callbacks client-facing.

### 13.2 Superfície autenticada do banco

```lua
GetOwnPublicAccount(source, context)
ResolveTransferRecipient(source, publicRoute, context)
TransferByPublicAccount(source, resolutionToken, amount, context)
```

Regras:

- `source` vem do runtime/export server-side, nunca do payload da NUI;
- `context.token` ou capability identifica canal e sessão;
- `TransferByPublicAccount` continua usando os limites, taxa e idempotência atuais;
- retorno financeiro continua separado do refresh;
- referência é sempre a do `mz_core`.

### 13.3 Compatibilidade de API

Não há consumidor executável externo do export atual `ResolveRecipient` encontrado no workspace. Mesmo assim, a troca não deverá aceitar dois formatos ambíguos no mesmo campo.

Estratégia:

- criar contratos internos versionados durante staging;
- atualizar callback/NUI juntos no lote de cutover;
- não interpretar um número curto como server ID quando o modo público estiver ativo;
- remover o texto “ID de destino” e o fallback `targetId` da NUI final;
- server ID pode existir apenas atrás de feature flag de staging durante a transição;
- a Fase 2 só poderá ser considerada concluída quando o server ID deixar de ser destino definitivo.

## 14. Integrações futuras

### ATM e agência

- overview mostra a conta própria completa;
- transferência usa rota pública e confirmação mascarada;
- sessão física, distância, cartão, animação e slot permanecem inalterados;
- estado da conta adiciona capacidade, mas não substitui a validação do cartão.

### Transferência

- conta pública resolve o target internamente;
- `mz_core` continua debitando/creditando e mantendo locks;
- destino permanece online nesta fase;
- metadata pode carregar somente rota mascarada/ID público não sensível para comprovante, nunca saldo paralelo.

### Comprovante

- usa `correlationId` oficial;
- mostra nomes parciais e rotas mascaradas;
- não usa transaction ID interno nem citizenid.

### Cartão

- cartão continua credencial sem saldo;
- titular continua validado por citizenid server-side;
- não é necessário copiar o número público para metadata do item;
- bloqueio do cartão e estado da conta são gates independentes.

### `mz_phone`

- backend do phone chama API server-to-server do `mz_bank`;
- `mz_bank` valida sessão/capability do canal phone;
- NUI do phone não chama `mz_core` e não envia citizenid;
- nenhuma implementação de phone pertence a este lote.

### Conta organizacional

- poderá reutilizar o conceito de rota e DTO;
- não poderá usar saldo pessoal nem `citizenid` fictício;
- exige primeiro a decisão do domínio oficial do saldo da organização;
- provavelmente exigirá owner model ou tabela própria e migration futura.

## 15. Alternativas descartadas

| Alternativa | Motivo da rejeição |
|---|---|
| server ID como conta | transitório, reciclável, somente online e enumerável |
| citizenid público | expõe identificador interno e viola o roadmap |
| license, telefone ou card UID como número | dados sensíveis/mutáveis ou credencial, não identidade bancária |
| número derivado do citizenid/license | reversível/correlacionável e previsível |
| auto increment exibido | enumeração trivial |
| `math.random` definitivo | aleatoriedade não adequada para um endereço público não sequencial |
| saldo em `mz_bank_accounts` | criaria fonte paralela e quebraria o core |
| lookup por nome/prefixo | facilita enumeração e exposição de dados pessoais |
| tipo de destinatário livre | reabre a superfície removida em B0-09 |
| `INSERT IGNORE` para criar conta | pode esconder erro que não seja colisão |
| reutilizar número encerrado | quebra histórico, comprovantes e segurança de roteamento |
| múltiplas contas pessoais agora | amplia cardinalidade, seleção de conta e semântica de saldo sem necessidade |
| FK com cascade | compatibilidade não provada e risco de apagar identidade/auditoria |
| transferência offline no banco | contornaria cache/locks/contrato atual do core |
| phone chamando `mz_core` | duplica autenticação e regra financeira fora do banco |

## 16. Riscos e controles

| Risco | Impacto | Controle proposto |
|---|---|---|
| RNG seguro não disponível | números previsíveis | bloquear implementação até confirmar primitiva segura |
| corrida entre lazy creation e backfill | duplicidade | constraints únicas, transação, reler titular e retry |
| colisão no espaço de 8 dígitos | falha de criação | retry limitado e telemetria; avaliar expansão antes de saturação |
| ausência de FK | linha órfã por ação administrativa externa | criação só com identidade real, auditoria e verificação de integridade |
| enumeração | descoberta de nomes/contas | lookup exato, DV, rate limit, resposta mínima e auditoria |
| nome alterado | comprovante inconsistente | buscar nome atual para confirmação; snapshot apenas no comprovante/ledger oficial quando existir |
| status interpretado como hold global | operações externas ainda afetam saldo | documentar que o gate é do `mz_bank`; hold global pertence ao core |
| rollback para pacote v2 | banco fica fail-closed após schema v3 | artefato de rollback compatível com v3 e feature flag desligada |
| backfill pesado | carga no MySQL | batches pequenos, cursor, pausa e transação por conta |
| token de resolução roubado | transferência para alvo vinculado | token opaco, curto, ligado a ator/sessão/rota e revalidação |
| source reciclado | alvo incorreto/idempotência conflitante | passar citizenid interno estável ao core |
| artefato ZIP defasado | deploy/rollback incorreto | não tratá-lo como fonte; regenerar somente na implementação autorizada |

## 17. Testes estáticos planejados

### Schema e migration

- uma única definição de `mz_bank_accounts`;
- migration v3 idempotente e readiness fail-closed;
- tipos, comprimentos, índices, engine e charset conferidos;
- ausência de coluna de saldo;
- ausência de FK incompatível/cascade;
- ausência de `DROP`, `TRUNCATE`, `DELETE` e escrita em `mz_player_accounts`.

### Geração e cardinalidade

- vetores do módulo 11, incluindo zeros à esquerda;
- formatos inválidos e DV incorreto negados;
- `00000000` negado;
- mesma identidade retorna a mesma conta;
- corrida cria uma linha;
- colisão de rota gera retry;
- conta closed não gera substituta;
- somente `personal` é aceito.

### Segurança e DTO

- callbacks não recebem `source`, `citizenid`, account ID ou recipient type livre;
- DTOs não contêm citizenid, license, source, card UID ou metadata;
- não existe endpoint de listagem/prefixo/nome;
- estados aplicam a matriz definida;
- token é ligado ao ator e sessão, expira e não funciona para outro jogador;
- respostas de alvo inexistente/frozen/closed são equivalentes;
- rate limits não são controlados pelo client.

### Integração financeira

- transferência chama somente `TransferBankBetweenPlayers`;
- target passado ao core é o citizenid resolvido server-side;
- idempotency key e correlationId oficiais são preservados;
- nenhum saldo paralelo, ledger próprio ou transferência offline;
- server ID e `targetId` desaparecem do fluxo final;
- phone não chama diretamente o core.

## 18. Testes runtime planejados

### RT-P2-MIG

- banco limpo, banco com v2 e restart repetido;
- concorrência de startup;
- schema divergente mantém readiness falso;
- feature desligada após migration preserva operação atual;
- rollback funcional usa pacote compatível com v3 sem apagar tabela.

### RT-P2-CREATE

- primeiro overview cria uma conta;
- refresh/reconnect/restart devolvem a mesma conta;
- duas chamadas concorrentes criam uma linha;
- lazy creation concorrente com backfill não duplica;
- colisão injetada executa retry;
- falha SQL não deixa linha parcial;
- personagens com citizenids diferentes recebem rotas diferentes.

### RT-P2-STATE

- active permite todos os fluxos atuais;
- blocked permite leitura/entrada e nega saída;
- frozen permite somente leitura própria e não resolve como destino;
- closed nega fluxo normal, permanece reservado e não é recriado;
- cartão ativo não contorna status da conta;
- desbloqueio não altera saldo nem número.

### RT-P2-RESOLVE

- rota válida mostra nome parcial e conta mascarada;
- agência, conta ou DV inválidos são negados;
- alvo inexistente/frozen/closed produz resposta pública equivalente;
- self transfer é negada;
- token falso, expirado, de outra sessão ou jogador é negado;
- 5/60 s e 20/h são aplicados;
- tentativa de enumeração é auditada sem vazar dados.

### RT-P2-TRANSFER

- depósito e saque continuam inalterados;
- transferência por conta pública debita/credita uma vez;
- mesmo idempotency key recupera a mesma `correlationId`;
- destinatário offline é negado sem alteração;
- source/server ID não funciona como conta;
- concorrência, disconnect, timeout e restart preservam as invariantes da Fase 1;
- saldo/cache/persistência continuam exclusivamente no core;
- comprovante não expõe identificadores internos.

### RT-P2-BACKFILL

- preview não cria conta;
- apply em lotes respeita cursor e limite;
- repetir batch é idempotente;
- restart no meio permite retomada;
- falha individual é reportada sem perder sucessos anteriores;
- relatório agregado fica persistido;
- comparação antes/depois confirma zero alteração em wallet/bank/dirty.

## 19. Plano de implementação em pequenos lotes

Cada lote exige revisão antes do seguinte. Nenhum deles foi executado nesta etapa.

### Lote P2-A — Contrato e feature flags

- documentar formatos, estados, erros e capacidades;
- adicionar configurações server-side propostas com feature desligada;
- confirmar e testar a primitiva de RNG seguro;
- nenhuma mudança de transferência.

### Lote P2-B — Migration e readiness

- criar `003_mz_bank_accounts.sql`;
- elevar/validar schema v3;
- adicionar repository somente de identidade;
- manter feature pública desligada;
- validar fresh install, upgrade e rollback funcional.

### Lote P2-C — Criação e DTO próprio

- implementar DV e geração;
- implementar criação idempotente;
- integrar ao overview autenticado;
- exibir a conta própria sem alterar transferências;
- testar concorrência, restart e estados.

### Lote P2-D — Backfill controlado

- preview, ACE, confirmação e batches;
- cursor, relatório agregado e retomada;
- executar primeiro em staging;
- conferir explicitamente zero alteração de saldo.

### Lote P2-E — Resolução privada

- lookup exato, rate limits e auditoria;
- DTO mínimo e `resolutionToken`;
- sem movimentação financeira ainda;
- revisão de enumeração e abuso.

### Lote P2-F — Transferência por conta pública

- revalidar origem/alvo e token;
- chamar o core com citizenid interno estável;
- preservar limites, taxa, idempotência e resposta confirmada;
- manter destino online;
- validar replay, concorrência e falhas.

### Lote P2-G — Cutover da NUI

- trocar o campo de server ID por agência/conta/DV;
- adicionar etapa de confirmação do destinatário;
- remover `targetId`/server ID do contrato final;
- preservar animação, alinhamento, slot e aparência atual;
- validar DTOs e comprovante.

### Lote P2-H — Revisão e decisão

- revisão estática independente;
- checklist runtime completo;
- backfill em staging;
- regressão integral da Fase 1;
- somente então decidir `[S]` e, depois, `[R]` para a Fase 2.

## 20. Gates de compatibilidade

A Fase 2 não pode ser aprovada se qualquer item abaixo falhar:

- `mz_bank_accounts` contém ou deriva saldo;
- NUI envia/recebe citizenid, license, source ou IDs internos;
- server ID continua sendo conta definitiva;
- criação concorrente produz duplicidade;
- número closed é reutilizado;
- resolver permite listagem ou enumeração prática;
- transferência contorna `TransferBankBetweenPlayers`;
- destino offline é creditado diretamente por SQL;
- phone chama o `mz_core` diretamente;
- schema v3 não possui caminho de rollback funcional sem perda de dados;
- animação, NUI, slot, sessões, cartões ou invariantes financeiras regridem.

## 21. Decisão desta revisão

O desenho recomendado é:

```text
uma conta pessoal vitalícia por citizenid
agência 0001
número aleatório de 8 dígitos
DV módulo 11
rota nunca reutilizada
resolução exata e server-side
DTO mínimo e mascarado para terceiros
transferência online pelo serviço oficial do mz_core
zero saldo no mz_bank_accounts
```

Estado registrado:

```text
Fase 2: [ ] Não iniciada
Revisão de desenho: CONCLUÍDA
Implementação: NÃO INICIADA
Migration 003: NÃO CRIADA
Runtime: NÃO EXECUTADO
```

Este relatório não implementa, não aprova estaticamente e não concede aprovação runtime à Fase 2.
