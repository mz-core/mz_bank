# MZ Bank — Revisão estática final da Fase 0

Data: 2026-07-15  
Revalidação final: 2026-07-15, após correção autorizada de `B0-07`  
Decisão: **Fase 0 `[S]` — VALIDADA ESTATICAMENTE**  
Escopo: `B0-01` a `B0-10`  
Runtime: não avaliado por este documento

## 1. Método e fontes relidas

Esta revisão foi feita sobre os arquivos reais atuais, sem usar Git ou histórico como autoridade e sem assumir corretos os relatórios anteriores.

Foram relidos:

- `BANK_ROADMAP.md`, `TEST_PLAN.md`, `README.md`, `INTEGRATION.md`, `LEGACY_BANK_TABLES.md` e `SCHEMA_AND_STARTUP.md`;
- todos os relatórios existentes em `mz_bank/reports`;
- todos os Lua, JavaScript, HTML, CSS e SQL atuais de `mz_bank`;
- implementações reais consumidas em `mz_core`, `mz_economy`, `mz_inventory`, `mz_interact` e `mz_notify`;
- `mz_starter/server.cfg`, `cfg/resources.cfg` e `cfg/permissions.cfg` efetivos.

Os relatórios anteriores foram usados somente como inventário de alegações e testes pendentes. A classificação abaixo vem do código executável atual e das buscas/validações repetidas nesta revisão.

Nesta revalidação foram alterados somente os arquivos necessários para encerrar `B0-07`: ordem efetiva de resources, classificação degradável do `mz_economy`, readiness, documentação operacional e matriz. Nenhuma funcionalidade da Fase 2 foi implementada e nenhum contrato financeiro foi trocado.

## 2. Resultado executivo

| Item | Resultado independente | Resumo |
|---|---|---|
| B0-01 | APROVADO ESTATICAMENTE | Canal posterior vem da sessão; não existe caminho executável `phone` |
| B0-02 | APROVADO ESTATICAMENTE | ATM precisa corresponder ao catálogo server-side e à posição real do ped |
| B0-03 | APROVADO ESTATICAMENTE | Item, titular, `cardUid` e status são revalidados em cada ação protegida |
| B0-04 | APROVADO ESTATICAMENTE | Ped, coordenada, vida, veículo, distância e personagem são validados no servidor |
| B0-05 | APROVADO ESTATICAMENTE | Confirmação/referência precedem refresh; deduplicação mínima é persistente e atômica |
| B0-06 | APROVADO ESTATICAMENTE | Somente inteiro positivo/finito; limites, taxa e ausência de limite diário estão explícitos |
| B0-07 | APROVADO ESTATICAMENTE | Ordem efetiva aplicada; dependências rígidas falham fechadas e `mz_economy` degrada somente extrato/ledger |
| B0-08 | APROVADO ESTATICAMENTE | DDL de cartões único, migrations versionadas e readiness fail-closed |
| B0-09 | APROVADO ESTATICAMENTE | Callback físico não aceita identidade/tipo de destinatário livres nem vaza identificadores internos |
| B0-10 | APROVADO ESTATICAMENTE | Legado fechado por padrão, com ACE, gates, preview e relatório persistente |

Todos os bloqueadores `B0-01` a `B0-10` possuem evidência estática no estado atual. O gate `[S]` é concedido sem inferir aprovação runtime.

## 3. Evidências por bloqueador

### B0-01 — Canal controlado pelo client

`resolvePhysicalContext` aceita apenas `atm` e `branch`, comprova o ponto e devolve o contexto canônico. `OpenSession` grava `context.channel` em `Sessions[source]`. Autenticação, overview, extrato, cartões e operações consultam `session.channel`; os callbacks posteriores recebem token e DTO financeiro restrito, sem `channel`.

Busca em Lua/JavaScript executável:

```text
phone: 0 ocorrências
recipientType/recipient_type: 0 ocorrências
```

`payload.channel` permanece somente como intenção de abertura física e dado de log de negação. Informar `phone` termina em `channel_forbidden` antes de criar sessão.

### B0-02 — ATM comprovado pelo servidor

O client observa prop/coordenada para UX, mas o servidor chama `resolveKnownAtm`, cruza a coordenada com `Config.ATM.catalog` dentro de `catalogMatchDistance`, substitui o valor recebido pela coordenada canônica e mede a posição obtida de `GetEntityCoords(GetPlayerPed(source))`. Ponto fora do catálogo retorna `atm_invalid`.

Não é recebido network ID ou entity handle do client. Props não networked não são a autoridade da autorização.

### B0-03 — Revalidação do cartão

Na autenticação, `findInventoryCard` exige o item real `bank_card`, metadata do titular, `cardUid` e linha persistida ativa em `mz_bank_cards`. O `cardUid` autenticado fica preso à sessão.

`validateSession` repete a consulta de inventário e credencial antes de toda ação autenticada em canal que exige cartão. Item removido, titular divergente, credencial ausente, bloqueada ou revogada elimina a sessão. Bloqueio e substituição também chamam `invalidateCardSessions`.

A política atual está explícita: cartão obrigatório no ATM e opcional na agência.

### B0-04 — Estado físico server-side

`getServerPlayerState` usa natives server-side para validar:

- handle do ped;
- coordenadas do ped;
- vida maior que zero;
- ausência de veículo.

Na abertura existe uma tolerância limitada para disponibilidade do ped. Depois, `validateSession` compara o `citizenid` atual ao vinculado, mede distância até a coordenada canônica e invalida a sessão nas falhas. O fechamento client-side permanece apenas como UX adicional.

### B0-05 — Resultado financeiro e idempotência

Saque e depósito chamam somente `mz_core:TransferMoneyBetweenAccounts`; transferência chama somente `mz_core:TransferBankBetweenPlayers`.

O core:

- cria/preserva `transactionRef` a partir de `metadata.external_ref`;
- usa locks por `citizenid` em ordem determinística;
- grava `mz_account_idempotency` e alteração de saldo na mesma `MySQL.transaction.await`;
- possui unicidade por `(source_resource, actor_citizenid, idempotency_key)`;
- compara operação e fingerprint;
- recupera a referência anterior com `replayed = true` sem nova alteração.

`confirmedFinancialResponse` exige a referência confirmada antes do overview. Falha posterior somente preenche `refreshError`; `ok`, `confirmed` e `correlationId` permanecem de sucesso.

Uma transferência nova ainda exige destinatário online. `allowOfflineRecovery` só permite que o mesmo server ID alcance o core para recuperar uma chave já confirmada; se não existir resultado persistido, o core retorna `recipient_offline` antes de movimentar saldo.

### B0-06 — Valores, limites e taxa

`validateAmount` exige `type == number`, valor positivo, inteiro e finito. Texto, texto numérico, decimal, zero, negativo, `NaN`, infinito e valor acima do teto são rejeitados antes do core.

Os limites são escolhidos por `session.channel`:

| Canal | Saque | Depósito | Transferência |
|---|---:|---:|---:|
| ATM | 1.000.000 | 1.000.000 | 1.000.000 |
| Agência | 1.000.000 | 1.000.000 | 1.000.000 |

`DailyTransactionLimit = false`; não existe limite diário nesta fase. A taxa atual é `0%`; quando configurada, usa `floor` e o core debita valor mais taxa. O teto seguro de Lua/JSON permanece abaixo do `BIGINT` assinado do schema oficial.

### B0-07 — Inicialização e dependências

O arquivo efetivamente executado por `mz_starter/server.cfg` contém os seis resources na precedência exigida:

```text
ensure oxmysql     = presente
ensure ox_lib      = presente
ensure mz_core     = presente
ensure mz_economy  = presente
ensure mz_inventory = presente
ensure mz_bank     = presente
```

`fxmanifest.lua` e `server/main.lua` tratam `oxmysql`, `ox_lib`, `mz_core` e `mz_inventory` como dependências rígidas. Falta ou parada de qualquer uma mantém/torna o serviço indisponível; falha de schema também continua fail-closed.

`mz_economy` permanece antes do banco na ordem efetiva, mas é observado/degradável porque não é autoridade do saldo nem do commit. Se estiver ausente ou parar, `GetReadiness` mantém `ready = true`, publica `degraded = true` e `warning`, e o bridge retorna `statement_unavailable`; saque, depósito e transferência continuam exclusivamente nos serviços do `mz_core`. O retorno do resource é observado e o bridge recupera o extrato pelo estado real, sem reiniciar o banco.

Essa política coincide em código, manifest, `README.md`, `TEST_PLAN.md` e `SCHEMA_AND_STARTUP.md`. B0-07 está aprovado estaticamente; start, stop e recuperação ainda exigem runtime da Fase 1.

### B0-08 — Schema e migrations

Busca executável encontrou uma única definição de:

```text
CREATE TABLE IF NOT EXISTS mz_bank_cards
```

Ela está somente em `sql/001_mz_bank_cards.sql`. Não existe mais `MZBankRepository.prepare()` nem DDL de cartões no repository.

`server/migrations.lua` aplica `001` e `002`, registra versões em `mz_bank_schema_migrations`, valida engine, tipos, comprimentos essenciais, auto incremento, índices e versão esperada. Erro ou versão incompatível mantém readiness falso. Os SQLs/runner não contêm `DROP`, `TRUNCATE` ou `DELETE`.

Essa é aprovação estática da implementação; nenhuma migration foi executada contra banco real nesta revisão.

### B0-09 — Superfície interna indevida

Os callbacks financeiros usam o `source` implícito fornecido pelo `ox_lib`; não leem `source` ou `citizenid` do payload. O callback de transferência reconstrói somente:

```text
recipientValue
amount
idempotencyKey
token
```

O resolvedor aceita apenas server ID numérico, inteiro e positivo. Não existem `recipientType`, resolução por `citizenid`, `GetSourceByCitizenId` ou `accountMask` no código do banco.

Overview/NUI recebem nome de exibição, saldos, rótulo genérico `Conta corrente`, extrato normalizado, canal e token opaco. Não recebem `citizenid`, license, card UID, ID SQL ou transaction ID interno.

### B0-10 — Segurança do legado

`AllowApply` permanece `false`. Preview e apply passam por `IsPlayerAceAllowed`; a ACE correspondente está declarada em `cfg/permissions.cfg`.

O preview detecta e bloqueia:

- identificador repetido;
- mais de uma linha resolvendo para a mesma conta;
- match ambíguo entre `citizenid` e license;
- saldo negativo, decimal, inválido ou fora do inteiro seguro;
- conflito com saldo oficial não zerado;
- linha sem personagem/conta oficial correspondente.

Backup, autorização, ambiente, estratégia, fingerprint, resumo e resultado são persistidos em `mz_bank_legacy_reports`. Apply exige staging, frase forte, relatório recente, snapshot idêntico, claim de uso único e zero jogadores conectados.

A única escrita direta em saldo encontrada no `mz_bank` é a exceção administrativa explícita em `server/legacy.lua`: atualização transacional de `mz_player_accounts.bank` somente onde `bank = 0`. Não existe soma de saldo. `bank_accounts` e `bank_transactions` aparecem somente em `server/legacy.lua` e na chamada diagnóstica de preview do bootstrap; não participam de overview ou operações. O histórico é contado, nunca importado ou apagado.

## 4. Contratos e superfícies conferidos

Todos os exports chamados pelo `mz_bank` possuem implementação real localizada:

- `mz_core`: `GetMoney`, `NormalizeMoneyAccount`, `TransferMoneyBetweenAccounts`, `TransferBankBetweenPlayers`, `RemoveMoney`, `AddMoney`, `GetPlayer`, `IsPlayerLoaded`, `EnsurePlayerLoaded`, `ResolvePlayerIdentity`, `GetPlayerInventory`, `AddPlayerItem`, `RegisterItemUseHandler` e `CreateDetailedLog`;
- `mz_economy`: `GetAccountStatement`;
- `mz_interact`: `AddPoint` e `RemovePoint`;
- `mz_notify`: `Notify`.

Os seis callbacks server-side registrados coincidem com os seis chamados pelo client:

```text
openSession, authenticate, overview, withdraw, deposit, transfer
```

O evento de fechamento recebe somente token/motivo e usa o `source` implícito. Não foram encontrados callbacks físicos antigos ativos, caminho phone, tipo de destinatário arbitrário ou identity payload livre.

## 5. Dados ainda vindos do client

| Campo | Uso server-side | Autoridade |
|---|---|---|
| `payload.channel` na abertura | intenção limitada a ATM/agência | servidor comprova catálogo/agência e grava canal na sessão |
| `payload.coords` na abertura | candidato para lookup | servidor substitui por coordenada canônica e mede o ped real |
| token | identifica tentativa de sessão | comparado com `Sessions[source]` |
| amount | intenção financeira | contrato inteiro/limite aplicado no servidor |
| recipientValue | server ID candidato | resolvido online no servidor/core |
| idempotencyKey | chave opaca | formato, escopo, fingerprint e unicidade validados no servidor/core |
| motivo de fechamento | somente log/limpeza | não autoriza operação |

Nenhum desses campos decide sozinho identidade, saldo, canal posterior ou permissão financeira.

## 6. Saldo, transferência offline e legado

- Fluxo normal não executa SQL direto em `mz_player_accounts`; usa serviços oficiais do `mz_core`.
- `player.money.wallet`, `player.money.bank` e `mz_player_accounts` continuam as fontes oficiais.
- `mz_account_idempotency` armazena confirmação/referência, não snapshot de saldo.
- `mz_bank_cards`, `mz_bank_schema_migrations` e `mz_bank_legacy_reports` não possuem coluna de saldo.
- Não existe `mz_bank_accounts`, saldo paralelo, PIX, conta empresarial ou outbox criada pelo banco.
- Não existe nova transferência offline; somente recuperação idempotente de resultado já confirmado.
- A escrita direta do legado é isolada, desligada por padrão, não aditiva e fora do fluxo operacional.

## 7. NUI, animação e slot

Revisão estrutural confirmou preservação de:

- NUI ATM/agência e callbacks atuais;
- alinhamento por `TaskTurnPedToFaceEntity`, com fallback por coordenada;
- cenário `PROP_HUMAN_ATM` iniciado na abertura e retomado enquanto a sessão ATM está ativa;
- `ClearPedTasks`, retirada de foco e fechamento da NUI no encerramento/restart;
- slot amarelo em `waiting`;
- slot verde em `inserted`;
- slot vermelho em `ejecting` ou `error`;
- rejeição server-side encaminhada como `cardRejected` antes do fechamento;
- extrato formatado como `-R$10`/`+R$10` e scrollbar usando as cores teal/âmbar do banco.

Isso comprova que os caminhos continuam presentes e coerentes estaticamente. Timing, alinhamento visual e duração das cores ainda exigem FiveM para confirmação runtime.

## 8. Validações executadas nesta revisão

### Sintaxe

- `luac -p`: aprovado para todos os Lua executáveis do `mz_bank`, incluindo manifest, bridge, client e server.
- `config.lua`: aprovado após substituir somente os hash literals com crase do FiveM por literais neutros para o parser Lua local.
- `luac -p`: aprovado também para os contratos consumidos de accounts/player/inventory do `mz_core` e service/main do `mz_economy`.
- `node --check`: aprovado para `mz_bank/html/script.js`.

### Buscas automatizadas

```text
phone executável: 0
recipientType executável: 0
payload client-facing com source/citizenid: 0
arquivos com DDL de mz_bank_cards: 1 (001_mz_bank_cards.sql)
arquivos executáveis com tabelas legadas: 2 (legacy.lua e preview diagnóstico em main.lua)
escritas diretas de saldo no banco: 1 (apply legado controlado)
DROP/TRUNCATE/DELETE no runner/legado/SQLs: 0
exports chamados sem implementação localizada: 0
callbacks server-side chamados sem registro: 0
```

Nenhum teste FiveM, comando financeiro, aplicação legada ou migration real foi executado.

## 9. Bloqueadores encerrados nesta revalidação

### ST-F0-01 — Ordem efetiva não inicia `mz_economy` e `mz_bank`

- **Item:** B0-07.
- **Classificação:** CORRIGIDO.
- **Evidência:** `mz_starter/cfg/resources.cfg` contém a sequência efetiva abaixo nas linhas 16, 17 e 25–28:

```cfg
ensure oxmysql
ensure ox_lib
ensure mz_core
ensure mz_economy
ensure mz_inventory
ensure mz_bank
```

- **Runtime posterior:** APROVADO conforme execução manual no FiveM informada pelo usuário; detalhes adicionais não foram anexados.

### ST-F0-02 — Contrato contraditório para `mz_economy` indisponível

- **Itens:** B0-07 e comportamento preservado do Lote B.
- **Classificação:** CORRIGIDO.
- **Evidência:** `mz_economy` foi removido da lista rígida do manifest/bootstrap e incluído como dependência observada. O código não chama `SetReady(false)` quando somente esse resource para, expõe degradação no readiness e deixa `MZBankBridge.GetStatement` controlar a disponibilidade do extrato. README, plano de testes e documentação de startup descrevem a mesma política.
- **Runtime posterior:** APROVADO conforme execução manual no FiveM informada pelo usuário, incluindo continuidade das operações e comportamento do extrato; detalhes adicionais não foram anexados.

## 10. Gate final

```text
Fase 0: [S] Validada estaticamente
```

A Fase 0 recebe `[S]` porque `B0-01` a `B0-10` possuem evidência estática no código e na configuração efetiva. Este documento não concede aprovação runtime, não marca `[R]` e não substitui os testes da Fase 1 em staging.

## 11. Registro runtime posterior

Em 2026-07-15, após a conclusão desta revisão estática, o usuário informou que os testes runtime dos Lotes A, B e C e os testes financeiros da Fase 1 foram executados manualmente no FiveM e passaram.

Segundo o resultado fornecido pelo usuário:

- depósito, saque e transferência foram aprovados;
- saldo, cache e persistência foram preservados;
- callbacks adulterados foram negados;
- sessões e cartões foram revalidados;
- animação, NUI e estados amarelo/verde/vermelho do slot foram aprovados;
- migrations, dependências e controles do legado foram aprovados;
- não há falhas pendentes conhecidas.

Limitação preservada: não foram fornecidos anexos adicionais de console, queries, vídeo, screenshot, build ou versão da rodada. Nenhuma evidência adicional foi inferida. Este registro posterior não altera a metodologia nem as evidências da revisão estática acima; a decisão runtime está consolidada em `reports/PHASE_1_FINAL_DECISION.md`.

```text
Fase 0: [S] Validada estaticamente
```
