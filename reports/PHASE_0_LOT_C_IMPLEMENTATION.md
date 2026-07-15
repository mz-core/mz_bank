# MZ Bank — Implementação do Lote C da Fase 0

Data: 2026-07-15  
Escopo: somente `B0-07`, `B0-08` e `B0-10`  
Estado: implementação e validação estáticas; runtime e migrations reais não executados

## Diagnóstico confirmado

### B0-07 — Inicialização e dependências

O arquivo efetivo `mz_starter/cfg/resources.cfg`, carregado por `mz_starter/server.cfg`, inicia `oxmysql`, `ox_lib`, `mz_core` e `mz_inventory`, mas não contém `ensure mz_economy` nem `ensure mz_bank`. O manifest do banco exigia apenas `oxmysql`, `ox_lib` e `mz_core`, enquanto o extrato usa o export real `mz_economy:GetAccountStatement` e o cartão físico depende da integração de inventário do core/consumer.

O manifest agora declara as cinco dependências anteriores ao banco. O bootstrap consulta o estado real de cada resource, executa migrations e somente depois libera `MZBankService`. Falta, parada ou erro de migration deixa novas sessões indisponíveis e registra um código explícito. O export server-side novo `GetReadiness` fornece um DTO de diagnóstico sem identificadores de jogador.

O arquivo efetivo de recursos não foi editado automaticamente. Proposta pendente de aprovação:

```cfg
ensure oxmysql
ensure ox_lib
ensure mz_core
ensure mz_economy
ensure mz_inventory
ensure mz_bank
```

Por isso, `B0-07` está **PARCIAL** até essa proposta ser aplicada e testada no servidor real.

### B0-08 — Schema e migrations

`mz_bank_cards` era criado tanto por `sql/001_mz_bank_cards.sql` quanto por `MZBankRepository.prepare()`. O DDL foi removido do repository. A única definição da tabela de cartões agora é a migration `001`.

Foi criado um runner que:

- inicializa o registro `mz_bank_schema_migrations` pela fonte `000`;
- aplica `001_mz_bank_cards.sql` e `002_mz_bank_legacy_reports.sql` em ordem;
- usa DDL idempotente e registra a versão somente depois da validação;
- valida engine InnoDB, colunas, tipos, comprimentos essenciais, auto incremento, índices e unicidade;
- recusa versão mais nova desconhecida, conflito de nome, arquivo ausente ou schema incompatível;
- mantém readiness falso e fornece erro explícito em qualquer falha.

Não foi usado `DROP`, `TRUNCATE`, `DELETE`, migração de dados destrutiva ou execução manual contra o banco. Dados existentes não são apagados.

### B0-10 — Segurança do legado

O fluxo antigo permitia `CONFIRM`, fazia correspondência SQL com `OR`, não tornava conflitos um bloqueio, ignorava saldo negativo e não mantinha relatório persistente.

O novo fluxo permanece desativado por padrão e exige:

- ACE em preview e aplicação;
- referência de backup, referência de autorização e ambiente `staging`;
- preview persistente em `mz_bank_legacy_reports`;
- frase exata `APPLY_REPLACE_IF_OFFICIAL_ZERO` e parâmetros iguais aos do relatório;
- relatório `preview_ready` com no máximo 30 minutos e claim atômico de uso único;
- nenhum jogador conectado;
- repetição do preview e fingerprint idêntico imediatamente antes da transação.

O preview bloqueia identificador duplicado, várias linhas resolvendo para a mesma conta, correspondência ambígua, saldo negativo/decimal/nulo/inválido, conflito com saldo oficial não zerado, linha não correspondida, tabela vazia/ausente ou schema incompatível. A resolução separa match por `citizenid` e `license`, sem join autoritativo com `OR`.

A aplicação não soma valores: cada candidato divergente só pode substituir `mz_player_accounts.bank` quando o saldo oficial ainda é zero. As escritas e a conclusão do relatório participam de uma transação. `bank_accounts` e `bank_transactions` não são apagadas; `bank_transactions` é somente contado e nunca importado.

## Arquivos alterados

- `mz_bank/fxmanifest.lua`: dependências, loader de migrations e inclusão dos SQLs.
- `mz_bank/config.lua`: política fechada do legado, staging, validade e frase forte.
- `mz_bank/server/main.lua`: bootstrap, readiness explícito e reação à parada de dependência.
- `mz_bank/server/service.lua`: fail-closed de sessões existentes quando readiness está falso.
- `mz_bank/server/migrations.lua`: runner versionado e verificação do schema.
- `mz_bank/server/repository.lua`: remoção do DDL duplicado e persistência dos relatórios legados.
- `mz_bank/server/legacy.lua`: preview seguro, bloqueadores, confirmação vinculada e aplicação não aditiva.
- `mz_bank/sql/000_mz_bank_schema_migrations.sql`: registro de versões.
- `mz_bank/sql/002_mz_bank_legacy_reports.sql`: trilha persistente do legado.
- `mz_bank/LEGACY_BANK_TABLES.md`: procedimento administrativo atualizado.
- `mz_bank/SCHEMA_AND_STARTUP.md`: ordem proposta, readiness e fonte de verdade.
- `mz_bank/reports/PHASE_0_BLOCKER_MATRIX.md`: somente `B0-07`, `B0-08` e `B0-10` adicionados/classificados.
- `mz_bank/reports/PHASE_0_LOT_C_IMPLEMENTATION.md`: este relatório.

`mz_bank/sql/001_mz_bank_cards.sql` não precisou mudar; passou a ser consumido diretamente como a única fonte de verdade.

## Contratos reais utilizados

- FiveM/Cfx: `GetResourceState`, `LoadResourceFile`, `GetCurrentResourceName`, `GetPlayers`, `IsPlayerAceAllowed`, `RegisterCommand`, `AddEventHandler` e `onResourceStop`.
- oxmysql: `MySQL.query.await`, `single.await`, `scalar.await`, `insert.await`, `update.await` e `transaction.await` nos formatos já usados por `mz_core` e `mz_economy`.
- mz_core: tabelas oficiais reais `mz_players` (`citizenid` e `license` únicos) e `mz_player_accounts` (`bank BIGINT`, `citizenid` único). O fluxo bancário normal continua usando os serviços oficiais do core; não foi criado saldo paralelo.
- mz_economy: o contrato existente `GetAccountStatement` permanece o provedor do extrato. Nenhum histórico legado é escrito nele.
- mz_inventory: dependência de inicialização solicitada; nenhum export novo foi inventado.

## Validações estáticas executadas

- `luac -p` aprovado para `server/migrations.lua`, `server/repository.lua`, `server/legacy.lua`, `server/main.lua` e `server/service.lua`.
- `node --check` aprovado para o JavaScript NUI preservado.
- Busca confirmou uma única ocorrência executável de `CREATE TABLE IF NOT EXISTS mz_bank_cards`, em `sql/001_mz_bank_cards.sql`.
- Busca confirmou ausência de `MZBankRepository.prepare()`.
- SQLs/runner do Lote C não contêm operação destrutiva.
- O código de aplicação legada não contém soma de saldo nem importação de `bank_transactions`.
- Harness Lua com MySQL simulado aprovou os cenários de preview seguro, identificador duplicado/várias linhas por conta, saldo negativo e conflito com saldo oficial.
- Harness Lua do runner com schema simulado aprovou primeira aplicação, replay idempotente sem novo registro e bloqueio de versão futura desconhecida.
- `mz_starter/cfg/resources.cfg` permaneceu sem alteração automática.

## Riscos e limites

- O resource não iniciará pela configuração efetiva até `mz_economy` e `mz_bank` serem incluídos na ordem proposta.
- A compatibilidade do principal de console/RCON com a ACE configurada precisa ser comprovada em runtime; negação é o comportamento seguro.
- Uma tabela antiga criada com schema divergente não é alterada silenciosamente: readiness falha e exige reconciliação administrativa não destrutiva.
- O fingerprint é uma proteção de mudança entre preview e apply, não uma assinatura criptográfica externa.
- Produção permanece bloqueada por `RequiredEnvironment = 'staging'`; mudar essa política está fora deste lote sem evidência e autorização.

## Testes pendentes

1. Revisar e, se aprovado, aplicar a ordem proposta em `mz_starter/cfg/resources.cfg`.
2. Testar start correto e ausência/parada individual de cada dependência.
3. Testar migrations em banco vazio, banco já compatível, replay, versão incompatível e falha SQL, sempre com backup.
4. Conferir `GetReadiness` antes/depois de sucesso e falha.
5. Testar ACE negada/permitida no principal administrativo real.
6. Gerar preview para cada bloqueador e conferir a linha persistida.
7. Confirmar que `AllowApply = false`, ambiente diferente, frase incorreta, relatório expirado/usado, snapshot alterado e jogadores conectados impedem aplicação.
8. Em staging isolado, testar a substituição somente de saldo oficial zero e confirmar que tabelas/histórico legados ficam intactos.

Nenhum desses testes foi executado ou aprovado neste relatório. A Fase 0 não foi marcada como `[S]` nem validada em runtime.
