# Integracao do mz_bank

## Contratos oficiais usados

O bridge `bridge/server.lua` usa somente exports diretos reais do `mz_core`: `GetPlayer`, `IsPlayerLoaded`, `EnsurePlayerLoaded`, `ResolvePlayerIdentity`, `GetMoney`, `NormalizeMoneyAccount`, `TransferMoneyBetweenAccounts`, `TransferBankBetweenPlayers`, `GetOperationResult`, `GetPlayerInventory`, `AddPlayerItem`, `RemoveMoney`, `AddMoney`, `RegisterItemUseHandler` e `CreateDetailedLog`.

A identidade bancaria nasce de uma unica leitura do player em cache (`GetPlayer`) e fica vinculada ao `citizenid` da sessao. `ResolvePlayerIdentity` e usado apenas como fallback para `firstname`/`lastname` quando o `charinfo` em cache estiver vazio; ele nunca substitui o `citizenid` da sessao.

Nao existe `GetCoreObject`, objeto QBCore, fallback de license como identidade bancaria nem escrita de saldo pelo `mz_bank`.

As duas APIs financeiras adicionadas ao dominio de accounts retornam:

```lua
{
  ok = true,
  balances = { ... },
  transactionRef = 'referencia-correlacionada',
  correlationId = 'referencia-correlacionada',
  replayed = false
}
```

`transactionRef` e a referencia oficial ja existente no `mz_core`; `correlationId` e o alias client-facing do mesmo valor. Quando `idempotency_key` e informado, o core persiste o resultado em `mz_account_idempotency` na mesma transacao SQL da alteracao de saldo. O mesmo escopo `(resource, citizenid, chave)` recupera o resultado anterior com `replayed = true`, sem nova movimentacao. Isso e uma deduplicacao minima, nao uma outbox.

Erros retornam `{ ok = false, error = 'codigo_estavel' }`. Todos os caminhos de alteracao do `mz_core` usam o mesmo lock por `citizenid`; transferencias entre players adquirem locks em ordem deterministica e persistem ambas as pontas em uma transacao antes de atualizar cache.

## API server-side versionada

`GetAPIVersion()` retorna a versao atual (`1`). Os demais exports exigem um `source` carregado,
resource chamador autorizado e sessao/capability valida. Chamadores externos enviam
`context.apiVersion = 1`. O token resolve a sessao e o canal no servidor; `context.channel` nao
seleciona capacidade:

```lua
local context = { apiVersion = 1, token = capabilityToken }
exports['mz_bank']:GetAccountOverview(source, context)
exports['mz_bank']:GetAccountStatement(source, { limit = 20 }, context)
exports['mz_bank']:GetPublicAccount(source, context)
exports['mz_bank']:ResolveTransferRecipient(source, route, context)
exports['mz_bank']:Transfer(source, {
  resolutionToken = resolutionToken,
  amount = 10,
  idempotencyKey = idempotencyKey
}, context)
exports['mz_bank']:GetCards(source, sessionContext)
exports['mz_bank']:BlockCard(source, cardRef, sessionContext)
exports['mz_bank']:IssueCard(source, branchContext)
exports['mz_bank']:ReplaceCard(source, branchContext)
exports['mz_bank']:GetChannelCapabilities(source, context)
exports['mz_bank']:GetOperationResult(source, {
  operation = 'transfer',
  idempotencyKey = idempotencyKey
}, context)
```

`Withdraw` e `Deposit` tambem existem para o adaptador fisico oficial. `GetStatement` e
`RequestReplacementCard` permanecem apenas como aliases de compatibilidade.

`GetCards` devolve `cardRef`, ultimos quatro digitos, estado e timestamps publicos. O `cardRef`
e opaco e vinculado ao `source` e token da listagem; `card_uid`, ID SQL, titular e metadata interna
nao saem pela API. Emissao e substituicao tambem removem `cardUid` da resposta compartilhada.

`GetOperationResult` aceita `withdraw`, `deposit` ou `transfer`, consulta a deduplicacao persistente
no escopo real `mz_bank + jogador + idempotencyKey` e devolve somente confirmacao, correlationId,
taxa e replay. Ele nao consulta nem altera saldo.

O fluxo fisico de transferencia nao possui export client-facing. A NUI envia somente
`branch`, `accountNumber` e `checkDigit` ao callback de resolucao; recebe um DTO mascarado e um
`resolutionToken` opaco e temporario. A confirmacao envia somente esse token, o valor inteiro e a
chave de idempotencia. O servidor resolve e revalida o `citizenid` internamente antes de chamar o
servico financeiro oficial do `mz_core`.

Server ID, `targetId`, `recipientValue` e `citizenid` nao fazem parte do contrato final da NUI.
`GetCards` aceita sessao de agencia ou telefone; `BlockCard` aceita os dois canais e exige o
`cardRef` opaco emitido para a mesma sessao. `IssueCard` e `ReplaceCard` continuam exclusivos da
agencia.

O `mz_phone` esta na allowlist server-to-server e usa sessao propria do canal `phone`, vinculada ao
source, personagem e aparelho resolvidos no servidor. A matriz fixa aceita `mz_phone -> phone` e
rejeita token `atm/branch`, mesmo que ele seja valido para o jogador. O token da sessao,
`resolutionToken` e `idempotencyKey` permanecem server-side; o client nao envia `source`,
`citizenid` ou canal. O P6-C libera overview, extrato, cartoes, transferencia por conta publica e
bloqueio de cartao ativo. Saque, deposito, emissao e substituicao continuam fail-closed no canal
phone.

Depois de uma transferencia confirmada no canal `phone`, o `mz_bank` chama o contrato server-side
`mz_phone:CreateBankTransferNotifications`. O telefone revalida os dois sources, persiste uma
notificacao de saida e uma de entrada e usa `(citizenid, dedupe_key)` para deduplicar cada ponta
pelo `correlationId` oficial. A chamada ocorre depois do commit: indisponibilidade ou falha no
`mz_phone` e apenas auditada e nunca converte sucesso financeiro em falha. Replay pode recuperar
uma notificacao ausente, mas nao exibe nem persiste duplicata.

## Extrato

`mz_economy:GetAccountStatement(source, account, limit)` resolve o `citizenid` pelo `source` autenticado, restringe a uma conta normalizada e aplica limite. A NUI recebe apenas o payload normalizado pelo servidor do banco.

## Sessao fisica

O client envia a intencao fisica (`atm` ou `branch`) e a coordenada observada. Agencias sao cruzadas com `Config.Branches`; ATMs sao cruzados com `Config.ATM.catalog`. O catalogo server-side e a fonte de autorizacao e nao depende de o prop ser networked. Mapeamentos customizados precisam registrar a coordenada real no catalogo.

O servidor valida ped, vida, veiculo, personagem e distancia. O token e invalidado em fechamento, afastamento, morte, veiculo, troca de personagem, disconnect, restart ou falha de revalidacao do cartao. Operacoes financeiras exigem autenticacao e ha apenas uma operacao simultanea por sessao.

## Valores, limites e taxa

Saque, deposito e transferencia aceitam somente `number` inteiro, positivo e finito. Texto numerico, decimal, zero, negativo, `NaN` e infinito sao rejeitados; nenhum valor e truncado. `Config.TransactionLimits` define separadamente saque, deposito e transferencia para `atm` e `branch`, e somente transferencia para `phone`, atualmente em `1.000.000` por operacao. O teto efetivo tambem fica limitado ao maior inteiro seguro do runtime (`9.007.199.254.740.991`), abaixo do `BIGINT` assinado usado por `mz_player_accounts`.

Nao existe limite diario nesta fase (`Config.DailyTransactionLimit = false`). A taxa atual e `0%`. Se configurada acima de zero, o core debita `valor + taxa` do remetente, credita somente `valor` ao destinatario e a taxa e calculada por `floor(valor * percentual / 100)`; portanto, o arredondamento e sempre para baixo e o resultado continua inteiro.

## Erros estaveis

Os codigos ficam em `Config.Locale`, incluindo `invalid_session`, `session_expired`, `too_far`, erros de cartao, saldo, destinatario, rate limit, inventario, extrato e banco de dados. A NUI usa `ok/error/message/data` e nao decide regras a partir do texto.
