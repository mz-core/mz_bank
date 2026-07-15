# MZ Bank — Matriz de bloqueadores da Fase 0

Atualização: 2026-07-15  
Escopo desta versão: Lote A (`B0-01`, `B0-02`, `B0-03`, `B0-04` e `B0-09`), itens `B0-05` e `B0-06` do Lote B e itens `B0-07`, `B0-08` e `B0-10` do Lote C.

Esta matriz foi inicializada durante a implementação do Lote A porque não havia um arquivo anterior no workspace. `ATENDIDO` abaixo significa que a correção está presente no código e passou pelas verificações estáticas descritas; não significa aprovação em runtime nem validação da Fase 0. Nesta atualização do Lote C, somente `B0-07`, `B0-08` e `B0-10` foram incluídos e classificados.

## Lote A

### B0-01 — Canal controlado pelo client

- **Estado:** ATENDIDO (implementação estática; runtime pendente).
- **Evidência:** `server/service.lua`, em `resolvePhysicalContext`, limita a abertura a `atm` ou `branch`; `OpenSession` grava o canal resolvido na sessão; `validateSession`, `GetAccountOverview`, `GetStatement` e `runOperation` derivam as permissões de `session.channel`. `server/main.lua` encaminha overview e operações somente com o token. O fluxo `phone` foi removido de `CHANNEL_PERMISSIONS` e do serviço físico.
- **Risco mitigado:** adulteração de `payload.channel` ou de contexto de operação não seleciona `phone` nem altera o canal vinculado ao token.
- **Resources envolvidos:** `mz_bank`; identidade e movimentação continuam delegadas ao `mz_core`.
- **Correção mínima:** concluída — manter `payload.channel` restrito à criação comprovada da sessão física e usar apenas token nos callbacks posteriores.
- **Dependências:** callbacks de `ox_lib`; identidade de personagem do `mz_core`.
- **Testes estáticos:** busca por `phone` nas superfícies Lua/JS sem ocorrência; `payload.channel` ocorre apenas na resolução/log da abertura; permissões posteriores usam `session.channel`.
- **Testes runtime pendentes:** adulterar `channel=phone` na abertura, overview e transferência; reutilizar token com canal adulterado; confirmar negação sem movimentação.
- **Risco de regressão:** integrações antigas que chamavam exports do banco sem token ou usavam o contexto implícito de phone passam a receber `invalid_session`, por desenho.

### B0-02 — ATM não comprovado pelo servidor

- **Estado:** ATENDIDO (implementação estática; catálogo e runtime pendentes de confirmação no mapa real).
- **Evidência:** `config.lua`, em `Config.ATM.catalog`, contém o catálogo estático de ATMs e a tolerância de correspondência; `server/service.lua`, em `resolveKnownAtm` e `resolvePhysicalContext`, cruza a coordenada solicitada com o catálogo, usa a coordenada canônica e compara com `GetEntityCoords(GetPlayerPed(source))`; coordenada arbitrária retorna `atm_invalid`. `client/main.lua` e `client/interact.lua` só oferecem interação para props próximos de uma entrada do catálogo.
- **Risco mitigado:** estar perto de uma coordenada enviada pelo próprio client deixa de ser prova suficiente de ATM.
- **Resources envolvidos:** `mz_bank`; `mz_interact` apenas para UX de interação, sem autoridade de segurança.
- **Correção mínima:** concluída — allowlist server-side, ponto canônico, validação da posição server-side e independência de network ID/entity handle.
- **Dependências:** server natives do FiveM para ped/coordenadas; catálogo deve refletir o mapa efetivamente usado pelo servidor.
- **Testes estáticos:** catálogo presente; nenhum entity handle é recebido pelo servidor; caminho desconhecido termina em `atm_invalid`; parsers Lua aprovados.
- **Testes runtime pendentes:** validar ATMs vanilla catalogados, coordenada falsa próxima ao jogador, prop não networked, interior/mapa customizado, tolerância e distância de sessão.
- **Risco de regressão:** ATM de MLO/mapa customizado não cadastrado será corretamente negado até sua coordenada real ser adicionada; coordenadas do catálogo precisam ser confrontadas com o build/mapa do servidor.

### B0-03 — Cartão não revalidado

- **Estado:** ATENDIDO (implementação estática; runtime pendente).
- **Evidência:** `server/service.lua`, em `findInventoryCard`, confere item `bank_card`, titular, `cardUid` esperado e credencial persistida com status `active`; `validateSession` repete essa verificação em toda ação autenticada de canal que exige cartão e elimina a sessão ao falhar. `invalidateCardSessions` é chamado no bloqueio e após revogação por substituição.
- **Risco mitigado:** cartão removido, bloqueado, revogado ou substituído deixa de autorizar novas consultas ou movimentações na sessão anterior.
- **Resources envolvidos:** `mz_bank`, facade de inventário do `mz_core`, implementação de inventário integrada pelo core e tabela `mz_bank_cards`.
- **Correção mínima:** concluída — fixar o `cardUid` autenticado na sessão e revalidar item + credencial antes de cada operação.
- **Dependências:** `mz_core:GetPlayerInventory`, metadata real do item, `MZBankRepository.getCard` e atualização consistente de status em `mz_bank_cards`.
- **Testes estáticos:** a revalidação usa exatamente `session.cardUid`; ausência/mismatch/status não ativo apaga `Sessions[source]`; bloqueio/substituição também invalidam sessões correspondentes.
- **Testes runtime pendentes:** remover o item após autenticar; bloquear, revogar e substituir; cartão de outro titular; credencial ausente; inventário indisponível; tentar overview, saque, depósito e transferência após cada mudança.
- **Risco de regressão:** indisponibilidade momentânea do inventário invalida a sessão por segurança; deve-se confirmar em runtime que o facade do core reflete remoções imediatamente.

### B0-04 — Estado físico confiado ao client

- **Estado:** ATENDIDO (implementação estática; server natives e tolerâncias pendentes de runtime).
- **Evidência:** `server/service.lua`, em `getServerPlayerState`, valida ped existente, coordenadas, vida e veículo usando estado server-side. `validateSession` também confirma identidade/citizenid atual, distância da coordenada canônica e ped válido, aplicando tolerância curta somente ao ped ainda indisponível e tolerância inicial somente à comparação de distância. Falhas eliminam a sessão. O fechamento client-side permanece em `client/main.lua` apenas como UX adicional.
- **Risco mitigado:** o client não é mais a única autoridade para distância, morte, veículo, ped ou personagem.
- **Resources envolvidos:** `mz_bank`, estado de personagem do `mz_core`, entidades/natives server-side do FiveM.
- **Correção mínima:** concluída — validar estado físico na abertura e em toda ação protegida; vincular a sessão ao citizenid atual.
- **Dependências:** OneSync/estado de entidade disponível ao servidor e `mz_core:GetPlayer`/`ResolvePlayerIdentity` coerentes com a troca de personagem.
- **Testes estáticos:** todos os caminhos de overview/extrato/operação/cartão passam por `validateSession`; falhas físicas removem a sessão; sintaxe Lua aprovada.
- **Testes runtime pendentes:** morrer, entrar em veículo, afastar-se, trocar personagem, ped inexistente durante e depois da tolerância, abrir imediatamente após spawn e reiniciar resource.
- **Risco de regressão:** latência de criação do ped ou diferenças do server native podem produzir negação conservadora; as tolerâncias precisam de aferição no servidor real.

### B0-09 — Superfície interna indevida

- **Estado:** ATENDIDO (implementação estática; runtime pendente).
- **Evidência:** `client/main.lua` envia na transferência apenas `recipientValue` e `amount`; `server/main.lua` reconstrói um DTO restrito e ignora campos extras. `server/service.lua`, em `resolveServerIdRecipient`, aceita apenas server ID inteiro, positivo, online e diferente do remetente. `ResolveRecipient` devolve ao chamador somente `name`. O overview fornece `account = 'Conta corrente'`, sem máscara derivada de citizenid. `createToken` gera valor opaco sem source/citizenid, que permanecem associados somente em `Sessions`. O bridge não expõe mais `GetSourceByCitizenId` ao banco.
- **Risco mitigado:** o client não seleciona resolução por citizenid, não escolhe `recipientType` arbitrário e não recebe source/citizenid/cardUid no overview ou resolução de destinatário.
- **Resources envolvidos:** `mz_bank`, resolução de player e transferência oficial do `mz_core`.
- **Correção mínima:** concluída — destinatário físico limitado a server ID online; DTOs client-facing sem identificadores internos.
- **Dependências:** `mz_core:GetPlayer` para resolver o server ID e `mz_core:TransferBankBetweenPlayers` para executar a transferência.
- **Testes estáticos:** buscas por `recipientType`, `GetSourceByCitizenId` e `accountMask` sem ocorrências; callback client-facing não recebe source/citizenid no payload; DTO de resolução contém apenas `name`; token não concatena identificadores internos.
- **Testes runtime pendentes:** injetar `recipientType`, `citizenid`, `source` e campos extras; usar ID decimal, texto, offline, próprio e válido; inspecionar mensagens NUI e respostas dos callbacks.
- **Risco de regressão:** a transferência física deixa de aceitar citizenid e destinatário offline; qualquer consumidor que dependia dessa superfície indevida precisa ser removido ou redesenhado em fase futura autorizada.

## Lote B — itens autorizados nesta atualização

### B0-05 — Resultado financeiro ambíguo

- **Estado:** ATENDIDO (implementação e revisão estáticas; runtime pendente).
- **Evidência:** `mz_core/server/accounts/service.lua` preserva o `transactionRef` oficial e recupera resultados por chave; `mz_core/server/accounts/repository.lua` grava a confirmação em `mz_account_idempotency` na mesma transação SQL da alteração de saldo; `mz_bank/server/service.lua` devolve `confirmed`, `correlationId`, `transactionRef` e `replayed` antes de tratar overview/extrato como complemento. Falha de refresh produz `refreshError` sem trocar `ok = true` por falha.
- **Risco mitigado:** timeout, replay da mesma chave, clique repetido ou restart não autorizam uma segunda movimentação já confirmada; o resultado persistido mantém a referência original.
- **Resources envolvidos:** `mz_bank` fornece a chave e o DTO; `mz_core` mantém locks, atomicidade, saldo e deduplicação transacional; `mz_economy` permanece ledger best effort posterior ao commit.
- **Correção mínima:** concluída — deduplicação persistente das operações atuais, sem outbox no `mz_bank` e sem saldo paralelo.
- **Dependências:** tabela `mz_account_idempotency` preparada pelo `mz_core`, `external_ref`/`transactionRef` real do core e callbacks `ox_lib`.
- **Testes estáticos:** parsers Lua/JavaScript aprovados; harness com os serviços reais e repositório simulado executou transferência entre contas e transferência entre jogadores duas vezes com a mesma chave, observando uma única escrita e a mesma referência com `replayed = true`; também cobriu recuperação com destinatário offline e conflito de payload.
- **Testes runtime pendentes:** timeout após commit, duplo clique/Enter, replay após reconnect/restart, falha de overview/extrato, concorrência real no MySQL e inspeção de uma única alteração em saldo/ledger.
- **Risco de regressão:** consumidores server-side do export `Transfer` precisam fornecer `context.idempotencyKey`; a tabela mínima ainda não possui retenção administrativa, reconciliação de ledger ou worker de outbox, que permanecem fora deste lote.

### B0-06 — Contrato de valores e limites

- **Estado:** ATENDIDO (implementação e revisão estáticas; runtime pendente).
- **Evidência:** `mz_bank/server/service.lua` aceita apenas `number` inteiro, positivo, finito e até o limite do canal/operação; texto, decimal, zero, negativo, `NaN` e infinito são rejeitados. `config.lua` define `withdraw`, `deposit` e `transfer` para `atm` e `branch`, todos em `1.000.000`, declara ausência de limite diário e fixa arredondamento de taxa em `floor`.
- **Risco mitigado:** valores deixam de ser truncados silenciosamente e nenhum canal herda limite implícito escolhido pelo client.
- **Resources envolvidos:** validação de entrada no `mz_bank`; saldos oficiais `BIGINT` e execução no `mz_core`.
- **Correção mínima:** concluída — contrato estrito antes de chamar o core, com teto efetivo também limitado ao inteiro seguro do Lua/JSON (`9.007.199.254.740.991`), inferior ao `BIGINT` assinado do schema.
- **Dependências:** `Config.TransactionLimits`, `Config.TransferFeePercent` e `Config.TransferFeeRounding`.
- **Testes estáticos:** harness executou inteiro mínimo/máximo, decimal, zero, negativo, texto, `NaN`, infinito e excesso de limite; também confirmou taxa zero e arredondamento para baixo.
- **Testes runtime pendentes:** injeção de cada classe inválida nos callbacks, limites `999.999`/`1.000.000`/`1.000.001` por canal/operação e conferência de taxa/correlationId no core e ledger.
- **Risco de regressão:** integrações antigas que enviavam valor como string passam a receber `invalid_amount`, conforme o novo contrato; não há limite diário e nenhum teste pode tratá-lo como funcionalidade existente.

## Lote C — itens autorizados nesta atualização

### B0-07 — Inicialização e dependências

- **Estado:** ATENDIDO (implementação e revisão estáticas; runtime pendente).
- **Evidência:** `mz_starter/cfg/resources.cfg` contém `oxmysql`, `ox_lib`, `mz_core`, `mz_economy`, `mz_inventory` e `mz_bank` na ordem exigida. O manifest mantém como rígidas somente as dependências necessárias ao serviço financeiro e ao cartão. `server/main.lua` fecha o banco quando falta uma dependência rígida e trata `mz_economy` como observado/degradável, coerente com o ledger best effort e com `README.md`/`TEST_PLAN.md`.
- **Política confirmada:** sem `mz_economy`, o extrato fica indisponível e `GetReadiness` sinaliza degradação; saldo, saque, depósito e transferência continuam exclusivamente no `mz_core`.
- **Testes runtime pendentes:** start na ordem efetiva, ausência/parada de cada dependência rígida, parada/retorno do `mz_economy`, erro explícito, restart e consulta ao readiness.

### B0-08 — Schema e migrations

- **Estado:** ATENDIDO (implementação e verificação estáticas; execução em banco real pendente).
- **Evidência:** `sql/001_mz_bank_cards.sql` é a única definição de `mz_bank_cards`; o DDL foi removido de `server/repository.lua`. `server/migrations.lua` aplica as versões `001` e `002`, registra em `mz_bank_schema_migrations`, valida engine/colunas/índices/versão e só libera o serviço após sucesso.
- **Risco mitigado:** divergência entre SQL e prepare local, serviço aceitando chamadas com schema incompleto e evolução silenciosa incompatível.
- **Testes estáticos:** uma única ocorrência de `CREATE TABLE IF NOT EXISTS mz_bank_cards`; nenhum `DROP`, `TRUNCATE` ou `DELETE` nos SQLs/runner; sintaxe Lua aprovada.
- **Testes runtime pendentes:** banco vazio, schema já correto sem registro, replay, versão conflitante/mais nova, arquivo/coluna/índice ausente, erro SQL e persistência de dados existentes.

### B0-10 — Segurança do legado

- **Estado:** ATENDIDO (implementação e verificação estáticas; aplicação permanece desativada e runtime pendente).
- **Evidência:** `config.lua` mantém `AllowApply = false`; `server/legacy.lua` exige ACE também no preview, detecta identificadores duplicados, várias linhas por conta, ambiguidade, saldo negativo/inválido, conflitos e não correspondidos. Preview, backup, autorização, ambiente, fingerprint e resultado são persistidos em `mz_bank_legacy_reports`.
- **Risco mitigado:** saldo duplicado por soma, resolução `OR` ambígua, aplicação sobre saldo oficial divergente, execução sem preview vinculante e ausência de trilha administrativa.
- **Salvaguardas:** frase forte e parâmetros idênticos ao relatório, preview com validade de 30 minutos, novo snapshot antes do update, staging obrigatório, zero jogadores, somente `bank = 0`, transação, tabelas legadas preservadas e histórico não importado.
- **Testes estáticos:** não há `SUM` de saldo, `DROP`, `TRUNCATE`, `DELETE` nem importação de `bank_transactions`; sintaxe Lua aprovada.
- **Testes runtime pendentes:** ACE/negação, cada bloqueador, relatório persistente, snapshot alterado/expirado, aplicação desativada, servidor ocupado, rollback SQL, replay do report e conferência de zero alteração nas tabelas legadas.

## Estado da fase

- Fase 0 não foi marcada como validada.
- Nenhum teste runtime foi executado ou aprovado neste documento.
- `B0-05`, `B0-06`, `B0-07`, `B0-08` e `B0-10` não foram marcados em runtime. Todos possuem implementação estática; nenhum item foi marcado como aprovado em runtime.
