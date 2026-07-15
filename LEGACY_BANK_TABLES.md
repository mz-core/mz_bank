# Tabelas legadas do mz_bank v0

`bank_accounts` e `bank_transactions` não são usadas pelo fluxo bancário normal. Elas não são criadas, apagadas nem alteradas automaticamente pelo `mz_bank`. O histórico legado nunca é importado automaticamente para o `mz_economy`.

## Segurança padrão

- `Config.LegacyMigration.AllowApply` permanece `false`.
- Os dois comandos exigem a ACE configurada em `Config.LegacyMigration.Ace`.
- O ambiente aceito nesta fase é `staging`.
- Nenhum saldo legado é somado ao saldo oficial.
- A única estratégia disponível é `replace_if_official_zero`.
- A aplicação é recusada enquanto houver jogadores conectados, protegendo o cache do `mz_core`.
- As tabelas legadas são preservadas após preview ou aplicação.

Conceda a ACE somente ao principal administrativo responsável. Exemplo de proposta para a configuração ACE, a ser revisada antes de uso:

```cfg
add_ace group.mz_owner group.mz_owner allow
```

O nome acima preserva o contrato existente de `Config.LegacyMigration.Ace`. Se o servidor adotar um objeto ACE dedicado, altere a configuração e a regra juntas. O comando também executa a verificação ACE quando chamado pelo console/RCON; confirme esse principal no ambiente real antes do ensaio.

## Preview obrigatório e persistente

Registre primeiro uma referência de backup e uma referência de autorização. Elas aceitam de 6 a 128 caracteres alfanuméricos, ponto, sublinhado, dois-pontos ou hífen:

```text
mz_bank_legacy_preview <backup_ref> <authorization_ref> STAGING
```

O preview cria uma linha em `mz_bank_legacy_reports` e imprime o `report_uid`. Ele bloqueia a aplicação ao encontrar:

- identificador legado repetido;
- identificadores diferentes que resolvem para a mesma conta oficial;
- correspondência ambígua entre `citizenid` e `license`;
- saldo negativo, decimal, nulo ou inválido;
- saldo oficial não zerado e divergente;
- conta legada sem personagem/conta oficial correspondente;
- tabela ausente, vazia ou com schema incompatível.

O relatório guarda resumo, referências administrativas, ambiente, estratégia, estado e fingerprint do snapshot. Identificadores individuais não são impressos no console nem incluídos no JSON resumido.

## Confirmação forte

Somente depois de revisar um relatório `preview_ready`, testar em staging e habilitar deliberadamente `AllowApply = true`, use exatamente:

```text
mz_bank_legacy_apply APPLY_REPLACE_IF_OFFICIAL_ZERO <report_uid> <backup_ref> <authorization_ref> STAGING
```

O relatório deve ter no máximo 30 minutos, e todas as referências devem coincidir. Antes do primeiro `UPDATE`, o código refaz o preview, exige o mesmo fingerprint e nenhum bloqueador, e faz um claim atômico do relatório para impedir aplicação concorrente/replay. Cada candidato é escrito somente em `mz_player_accounts.bank` com `bank = 0`; não existe `SUM`, merge aditivo ou criação de saldo paralelo. O resultado `applied`/`failed` fica persistido em `mz_bank_legacy_reports`.

Produção continua bloqueada por `RequiredEnvironment = 'staging'`. Uma liberação futura para produção exige aprovação explícita após evidência do ensaio, nova referência de backup e nova autorização.

## Histórico

`bank_transactions` é apenas contado no preview. Não há importação automática porque não existe garantia de idempotência ou correlação com operações já registradas. Qualquer migração de histórico deverá ser uma ferramenta offline separada, auditada e autorizada em outra fase.
