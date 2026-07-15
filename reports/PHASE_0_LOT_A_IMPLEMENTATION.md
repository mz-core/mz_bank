# MZ Bank — Implementação do Lote A da Fase 0

Data: 2026-07-15  
Escopo: `B0-01`, `B0-02`, `B0-03`, `B0-04` e `B0-09`.

## Resultado

O Lote A foi implementado no código atual. As sessões físicas agora vinculam token, canal, personagem e localização canônica no servidor; ATMs precisam pertencer ao catálogo; o cartão autenticado é revalidado com o item físico e a credencial persistida; o servidor volta a conferir o estado físico antes de ações protegidas; e a superfície client-facing de transferência ficou restrita a server ID online.

Isto é um resultado de implementação e validação de sintaxe. Não houve execução no FiveM, evidência de staging ou aprovação runtime. A Fase 0 também não foi marcada como validada.

## Diagnóstico anterior e correção aplicada

### B0-01 — canal físico

Antes, operações e exports podiam selecionar ou assumir `phone` a partir de contexto informado pelo chamador. Agora:

- a abertura só resolve `atm` ou `branch` em `resolvePhysicalContext`;
- `OpenSession` grava o canal comprovado em `Sessions[source]`;
- overview, extrato, resolução, cartões e movimentações exigem token e consultam `session.channel`;
- o callback de transferência reconstrói o payload permitido e não encaminha `channel`;
- permissões e estado especial de `phone` foram removidos deste lote físico.

Um `payload.channel` ainda existe exclusivamente na tentativa de abrir uma sessão; ele é comparado com os dois canais físicos e não alcança phone. Depois da abertura, o token é a referência da sessão e de seu canal.

### B0-02 — prova do ATM

Foi criado `Config.ATM.catalog` com 112 pontos estáticos e `catalogMatchDistance`. A lista serve tanto para restringir a descoberta client-side quanto, principalmente, para a decisão server-side.

O seed de coordenadas vanilla foi confrontado com a lista pública de configuração em <https://docs.felis.gg/banking/config>. Essa referência não substitui a confirmação no mapa real do servidor, que permanece pendente.

Na abertura ATM, o servidor:

1. converte e limita o payload;
2. encontra um ATM conhecido dentro da tolerância;
3. substitui a coordenada pedida pela coordenada canônica do catálogo;
4. lê o ped e sua posição no servidor;
5. nega ponto arbitrário (`atm_invalid`) ou jogador distante (`too_far`).

O servidor não recebe nem exige entity handle ou network ID. Isso permite tratar os props vanilla não networked sem transformar o client em autoridade. Para MLOs e mapas customizados, a coordenada real precisa ser adicionada explicitamente ao catálogo.

### B0-03 — revalidação do cartão

Ao autenticar, o serviço associa à sessão o `cardUid` da credencial ativa encontrada no item físico. Em toda chamada autenticada de um canal que exige cartão, `validateSession` repete:

- presença do item `bank_card` no inventário oficial;
- correspondência com o mesmo `cardUid` autenticado;
- titularidade da metadata e da linha persistida;
- existência da credencial;
- status exatamente `active`.

Falha na revalidação elimina a sessão antes de nova ação. Bloqueio invalida imediatamente sessões com o cartão; substituição revoga as credenciais anteriores e invalida sessões que não usam o novo cartão. Remoção do item, revogação e credencial inexistente são recusadas na próxima chamada protegida.

### B0-04 — estado físico server-side

A abertura e a validação recorrente agora usam `GetPlayerPed(source)` e server natives para conferir:

- ped válido/existente;
- posição real do ped;
- vida maior que zero;
- ausência de veículo;
- distância da agência ou ATM canônico;
- citizenid atual igual ao personagem que abriu a sessão.

Morte, veículo, distância, troca de personagem e ped inválido fora da tolerância removem a sessão. As checagens client-side e o fechamento visual continuam existindo como UX, mas não são o controle de segurança.

### B0-09 — superfície client-facing

A transferência física foi limitada a um único contrato: server ID inteiro, positivo, online e diferente do próprio jogador. Foram removidos:

- `recipientType` do NUI/client e do callback;
- resolução client-facing por citizenid;
- `GetSourceByCitizenId` do bridge do banco;
- retorno de `source` e `citizenid` no DTO de resolução;
- máscara de conta derivada do citizenid no overview;
- source/citizenid embutidos no token, que agora é um valor opaco aleatório e se relaciona ao personagem somente em `Sessions` no servidor;
- rótulo JavaScript remanescente para `phone_transfer`.

Campos extras enviados ao callback são descartados quando `server/main.lua` cria o DTO `{ value = payload.recipientValue }`. A NUI recebe nome de exibição, saldos, descrição genérica da conta e extrato, mas não recebe citizenid, source, cardUid ou tipo arbitrário de resolução.

## Arquivos alterados

| Arquivo | Alteração do Lote A |
|---|---|
| `mz_bank/config.lua` | catálogo/tolerância de ATM e mensagens para ped, morte, veículo e ATM inválido |
| `mz_bank/client/main.lua` | filtro do catálogo, payloads sem canal/tipo arbitrário, fechamento em falha física server-side; animação preservada |
| `mz_bank/client/interact.lua` | registro de interação ATM limitado ao catálogo |
| `mz_bank/server/service.lua` | autoridade de sessão/canal, prova física, revalidação de cartão, invalidação de sessão e destinatário restrito |
| `mz_bank/server/main.lua` | callbacks sanitizados e exports protegidos por contexto/token |
| `mz_bank/bridge/server.lua` | remoção da resolução por citizenid usada pelo fluxo client-facing |
| `mz_bank/html/script.js` | remoção apenas do rótulo órfão de phone; layout e estados do cartão preservados |
| `mz_bank/INTEGRATION.md` | contrato físico atual e phone explicitamente indisponível sem capability futura |
| `mz_bank/README.md` | catálogo de ATM e destinatário físico oficialmente suportado |
| `mz_bank/TEST_PLAN.md` | expectativa de negação do phone sem capability própria |
| `mz_bank/reports/PHASE_0_BLOCKER_MATRIX.md` | inicialização somente com os cinco itens do Lote A |
| `mz_bank/reports/PHASE_0_LOT_A_IMPLEMENTATION.md` | este relatório |

`BANK_ROADMAP.md` e `PHASE_0_CURRENT_STATE.md` não foram reescritos. O relatório de estado atual permanece como fotografia anterior à implementação.

## Contratos reais utilizados

Nenhum export, callback, evento ou tabela externa nova foi inventado.

### `mz_core`

- player: `GetPlayer`, `IsPlayerLoaded`, `EnsurePlayerLoaded`, `ResolvePlayerIdentity`;
- contas oficiais: `GetMoney`, `NormalizeMoneyAccount`, `AddMoney`, `RemoveMoney`, `TransferMoneyBetweenAccounts`, `TransferBankBetweenPlayers`;
- inventário oficial: `GetPlayerInventory`, `AddPlayerItem`, `RegisterItemUseHandler`;
- auditoria: `CreateDetailedLog`.

Os saldos continuam exclusivamente em `player.money.wallet`, `player.money.bank` e na persistência oficial `mz_player_accounts` operada pelo core. Não foi criada conta ou saldo paralelo.

### `mz_economy`

- `GetAccountStatement(source, 'bank', limit)` continua fornecendo o extrato;
- a gravação de transações permanece consequência dos serviços financeiros do `mz_core`, sem outbox nova no banco.

### inventário

O banco usa a facade real do `mz_core` para ler/adicionar itens. Não foi criado contrato direto fictício com `mz_inventory`. A autoridade física usada na revalidação é o item retornado pelo facade oficial, junto da credencial `mz_bank_cards` do próprio banco.

## Preservações verificadas no código

- a NUI existente, sua estrutura HTML/CSS e navegação não foram redesenhadas;
- `PROP_HUMAN_ATM`, giro/alinhamento do ped e retomada do cenário permanecem em `client/main.lua`;
- `setCardState` e as classes `waiting`, `inserted`, `ejecting` e `error` permanecem; portanto a lógica amarela/verde/vermelha não foi substituída;
- saque e depósito continuam usando `TransferMoneyBetweenAccounts` do `mz_core`;
- transferência continua usando `TransferBankBetweenPlayers` do `mz_core`;
- não foram implementados phone, PIX, conta pública, destinatário offline, outbox completa ou conta empresarial.

Essas preservações são constatações estáticas. O comportamento visual e financeiro ainda precisa ser comprovado em FiveM.

## Validações executadas

### Sintaxe

- todos os 9 arquivos Lua de `mz_bank` passaram em `luac -p`;
- no `config.lua`, somente os literais hash em backticks próprios do FiveM foram normalizados para `0` na entrada do parser Lua de estoque; o arquivo real não foi reescrito para a validação;
- `mz_bank/html/script.js` passou em `node --check`;
- resultado dos comandos: exit code `0`.

### Buscas de superfície

- nenhuma ocorrência de `phone` no conjunto de código Lua/JS do resource;
- nenhuma ocorrência de `recipientType`, `GetSourceByCitizenId` ou `accountMask`;
- `payload.channel` permanece apenas na resolução e auditoria da abertura física;
- o callback NUI de transferência envia somente `recipientValue` e `amount`;
- o callback server-side deriva `source` do `ox_lib`, e não de campo livre enviado pelo client;
- respostas client-facing de overview e resolução não contêm citizenid, source ou cardUid;
- o token client-facing tem 48 caracteres opacos e não contém source/citizenid serializados;
- sete asserções estruturais automatizadas confirmaram sanitização do DTO, overview por token, ATM canônico, revalidação do mesmo cartão, estado físico server-side, DTO de destinatário somente com nome e token opaco; todas retornaram verdadeiro;
- a contagem isolada de `Config.ATM.catalog` confirmou 112 entradas.

### O que não foi validado

- servidor FiveM não foi iniciado;
- nenhum callback foi adulterado em rede;
- nenhuma transação real foi executada;
- nenhum item foi removido/bloqueado/substituído durante uma sessão real;
- nenhuma coordenada foi confirmada visualmente no mapa em uso;
- animação, alinhamento, foco NUI e cores do slot não foram observados em runtime.

## Riscos e dependências restantes

1. **Catálogo do mapa:** os 112 pontos precisam ser testados contra o build e os mapas/MLOs usados. Um ATM customizado fora da lista será negado até configuração explícita.
2. **Server natives/OneSync:** disponibilidade e atualização de ped, vida, veículo e coordenadas devem ser confirmadas no ambiente real, especialmente logo após spawn/troca de personagem.
3. **Tolerâncias:** `catalogMatchDistance`, distância da sessão e as tolerâncias iniciais podem precisar de ajuste baseado em evidência runtime, sem afrouxar a autoridade server-side.
4. **Inventário:** é necessário confirmar que `GetPlayerInventory` reflete imediatamente remoção, troca e metadata do item no resource efetivamente ativo.
5. **Consumidores server-side:** exports de overview/extrato/transferência/cartões agora exigem token físico válido. Consumidor antigo sem sessão deve falhar; phone futuro precisará de contrato/capability próprio e não foi implementado.
6. **Resultado financeiro:** separação entre commit financeiro e falha de refresh pertence a `B0-05` e não foi alterada neste lote.

## Testes runtime pendentes

- abertura válida em agência e em amostra de ATMs do catálogo;
- abertura com `channel=phone`, canal desconhecido e coordenada ATM falsa;
- prop ATM não networked e ATM de mapa customizado dentro/fora do catálogo;
- adulteração de token, canal, source, citizenid, recipientType e campos extras;
- distância, morte, veículo, ped ausente e troca de personagem antes de overview e de cada operação;
- cartão válido, de outro titular, bloqueado, revogado, substituído, credencial ausente e item removido;
- saque, depósito e transferência válidos/negados, conferindo wallet, bank, `mz_player_accounts` e extrato;
- destinatário por server ID válido, próprio, offline, decimal, texto e inexistente;
- disconnect, resource stop/restart e expiração;
- início/fim da animação, alinhamento do ped, slot amarelo ao abrir, verde ao autenticar e vermelho ao retirar/recusar;
- fechamento e foco da NUI em todas as recusas.

Todos esses testes estão **PENDENTES DE RUNTIME**. Nenhum foi marcado como aprovado.
