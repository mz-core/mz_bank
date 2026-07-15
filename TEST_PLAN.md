# Plano de testes do mz_bank

Os testes abaixo exigem uma instancia FiveM com MySQL. Eles nao sao considerados executados por validacao estatica.

## Preparacao

- Iniciar `oxmysql`, `ox_lib`, `mz_core`, `mz_economy`, `mz_inventory` e `mz_bank` nessa ordem.
- Confirmar no console `mz_bank ready` e executar `mz_bank_legacy_preview` como console/ACE.
- Usar dois personagens carregados e registrar saldos oficiais antes de cada caso.

## Casos principais

1. Sem cartao no ATM: a NUI pode mostrar a tela de insercao, mas `authenticate` deve retornar `card_required`; nenhuma operacao abre o menu ou muda saldo.
2. Primeira visita a agencia: deve abrir sem cartao quando configurado e tentar emitir o primeiro cartao; validar item, metadata e linha ativa em `mz_bank_cards`.
3. Cartao valido: ATM cria sessao, autentica e mostra exatamente `player.money.bank`/`mz_player_accounts.bank`.
4. Cartao de outro titular, bloqueado ou revogado: negar com codigo correspondente e gerar log.
5. Saque: `bank -= valor`, `wallet += valor`, total preservado, cache e banco iguais apos reconnect.
6. Deposito: `wallet -= valor`, `bank += valor`, total preservado.
7. Saldo insuficiente: nenhuma das contas muda.
8. Transferencia: remetente debita uma vez (valor + taxa), destino recebe o valor uma vez e os registros do ledger compartilham `external_ref`.
9. Duplo Enter/clique e dois callbacks concorrentes: somente uma operacao deve passar; observar `operation_busy`/`rate_limited` e ausencia de saldo negativo.
10. Falha de persistencia simulada na segunda query: a transacao SQL deve reverter e o cache nao deve mudar.
11. Afastamento, morte, entrada em veiculo e restart: NUI fecha, focus e restaurado e token posterior falha.
12. `mz_economy` parado: operacoes continuam no core; extrato fica indisponivel/vazio e nenhuma tabela legada recebe escrita.
13. Contexto `phone`: overview/extrato/transferencia funcionam server-to-server; saque e deposito nao sao exportados nesse canal.
14. Segunda via: com configuracao habilitada, emitir novo item antes de revogar credenciais anteriores; falha de inventario deve manter o cartao antigo ativo.

## Concorrencia e recuperacao

Executar saques/depositos simultaneos no mesmo personagem e transferencias cruzadas entre dois personagens. A ordem deterministica de locks deve impedir deadlock. Reiniciar os resources e reconectar para comparar cache, `mz_player_accounts` e ledger.
