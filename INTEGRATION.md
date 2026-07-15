# Integracao do mz_bank

## Contratos oficiais usados

O bridge `bridge/server.lua` usa somente exports diretos reais do `mz_core`: `GetPlayer`, `IsPlayerLoaded`, `EnsurePlayerLoaded`, `ResolvePlayerIdentity`, `GetMoney`, `NormalizeMoneyAccount`, `TransferMoneyBetweenAccounts`, `TransferBankBetweenPlayers`, `GetPlayerInventory`, `AddPlayerItem`, `RemoveMoney`, `AddMoney`, `RegisterItemUseHandler` e `CreateDetailedLog`.

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

## API server-side atual

Os exports atuais exigem contexto fisico autenticado. O token resolve a sessao e o canal no servidor; `context.channel` nao seleciona capacidade:

```lua
exports['mz_bank']:GetAccountOverview(source, { token = token })
exports['mz_bank']:GetStatement(source, { limit = 20 }, { token = token })
exports['mz_bank']:ResolveRecipient(source, '12', { token = token })
exports['mz_bank']:Transfer(source, { value = '12' }, 500, {
  token = token,
  idempotencyKey = 'chave-opaca-unica-com-16-a-64-caracteres'
})
exports['mz_bank']:GetCards(source, { token = branchToken })
exports['mz_bank']:BlockCard(source, cardUid, { token = branchToken })
exports['mz_bank']:RequestReplacementCard(source, { token = branchToken })
```

O tipo de destinatario fisico e fixo em `server_id`; `citizenid` nao e aceito nem devolvido pelo contrato de resolucao. `GetCards`, `BlockCard` e `RequestReplacementCard` exigem uma sessao de agencia.

O canal `phone` esta desativado nesta fase. Uma integracao futura precisa de sessao/capability propria e nao pode reutilizar callbacks fisicos ou aceitar `source`/`citizenid` escolhidos pelo client.

## Extrato

`mz_economy:GetAccountStatement(source, account, limit)` resolve o `citizenid` pelo `source` autenticado, restringe a uma conta normalizada e aplica limite. A NUI recebe apenas o payload normalizado pelo servidor do banco.

## Sessao fisica

O client envia a intencao fisica (`atm` ou `branch`) e a coordenada observada. Agencias sao cruzadas com `Config.Branches`; ATMs sao cruzados com `Config.ATM.catalog`. O catalogo server-side e a fonte de autorizacao e nao depende de o prop ser networked. Mapeamentos customizados precisam registrar a coordenada real no catalogo.

O servidor valida ped, vida, veiculo, personagem e distancia. O token e invalidado em fechamento, afastamento, morte, veiculo, troca de personagem, disconnect, restart ou falha de revalidacao do cartao. Operacoes financeiras exigem autenticacao e ha apenas uma operacao simultanea por sessao.

## Valores, limites e taxa

Saque, deposito e transferencia aceitam somente `number` inteiro, positivo e finito. Texto numerico, decimal, zero, negativo, `NaN` e infinito sao rejeitados; nenhum valor e truncado. `Config.TransactionLimits` define separadamente saque, deposito e transferencia para `atm` e `branch`, atualmente em `1.000.000` por operacao. O teto efetivo tambem fica limitado ao maior inteiro seguro do runtime (`9.007.199.254.740.991`), abaixo do `BIGINT` assinado usado por `mz_player_accounts`.

Nao existe limite diario nesta fase (`Config.DailyTransactionLimit = false`). A taxa atual e `0%`. Se configurada acima de zero, o core debita `valor + taxa` do remetente, credita somente `valor` ao destinatario e a taxa e calculada por `floor(valor * percentual / 100)`; portanto, o arredondamento e sempre para baixo e o resultado continua inteiro.

## Erros estaveis

Os codigos ficam em `Config.Locale`, incluindo `invalid_session`, `session_expired`, `too_far`, erros de cartao, saldo, destinatario, rate limit, inventario, extrato e banco de dados. A NUI usa `ok/error/message/data` e nao decide regras a partir do texto.
