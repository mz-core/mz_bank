# MZ Bank — Phase 0 Current State

Data da análise estática: 2026-07-15  
Escopo: estado real dos arquivos em `D:\git-hub\repo_oficial`  
Status de runtime: **não executado e não aprovado**

## 1. Escopo e método

Este relatório é um inventário estático da implementação atual. Foram lidos:

- `BANK_ROADMAP.md` e todos os arquivos atuais de `mz_bank`;
- as definições reais dos exports, serviços, repositórios, schemas e estados de readiness usados em `mz_core`;
- os contratos reais de ledger e extrato usados em `mz_economy`;
- o papel real de `mz_inventory` e os contratos de inventário que, na implementação atual, pertencem a `mz_core`;
- a ordem efetiva declarada em `mz_starter/server.cfg` e `mz_starter/cfg/resources.cfg`;
- referências reais entre `mz_bank` e `mz_phone`.

Não foi usado Git ou histórico como fonte. Nenhum teste FiveM/MySQL foi executado. Nenhum arquivo de código, configuração, SQL ou NUI foi alterado nesta etapa; o único arquivo criado é este relatório.

## 2. Diagnóstico executivo

O `mz_bank` não mantém saldo paralelo. As fontes efetivas continuam sendo `player.money.wallet`, `player.money.bank` e a persistência `mz_player_accounts` do `mz_core`. Saque e depósito usam a transferência canônica entre contas do próprio jogador; transferência entre jogadores usa a operação canônica e transacional do core. O extrato vem de `mz_economy` e é tratado como best effort.

A base atual, contudo, não satisfaz integralmente os bloqueadores da Fase 0 descritos no roadmap. Os principais pontos encontrados são:

1. callbacks físicos ainda aceitam canal informado pelo client e conseguem alcançar o caminho `phone`;
2. a abertura de ATM aceita qualquer coordenada próxima ao ped, sem catálogo/allowlist server-side que comprove o ATM;
3. o cartão é validado somente na autenticação, não antes de cada operação sensível;
4. morte e veículo são controlados no client, mas não são negados pelo servidor;
5. valores decimais são truncados por `math.floor`, em vez de rejeitados;
6. saque, depósito e transferência física retornam o resultado de um overview posterior; uma falha após o commit pode produzir resposta ambígua;
7. não há idempotência persistente nem recuperação de resultado por chave;
8. `mz_bank_cards` possui duas fontes de criação de schema: SQL versionado e `repository.prepare()`;
9. o arquivo efetivo de resources não inicia `mz_economy` nem `mz_bank`;
10. a aplicação do legado tem proteções básicas, mas não bloqueia duplicidades/conflitos com relatório persistente.

A NUI, a animação do ATM e os estados amarelo/verde/vermelho do slot estão implementados e conectados estaticamente. Isso não constitui aprovação de runtime.

## 3. Arquitetura e fontes de verdade confirmadas

### 3.1 Saldo e identidade

| Responsabilidade | Fonte real | Evidência principal |
|---|---|---|
| Jogador carregado e `citizenid` | cache `MZCache.playersBySource` / `MZCache.playersByCitizenId` | `mz_core/server/player/service.lua` |
| Estrutura em memória | `player.money.wallet`, `player.money.bank`, `player.money.dirty` | `buildPlayerData()` em `mz_core/server/player/service.lua` |
| Persistência pessoal | `mz_player_accounts` | `mz_core/server/prepare.lua` e `server/accounts/repository.lua` |
| Tipos numéricos de saldo | `BIGINT` | `wallet`, `bank` e `dirty` no schema do core |
| Locks financeiros | `AccountLocks` por `citizenid` | `mz_core/server/accounts/service.lua` |
| Extrato/ledger | `mz_economy_transactions` | `mz_economy/server/prepare.lua` |
| Credencial de cartão | `mz_bank_cards` + item `bank_card` | `mz_bank/server/repository.lua` e inventário do core |

Não há escrita normal de saldo pelo `mz_bank`. A única escrita direta em `mz_player_accounts` dentro do resource está no comando legado deliberado `mz_bank_legacy_apply`, desativado por padrão.

### 3.2 Inventário

`mz_inventory` é um resource client/NUI consumidor. Ele não possui servidor nem exports server-side usados pelo banco. Os contratos reais usados para cartões estão em `mz_core`:

- `GetPlayerInventory`;
- `AddPlayerItem`;
- `RegisterItemUseHandler`.

O item `bank_card` está definido em `mz_core/shared/items.lua` como único, não empilhável, utilizável, vinculado ao recebedor e com serial gerado. Ao adicionar o item, o serviço do core também gera `uid`, `serial`, `owner` e `bound`, preservando a metadata enviada pelo banco (`ownerCitizenId`, `cardUid`, `last4`, `issuedAt`, `schemaVersion`).

A imagem `mz_inventory/web/images/bank_card.png` existe. Porém, a fonte local está comentada em `mz_inventory/web/script.js`; a lista ativa de candidatos usa o servidor remoto configurado. Logo, a presença do PNG local não prova que ele é a imagem efetivamente renderizada no runtime atual.

## 4. Fluxo de abertura física até a NUI

### 4.1 Descoberta e interação no client

Existem dois caminhos:

1. `mz_interact`:
   - `client/interact.lua` registra as agências configuradas via `exports['mz_interact']:AddPoint`;
   - ATMs são descobertos no client por `GetClosestObjectOfType` usando os quatro modelos de `Config.ATM.models`;
   - o evento configurado é `mz_bank:client:openPoint(channel, x, y, z)`.
2. fallback manual:
   - `client/main.lua` procura agência ou ATM próximo;
   - desenha marcador/ajuda;
   - a tecla configurada chama `openBank(currentPoint)`.

O client impede a abertura se o ped estiver morto ou em veículo. Essa checagem é de UX e pode ser removida por um client modificado.

### 4.2 Criação da sessão server-side

`openBank()` chama o callback:

```text
mz_bank:server:openSession
```

Payload enviado pelo client:

```lua
{
  channel = point.channel,
  coords = { x = ..., y = ..., z = ... }
}
```

O servidor executa `MZBankService.OpenSession`:

1. exige o booleano local `ready`;
2. aplica rate limit de abertura;
3. resolve/carrega o player pelo `mz_core`;
4. chama `resolvePhysicalContext`;
5. opcionalmente tenta emitir o primeiro cartão na agência;
6. cria uma sessão em memória em `Sessions[source]` com token, `citizenid`, canal, coordenada, expiração, autenticação e busy flag;
7. devolve token, canal, estado de autenticação, moeda e nome do banco.

A sessão não é persistida em tabela. Ela é removida em fechamento, expiração periódica, `playerDropped` e stop do resource.

### 4.3 Validação física atual

Agência:

- o canal e a coordenada vêm do client;
- a coordenada solicitada precisa ficar até `0.75` da agência configurada;
- o ped server-side precisa estar dentro de `max(radius + 0.5, ServerValidationDistance)`; com a configuração atual, o limite efetivo é `7.5`.

ATM:

- o servidor somente verifica se a coordenada informada está até `ServerValidationDistance` do ped;
- não consulta entidade, modelo, catálogo ou allowlist server-side;
- portanto, uma coordenada arbitrária próxima ao jogador é aceita como ATM.

Durante a sessão, `validateSession` confirma token, expiração, mesmo `citizenid` e distância até a coordenada gravada. Há tolerância inicial de 2 segundos e tolerância de 3 segundos para indisponibilidade momentânea do ped. O servidor não verifica morte nem veículo.

### 4.4 Autenticação, overview e abertura visual

Agência, na configuração atual, não exige cartão. A sessão nasce autenticada. O client chama `authenticate` imediatamente para obter o overview antes de abrir a NUI.

ATM exige cartão. A NUI abre na tela `welcome`, com slot amarelo, e o clique/Enter chama o callback NUI `authenticate`, que encaminha o token ao servidor. O servidor:

1. valida a sessão sem exigir autenticação anterior;
2. lê o inventário oficial pelo core;
3. procura `bank_card` pertencente ao `citizenid` da sessão;
4. obtém `cardUid` da metadata;
5. consulta `mz_bank_cards`;
6. exige credencial `active` e mesmo titular;
7. grava `session.cardUid` e marca a sessão autenticada;
8. retorna `GetAccountOverview`.

O overview lê `bank` e `wallet` do cache do core, tenta buscar o extrato do `mz_economy` e devolve à NUI:

- `balance`;
- `cash`;
- nome do personagem;
- `account`, que hoje é uma máscara derivada do `citizenid`;
- extrato normalizado;
- `statementError` quando o ledger está indisponível;
- símbolo da moeda.

### 4.5 Abertura da NUI

O client aplica foco e envia `SendNUIMessage({ action = 'open', ... })`. `html/script.js` decide entre `welcome` e `menu`, renderiza saldo/extrato e gerencia as ações `authenticate`, `refresh`, `withdraw`, `deposit`, `transfer` e `close`.

## 5. Saque, depósito e transferência

### 5.1 Contrato de valor atual

`validateAmount` usa:

```lua
amount = math.floor(tonumber(amount) or 0)
```

Depois exige valor positivo e até `Config.MaxTransaction` (`1.000.000`). Consequências:

- zero, negativo e texto não numérico são negados;
- decimais numéricos ou strings decimais são aceitos e truncados;
- não há limite diário;
- a NUI produz inteiros via teclado e `parseInt`, mas o servidor não pode depender disso;
- o core também normaliza várias operações com `math.floor`;
- o schema oficial usa `BIGINT`, mas o limite do banco é muito menor que o máximo do schema.

### 5.2 Saque

Fluxo:

```text
NUI withdraw
-> RegisterNUICallback('withdraw')
-> mz_bank:server:withdraw
-> MZBankService.Withdraw
-> runOperation(session)
-> mz_core:TransferMoneyBetweenAccounts(bank, wallet)
```

O core adquire lock por `citizenid`, valida saldo, atualiza as duas colunas em um único `UPDATE`, atualiza o cache somente depois da persistência e devolve `transactionRef`.

Após o sucesso, o banco grava log e chama `GetAccountOverview`. A resposta final enviada ao client é o objeto do overview, não um DTO separado do resultado financeiro. O `transactionRef` confirmado não é devolvido no caminho físico.

### 5.3 Depósito

É simétrico ao saque:

```text
wallet -> bank
```

Usa o mesmo lock, persistência conjunta e atualização de cache do core. Também substitui o resultado financeiro pelo overview posterior.

### 5.4 Transferência física

A NUI atual solicita server ID. O client monta:

```lua
{
  recipientType = 'server_id',
  recipientValue = valor_da_nui,
  amount = valor_da_nui,
  channel = sessionChannel
}
```

O callback server-side repassa `recipientType`, `recipientValue` e `channel` para `MZBankService.Transfer`. `ResolveRecipient` aceita atualmente:

- `server_id`;
- `citizenid`.

O alvo precisa estar online, com player carregado, e não pode ser o remetente. A transferência canônica do core:

- resolve os dois players em cache;
- adquire locks pelos dois `citizenid` em ordem ordenada;
- debita `amount + fee` do remetente;
- credita `amount` ao destinatário;
- persiste as duas pontas em `MySQL.transaction.await`;
- atualiza ambos os caches somente após commit;
- retorna `transactionRef`, saldos e taxa.

O banco notifica o destinatário e, no caminho físico, novamente devolve um overview posterior em vez do resultado confirmado.

### 5.5 Taxa e ledger

`TransferFeePercent` é `0` atualmente. A taxa é calculada com `math.floor(amount * percentual / 100)`. Se configurada acima de zero, ela é removida do remetente e registrada em metadata, mas não existe uma conta de destino da taxa nesse fluxo.

O `mz_core` envia alterações ao `mz_economy` depois do commit de saldo. Esse registro é best effort:

- se `mz_economy` estiver parado, a operação financeira continua;
- se o insert no ledger falhar, o saldo não é revertido;
- não existe outbox;
- remetente e destinatário usam o mesmo `external_ref`, mas recebem `transaction_id` distintos no ledger;
- `external_ref` não possui constraint única;
- não há garantia persistente de recuperação do evento.

### 5.6 Concorrência e retry

Há duas proteções em memória:

- rate limit por source;
- `session.busy` para operação física e `PhoneBusy[source]` para phone.

Elas reduzem clique duplo simultâneo, mas não implementam idempotência. Após timeout, fechamento, reconnect ou restart, reenviar a mesma intenção pode movimentar saldo novamente. Não existe `idempotencyKey`, tabela de resultados ou `GetOperationResult`.

## 6. Ciclo atual do cartão

### 6.1 Emissão inicial

Na primeira abertura de agência, se não houver cartão ativo e `AutoIssueOnFirstBranchVisit` estiver habilitado, `issueCard(false)`:

1. verifica a contagem de cartões ativos;
2. cobra taxa via `RemoveMoney` se configurada;
3. gera `cardUid` e `last4`;
4. insere a credencial ativa em `mz_bank_cards`;
5. adiciona o item pelo inventário do core;
6. em falha de entrega, revoga a credencial e tenta devolver a taxa.

A falha de emissão não impede a abertura da agência; ela é devolvida apenas como `issueMessage/issueOk`.

Não existe transação única entre cobrança, credencial e inventário. Não há lock/idempotência de emissão. Uma exceção SQL durante o insert pode interromper o fluxo antes do rollback explícito da taxa.

### 6.2 Autenticação

A autenticação confere item, titular da metadata, existência da credencial, titular da credencial e status. Estados tratados:

- `active`: aceita;
- `blocked`: retorna `card_blocked`;
- qualquer outro estado, inclusive `revoked`: retorna `card_invalid`.

O PIN não está implementado. `pin_hash` existe como coluna nullable; se `RequirePinAtATM` for ligado, o acesso retorna `pin_unavailable`.

### 6.3 Bloqueio

`BlockCard(source, cardUid)` é um export server-side. Ele resolve o titular pelo source e atualiza apenas um cartão `active` desse titular para `blocked`.

Não há callback/NUI atual de gerenciamento de cartões. O bloqueio não procura nem invalida sessões cujo `session.cardUid` corresponda ao cartão.

### 6.4 Substituição

`RequestReplacementCard(source, context)` exige `context.channel == 'branch'`, token e sessão autenticada. Emite a nova credencial/item e só depois revoga outros cartões ativos quando configurado. Essa ordem preserva o cartão anterior se a entrega falhar.

Limitações atuais:

- sem lock ou idempotência, substituições concorrentes podem competir;
- `MaxActiveCards` não é imposto ao caminho `replacement` antes da emissão;
- a regra de máximo ativo depende de contagem em aplicação, sem constraint de cardinalidade por titular;
- sessões autenticadas com cartão antigo não são invalidadas;
- item antigo não é removido do inventário;
- não há rotina de reconciliação credencial/item.

### 6.5 Revalidação ausente

Depois de `Authenticate`, `runOperation` só valida token, expiração, identidade, distância, autenticação e permissão do canal. Não volta a consultar:

- item físico presente;
- `session.cardUid`;
- status atual da credencial;
- titular atual da instância.

Assim, bloquear/revogar/substituir o cartão ou remover o item durante a sessão não impede automaticamente a próxima operação.

## 7. Sessões e canais

### 7.1 ATM

- sessão física em memória;
- token vinculado ao `source` pela chave `Sessions[source]` e ao `citizenid` armazenado;
- autenticação por cartão quando configurada;
- saque, depósito, transferência, overview e extrato permitidos;
- distância revalidada;
- ATM real não comprovado server-side;
- morte/veículo não revalidados no servidor;
- cartão não revalidado após autenticação.

### 7.2 Agência

- ponto comparado com `Config.Branches` no servidor;
- cartão não é exigido por padrão;
- sessão nasce autenticada;
- pode tentar autoemissão no primeiro acesso;
- mesmas operações financeiras do ATM;
- substituição só existe por export, não na NUI atual.

### 7.3 Phone

Não há integração real de `mz_phone` com `mz_bank`: a busca em `mz_phone` não encontrou chamada a exports do banco. Não existe sessão bancária vinculada a aparelho, capability, token de phone ou validação do invocador.

Apesar disso, o serviço atual contém um caminho `phone` ativo:

- `GetAccountOverview`, `GetStatement` e `Transfer` assumem `phone` quando `context.channel` está ausente;
- o canal `phone` evita `validateSession` física;
- `Transfer` usa apenas `PhoneBusy` e o player carregado;
- `GetCards` e `BlockCard` não exigem contexto de canal;
- qualquer resource server-side capaz de chamar os exports pode informar `phone`; não há allowlist/capability de invocador.

Mais grave para a superfície client-facing:

- o callback `overview` recebe `channel` do client;
- o callback `transfer` recebe `payload.channel` do client;
- informar `phone` desvia para o caminho sem sessão física;
- o token enviado junto deixa de ser validado nesse caminho.

Portanto, phone está simultaneamente **não integrado** como produto e **alcançável indevidamente** como caminho de serviço.

## 8. Callbacks, eventos e exports atuais

### 8.1 Callbacks client-facing de `mz_bank`

| Nome | Entrada relevante | Serviço |
|---|---|---|
| `mz_bank:server:openSession` | payload com canal e coordenadas | `OpenSession` |
| `mz_bank:server:authenticate` | token | `Authenticate` |
| `mz_bank:server:overview` | token e canal | `Refresh` |
| `mz_bank:server:withdraw` | token e amount | `Withdraw` |
| `mz_bank:server:deposit` | token e amount | `Deposit` |
| `mz_bank:server:transfer` | token, recipientType, recipientValue, amount e channel | `Transfer` |

### 8.2 Eventos de rede de `mz_bank`

| Nome | Direção | Papel |
|---|---|---|
| `mz_bank:client:openPoint` | client local/evento client | inicia abertura em ponto informado |
| `mz_bank:client:notify` | server -> client | notificação |
| `mz_bank:server:closeSession` | client -> server | encerra a sessão do próprio source |

Também há handlers locais para `playerDropped`, `onResourceStop`, `onClientResourceStart` e `onClientResourceStop`.

### 8.3 Exports server-side existentes em `mz_bank`

| Export | Existe | Observação |
|---|---:|---|
| `GetAccountOverview` | sim | contexto ausente assume phone |
| `GetStatement` | sim | nome difere de `GetAccountStatement` do roadmap |
| `ResolveRecipient` | sim | aceita `server_id` e `citizenid`; retorna source e citizenid no DTO server-side |
| `Transfer` | sim | contexto ausente assume phone |
| `GetCards` | sim | sem autenticação de canal |
| `BlockCard` | sim | sem autenticação de canal/sessão |
| `RequestReplacementCard` | sim | exige branch/token dentro do serviço |

### 8.4 Contratos confirmados em `mz_core`

Todos os nomes abaixo usados pelo banco possuem definição real:

- player: `GetPlayer`, `IsPlayerLoaded`, `EnsurePlayerLoaded`, `ResolvePlayerIdentity`, `GetSourceByCitizenId`;
- contas: `GetMoney`, `NormalizeMoneyAccount`, `AddMoney`, `RemoveMoney`, `TransferMoneyBetweenAccounts`, `TransferBankBetweenPlayers`;
- inventário: `GetPlayerInventory`, `AddPlayerItem`, `RegisterItemUseHandler`;
- logs: `CreateDetailedLog`.

`SetMoney` também existe no core, mas não é usado pelo fluxo normal do banco.

### 8.5 Contratos confirmados em `mz_economy`

- `RecordTransaction(data)`: usado pelo `mz_core` depois das alterações de saldo;
- `GetAccountStatement(source, account, limit)`: usado diretamente pelo bridge do banco.

`GetAccountStatement` resolve o `citizenid` a partir do `source` no core, normaliza a conta, limita o número de linhas e consulta `mz_economy_transactions`.

### 8.6 Contratos inexistentes ou não implementados

Não foram encontrados na implementação atual do banco:

- `GetPublicAccount`;
- `ResolveTransferRecipient` com esse nome;
- `IssueCard` como API pública;
- `ReplaceCard` com esse nome;
- `GetChannelCapabilities`;
- `GetOperationResult`;
- versão explícita de API/DTO;
- capability ou sessão de phone;
- identidade bancária pública;
- transferência por conta pública;
- idempotência persistente;
- outbox financeira;
- recibo/comprovante recuperável;
- transferência offline;
- sessão/admin API específica.

Também não existem tabelas `mz_bank_accounts`, `mz_bank_sessions`, `mz_financial_outbox` ou tabela de idempotência/resultados no estado atual.

## 9. Tabelas, migrations e readiness

### 9.1 Tabelas participantes

| Tabela | Dono | Uso atual |
|---|---|---|
| `mz_players` | `mz_core` | identidade persistente e fallback de resolução |
| `mz_player_accounts` | `mz_core` | saldo oficial `wallet`, `bank`, `dirty` |
| `mz_inventory_items` | `mz_core` | instâncias e metadata de `bank_card` |
| `mz_bank_cards` | `mz_bank` | credencial/status do cartão, sem saldo |
| `mz_economy_transactions` | `mz_economy` | ledger e extrato best effort |
| `bank_accounts` | legado externo | somente preview/apply administrativo |
| `bank_transactions` | legado externo | somente contagem no preview; não importada |

### 9.2 `mz_bank_cards`

O mesmo `CREATE TABLE IF NOT EXISTS` existe em:

- `mz_bank/sql/001_mz_bank_cards.sql`;
- `MZBankRepository.prepare()` em `mz_bank/server/repository.lua`.

O SQL numerado não é carregado pelo `fxmanifest` nem possui runner detectado. Na prática, o runtime usa `repository.prepare()`. Não existe:

- tabela/registro de versão de migration;
- checksum ou histórico de aplicação;
- validação explícita de colunas/índices esperados;
- export/health endpoint de readiness;
- fonte única de evolução do schema.

`server/main.lua` envolve `prepare()` em `pcall`; em erro mantém `ready = false`. Em sucesso marca o serviço ready. Isso é uma proteção parcial, mas não comprova versão do schema nem dependências externas.

### 9.3 Readiness dos resources relacionados

- `mz_core` possui `MZCoreState` e `EnsurePlayerLoaded` aguarda readiness/prepare;
- `mz_economy` possui `MZEconomyState` com `prepareDone`, `prepareOk`, `prepareError` e `ready`;
- `mz_bank` possui apenas booleano local `ready`, marcado após criar/verificar superficialmente `mz_bank_cards`;
- o registro do handler de uso do cartão acontece depois de `ready` e dentro de `pcall`; sua falha não torna o banco indisponível;
- o banco não aguarda explicitamente o readiness do economy; extrato indisponível é degradado.

## 10. Dependências e ordem real

### 10.1 Manifests

`mz_bank/fxmanifest.lua` declara:

```text
oxmysql
ox_lib
mz_core
```

Não declara `mz_economy`, `mz_inventory`, `mz_interact` ou `mz_notify`. Economy, interact e notify são tratados como opcionais por checagem de estado. O domínio de inventário necessário ao cartão já está dentro do `mz_core`; `mz_inventory` é a interface NUI consumidora.

`mz_economy` depende de `oxmysql` e `mz_core`. `mz_inventory` depende de `ox_lib` e `mz_core`.

### 10.2 Ordem documentada

Os documentos do banco pedem:

```text
ensure oxmysql
ensure ox_lib
ensure mz_core
ensure mz_economy
ensure mz_inventory
ensure mz_bank
```

### 10.3 Ordem efetiva encontrada

`mz_starter/server.cfg` executa `cfg/resources.cfg`. Esse arquivo inicia `oxmysql`, `ox_lib`, `mz_core` e `mz_inventory`, mas não contém `ensure mz_economy` nem `ensure mz_bank`.

Portanto, a ordem efetiva do repositório não inicia os dois resources necessários para o funcionamento bancário completo. Nenhum runtime foi usado para verificar se outro mecanismo externo adiciona esses ensures.

## 11. Dados confiados ao client e dados expostos

### 11.1 Dados vindos do client que influenciam o servidor

| Dado | Uso atual | Estado |
|---|---|---|
| `payload.channel` na abertura | escolhe ATM ou branch; branch é cruzada com config, ATM não | parcial/inseguro para ATM |
| `payload.coords` na abertura | define localização da sessão; ATM aceita coordenada próxima arbitrária | inseguro |
| `channel` no overview | decide se valida sessão física ou usa phone | inseguro |
| `payload.channel` na transferência | seleciona caminho phone ou físico | inseguro |
| `recipientType` | callback repassa tipo arbitrário; serviço aceita `server_id` e `citizenid` | superfície interna indevida |
| `recipientValue` | server ID ou citizenid do destinatário | validado apenas server-side quanto a online/self |
| `amount` | convertido e truncado | parcial; decimal não é rejeitado |
| `token` | comparado com `Sessions[source]` nos caminhos físicos | atendido, exceto quando canal phone evita a validação |
| `reason` no fechamento | usado em log | não afeta saldo/permissão |

### 11.2 Estado físico

O client fecha ou impede a NUI ao detectar morte, veículo, distância ou expiração. O servidor revalida identidade, token, tempo e distância, mas não morte/veículo. Portanto, esses dois estados permanecem confiados ao client como controle efetivo.

### 11.3 Dados enviados à NUI

A NUI recebe saldo bancário, dinheiro em mãos, nome, extrato, símbolo, canal, estado de autenticação e token apenas no client Lua (o token não é enviado no `SendNUIMessage`). O campo `account` é uma máscara derivada do `citizenid`, não uma identidade bancária pública.

O DTO normal do overview não expõe `citizenid` completo. Contudo:

- a máscara ainda deriva de um identificador interno;
- `ResolveRecipient` retorna `source` e `citizenid` completos para consumidores server-side;
- `GetCards` retorna `card_uid` para consumidores server-side;
- não há política de invocador ou DTO versionado para limitar esses exports.

## 12. Animação do ATM e slot do cartão

### 12.1 Animação

Implementação em `client/main.lua`:

1. localiza novamente a entidade ATM pelos modelos ou usa a coordenada do ponto;
2. gira o ped para a entidade/coordenada por 450 ms;
3. inicia o cenário `PROP_HUMAN_ATM`;
4. enquanto a NUI está aberta no canal ATM, reinicia o cenário se ele parar;
5. no fechamento/stop, chama `ClearPedTasks`.

A animação não é iniciada em agência. O código foi preservado; seu funcionamento visual não foi testado em runtime.

### 12.2 Estados do slot

`html/script.js` e `html/style.css` implementam:

| Estado | Label | Cor visual |
|---|---|---|
| `waiting` | `INSIRA O CARTAO` | amarelo/âmbar pulsante |
| `inserted` | `CARTAO INSERIDO` | verde/teal |
| `error` | `CARTAO RECUSADO` | vermelho pulsante; volta a waiting após 900 ms |
| `ejecting` | `RETIRE O CARTAO` | vermelho pulsante; fecha após 550 ms |

No ATM, a abertura não autenticada começa em amarelo; autenticação bem-sucedida muda para verde; recusa ou retirada usa vermelho. Em agência sem exigência de cartão, a NUI é aberta como autenticada e aplica visual `inserted`, embora o botão fique desabilitado por não ser canal ATM.

Não houve validação visual em FiveM, resolução real, foco ou sincronização da animação com o slot.

## 13. Legado

Pontos atendidos:

- `AllowApply = false` por padrão;
- ACE configurável;
- exige `CONFIRM`;
- recusa aplicação com jogadores conectados;
- não soma saldo; usa substituição somente quando a conta oficial está zero;
- saldo legado negativo não é aplicado pela cláusula `ba.balance >= 0`;
- tabelas legadas não são apagadas;
- histórico não é importado.

Pontos ausentes/parciais:

- preview não detecta explicitamente titulares duplicados ou múltiplas linhas resolvendo para a mesma conta;
- o `JOIN` com condição `OR` pode produzir múltiplas correspondências;
- conflitos/divergências são contados, mas não existe gate que recuse toda aplicação com base nesses totais;
- saldo negativo é ignorado, não tratado como bloqueador formal;
- não há relatório persistente;
- backup, autorização e execução prévia em staging não são comprovados pelo comando;
- a operação de apply não registra lote/idempotência nem evidência persistente.

## 14. Estado por área

| Área | Classificação estática atual | Resumo |
|---|---|---|
| Fonte oficial de saldo | atendido | saldo/cache/persistência permanecem no core |
| Saque e depósito canônicos | parcial | operação do core é correta; resposta e idempotência são insuficientes |
| Transferência online atômica | parcial | locks/transação/cache atendidos; destino interno, retry e refresh permanecem riscos |
| Sessão física e token | parcial | token/identidade/tempo/distância existem; canal, ATM e estado físico não estão completos |
| Autenticação de cartão | parcial | titular/status/item são checados inicialmente; não há revalidação |
| Emissão/substituição | parcial | fluxo básico e ordem de entrega existem; faltam atomicidade, lock, idempotência e reconciliação |
| Bloqueio | parcial | status é persistido; sessão ativa não é invalidada |
| PIN | ausente por decisão segura | coluna existe; uso retorna erro controlado se habilitado |
| Phone | produto ausente / caminho exposto | não existe integração/sessão, mas contexto phone já evita sessão física |
| Extrato | parcial | contrato real e degradação existem; ledger é best effort e sem outbox |
| Migration/readiness do banco | parcial | falha de prepare bloqueia ready; schema duplicado e sem versão |
| Ordem efetiva de resources | ausente | `mz_economy` e `mz_bank` não estão em `resources.cfg` |
| Legado | parcial | proteções básicas existem; faltam gates, duplicidades e relatório persistente |
| NUI atual | atendido estaticamente | telas e callbacks conectados; runtime não validado |
| Animação e slot | atendido estaticamente | cenário e três cores preservados; runtime não validado |
| Identidade bancária pública | ausente | server ID/citizenid ainda participam do fluxo |
| Idempotência/outbox | ausente | nenhum contrato ou persistência correspondente |

Esta tabela é um inventário, não a matriz formal B0-01 a B0-10 e não altera o status oficial da Fase 0.

## 15. Riscos prioritários

### Críticos

1. **Bypass de canal físico:** `overview` e `transfer` podem ser direcionados a `phone` pelo client, evitando validação da sessão física.
2. **ATM arbitrário:** coordenada próxima é aceita sem prova server-side de ATM.
3. **Credencial obsoleta válida na sessão:** bloqueio, revogação, substituição ou remoção do item não são revalidados.
4. **Retry financeiro duplicável:** ausência de idempotência persistente após timeout/resultado perdido.

### Altos

5. **Resultado ambíguo após commit:** operação física bem-sucedida depende do overview posterior para formar a resposta.
6. **Estado físico incompleto no servidor:** morte e veículo dependem do client.
7. **Superfície interna:** callback aceita `recipientType` e o serviço aceita `citizenid`; server ID continua sendo conta de destino temporária.
8. **Inicialização incompleta:** configuração efetiva não inicia economy nem bank.
9. **Schema sem fonte única:** SQL e `repository.prepare()` duplicam `mz_bank_cards`.

### Médios

10. **Decimal truncado:** contrato financeiro aceita silenciosamente um valor diferente do enviado.
11. **Cartão sem atomicidade/reconciliação:** cobrança, credencial e item atravessam domínios sem transação única.
12. **Ledger perdível:** falha/offline após commit não possui outbox ou replay.
13. **Legado insuficientemente bloqueado:** conflitos e duplicidades não impedem formalmente o apply.
14. **Exports sem capability/versionamento:** qualquer consumidor server-side pode informar contexto phone e obter DTOs internos.

## 16. Validações realizadas e testes pendentes

### Validações estáticas realizadas

- leitura integral dos arquivos atuais de `mz_bank`;
- confirmação das definições reais de todos os exports externos chamados pelo banco;
- confirmação dos schemas `mz_player_accounts`, `mz_inventory_items`, `mz_bank_cards` e `mz_economy_transactions`;
- confirmação da ordem declarada no `fxmanifest` e da ordem efetiva em `mz_starter`;
- busca de integração real `mz_phone -> mz_bank`, sem chamadas encontradas;
- rastreamento estático dos callbacks NUI, callbacks lib, eventos e exports;
- inspeção estática da animação e dos estados visuais do slot.

### Não validado nesta etapa

- sintaxe/runtime Lua no servidor FiveM;
- funcionamento de `ox_lib` callbacks;
- disponibilidade/semântica real do ped server-side sob OneSync;
- criação e evolução real do schema em MySQL;
- cache igual à persistência após reconnect/restart;
- atomicidade sob falha SQL injetada;
- concorrência e deadlocks;
- ledger compartilhando referência em dados reais;
- emissão, bloqueio, substituição e remoção real do item;
- comportamento com `mz_economy` parado;
- fechamento/foco da NUI;
- animação, alinhamento e reinício do cenário;
- slot amarelo/verde/vermelho no Chromium/FiveM;
- qualquer critério `[R]` do roadmap.

## 17. Inventário de arquivos de `mz_bank`

| Arquivo | Papel atual |
|---|---|
| `.gitattributes` | normalização textual |
| `BANK_ROADMAP.md` | arquitetura, bloqueadores e gates oficiais |
| `PROMPTS_VSCODE_MZ_BANK_ROADMAP.txt` | sequência operacional das fases |
| `README.md` | visão geral, ordem e canais documentados |
| `INTEGRATION.md` | contratos e integração documentados |
| `TEST_PLAN.md` | roteiro preliminar de testes runtime |
| `LEGACY_BANK_TABLES.md` | política operacional do legado |
| `fxmanifest.lua` | scripts, NUI e dependências declaradas |
| `config.lua` | limites, distâncias, pontos, cartões e locale |
| `bridge/server.lua` | adaptação de exports reais do core/economy |
| `server/repository.lua` | schema runtime e CRUD de cartões |
| `server/service.lua` | sessões, canais, operações e cartões |
| `server/legacy.lua` | preview/apply das tabelas legadas |
| `server/main.lua` | readiness, callbacks, eventos e exports |
| `client/main.lua` | abertura, callbacks NUI, animação e sessão client |
| `client/interact.lua` | pontos `mz_interact` e descoberta de ATMs |
| `sql/001_mz_bank_cards.sql` | SQL versionado, não executado pelo resource |
| `html/index.html` | estrutura visual do terminal |
| `html/script.js` | estado, ações, slot e comunicação NUI |
| `html/style.css` | visual do ATM e cores/estados do slot |

## 18. Conclusão da etapa

O estado atual preserva corretamente a autoridade financeira do `mz_core` e já possui uma base funcional de ATM/agência, cartão e NUI. A implementação é, porém, apenas parcial diante da Fase 0 do roadmap. Permanecem bloqueios estáticos reais em canal, ATM, revalidação de cartão, estado físico, superfície interna, resultado financeiro, valores, inicialização, migration e legado.

Nenhuma fase foi aprovada por este relatório. Em especial:

```text
Fase 0: permanece [~] Em implementação conforme BANK_ROADMAP.md
Fase 1: permanece [!] Bloqueada
Runtime: não executado / não aprovado
```

