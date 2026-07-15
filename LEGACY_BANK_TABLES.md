# Tabelas legadas do mz_bank v0

`bank_accounts` e `bank_transactions` nao sao mais criadas, lidas ou gravadas pelo fluxo bancario. Elas nao sao apagadas automaticamente.

Use no console:

```text
mz_bank_legacy_preview
```

O preview informa existencia, quantidade de contas/transacoes, identificadores correspondentes, nao correspondentes, divergencias e conflitos. Correspondencia tenta `citizenid` e `license` apenas para auditoria/migracao; license nunca e mostrada na NUI.

Nunca some o saldo legado ao oficial. Isso pode duplicar dinheiro. A estrategia fornecida e `replace_if_official_zero`: substitui apenas contas oficiais zeradas, exige `Config.LegacyMigration.AllowApply = true`, comando com `CONFIRM`, ACE e nenhum player conectado:

```text
mz_bank_legacy_apply CONFIRM
```

Antes de habilitar, exporte backup, revise todos os `unmatched` e `conflicts` e registre a autorizacao administrativa. O comando mantem as tabelas legadas. Se o saldo oficial nao estiver zerado, a linha e deliberadamente ignorada para revisao manual.

O historico `bank_transactions` nao e importado automaticamente para `mz_economy`, pois nao ha garantia de idempotencia ou correlacao com operacoes ja registradas. Uma eventual importacao deve ser uma ferramenta offline separada e auditada.
