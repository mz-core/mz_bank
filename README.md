# mz_bank

`mz_bank` e a camada de ATM/agencia do ecossistema Mazus. O resource nao possui saldo proprio: `wallet` e `bank` pertencem ao `mz_core`, enquanto o extrato e lido do ledger passivo do `mz_economy`.

## Responsabilidades

- `mz_core`: identidade, sessao do personagem, saldos, persistencia, locks, operacoes atomicas, cache e logs.
- `mz_economy`: ledger e extrato; nunca e fonte de saldo.
- `mz_bank`: deteccao de ATM/agencia, sessao curta, regras de canal, cartao, NUI e API bancaria reutilizavel.
- `mz_inventory`: apenas a NUI consumidora do inventario. O dominio e os exports de inventario usados pelo cartao ficam no `mz_core`.

## Ordem de inicio

1. `oxmysql`
2. `ox_lib`
3. `mz_core`
4. `mz_economy` (recomendado para extrato)
5. `mz_inventory`
6. `mz_bank`

`mz_economy` pode ficar indisponivel sem bloquear saldo, saque, deposito ou transferencia; nesse caso, o extrato retorna `statement_unavailable`. O resource nunca volta a gravar `bank_transactions`.

## Configuracao

Os pontos principais ficam em `config.lua`: moeda, distancias, expiracao, limite, taxa, ATMs, agencias, cartao e rate limits. `Debug` fica desativado por padrao. Nao existe saldo inicial no `mz_bank`.

Com `Config.Interaction.UseMzInteract = true`, as agencias sao registradas no `mz_interact` com marcador, texto e blip na mesma coordenada. ATMs sao descobertos pelos modelos fisicos e registrados dinamicamente nas coordenadas reais dos objetos; por padrao eles possuem marcador/interacao, mas nao criam blips no mapa. Se `mz_interact` nao estiver iniciado, `FallbackMarkers` preserva a interacao manual.

O item `bank_card` esta definido em `mz_core/shared/items.lua`. A imagem ja existe em `mz_inventory/web/images/bank_card.png`. O cartao e unico, serializado e vinculado; ele nao armazena saldo nem PIN.

PIN esta preparado no schema (`pin_hash` nullable), mas nao foi implementado sem um mecanismo criptografico confirmado no runtime. `RequirePinAtATM` permanece `false`; se for ativado antes dessa fase, o acesso falha de forma controlada com `pin_unavailable`, sem bypass silencioso.

## Comportamento por canal

| Operacao | ATM | Agencia | Phone futuro |
|---|---:|---:|---:|
| Overview/extrato | sim | sim | sim |
| Saque/deposito fisico | sim | sim | nao |
| Transferencia | sim | sim | sim |
| Emissao/substituicao | nao | sim | gerenciamento futuro |
| Exige item `bank_card` | configuravel | configuravel | nao |

O ATM atual resolve o destinatario por server ID e exige que ele esteja online. O dominio ja aceita um tipo explicito; `account_number`, `phone` e `pix_key` permanecem reservados e retornam erro em vez de fazer SQL inseguro.

Consulte `INTEGRATION.md`, `TEST_PLAN.md` e `LEGACY_BANK_TABLES.md` para contratos e operacao.
