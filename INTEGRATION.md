# Integracao do mz_bank

## Contratos oficiais usados

O bridge `bridge/server.lua` usa somente exports diretos reais do `mz_core`: `GetPlayer`, `IsPlayerLoaded`, `EnsurePlayerLoaded`, `ResolvePlayerIdentity`, `GetMoney`, `NormalizeMoneyAccount`, `TransferMoneyBetweenAccounts`, `TransferBankBetweenPlayers`, `GetSourceByCitizenId`, `GetPlayerInventory`, `AddPlayerItem`, `RemoveMoney`, `AddMoney`, `RegisterItemUseHandler` e `CreateDetailedLog`.

A identidade bancaria nasce de uma unica leitura do player em cache (`GetPlayer`) e fica vinculada ao `citizenid` da sessao. `ResolvePlayerIdentity` e usado apenas como fallback para `firstname`/`lastname` quando o `charinfo` em cache estiver vazio; ele nunca substitui o `citizenid` da sessao.

Nao existe `GetCoreObject`, objeto QBCore, fallback de license como identidade bancaria nem escrita de saldo pelo `mz_bank`.

As duas APIs financeiras adicionadas ao dominio de accounts retornam:

```lua
{
  ok = true,
  balances = { ... },
  transactionRef = 'referencia-correlacionada'
}
```

Erros retornam `{ ok = false, error = 'codigo_estavel' }`. Todos os caminhos de alteracao do `mz_core` usam o mesmo lock por `citizenid`; transferencias entre players adquirem locks em ordem deterministica e persistem ambas as pontas em uma transacao antes de atualizar cache.

## API publica para mz_phone

Os exports server-side do `mz_bank` sao:

```lua
exports['mz_bank']:GetAccountOverview(source, { channel = 'phone' })
exports['mz_bank']:GetStatement(source, { limit = 20 }, { channel = 'phone' })
exports['mz_bank']:ResolveRecipient(source, 'server_id', '12')
exports['mz_bank']:Transfer(source, { type = 'server_id', value = '12' }, 500, { channel = 'phone' })
exports['mz_bank']:GetCards(source)
exports['mz_bank']:BlockCard(source, cardUid)
exports['mz_bank']:RequestReplacementCard(source, context)
```

Esses exports sao para consumo server-to-server. O `mz_phone` deve autenticar sua propria sessao e nunca expor um evento que aceite `source` ou `citizenid` escolhidos pelo client. O canal `phone` nao permite saque ou deposito e nao exige o item fisico.

## Extrato

`mz_economy:GetAccountStatement(source, account, limit)` resolve o `citizenid` pelo `source` autenticado, restringe a uma conta normalizada e aplica limite. A NUI recebe apenas o payload normalizado pelo servidor do banco.

## Sessao fisica

O client envia canal e coordenada observada. O servidor confere o ped, distancia e, em agencias, a coordenada configurada. ATMs de mapa podem nao ser networked; por isso a lista de modelos e validada no client, enquanto o servidor combina proximidade, token vinculado a source/citizenid, expiracao, revalidacao e rate limit. Essa e uma mitigacao, nao uma prova server-side do prop.

O token e invalidado em fechamento, afastamento, morte, disconnect ou restart. Operacoes financeiras exigem autenticacao e ha apenas uma operacao simultanea por sessao.

## Erros estaveis

Os codigos ficam em `Config.Locale`, incluindo `invalid_session`, `session_expired`, `too_far`, erros de cartao, saldo, destinatario, rate limit, inventario, extrato e banco de dados. A NUI usa `ok/error/message/data` e nao decide regras a partir do texto.
