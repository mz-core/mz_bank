# MZ Bank — Roadmap de Estabilização e Evolução

> Documento de arquitetura, execução e aprovação do `mz_bank`.
>
> Este roadmap descreve o estado real do recurso, os riscos conhecidos, a ordem segura de evolução e as evidências necessárias para aprovar cada fase.
>
> Uma funcionalidade implementada não é considerada aprovada até cumprir seus critérios estáticos e de runtime.

---

## 1. Objetivo

O `mz_bank` é o domínio de acesso bancário do ecossistema Mazus. Ele deve oferecer:

- atendimento em ATM e agência;
- sessões e autenticação por canal;
- cartões bancários;
- consulta de saldo e extrato;
- saque, depósito e transferência;
- API bancária para recursos autorizados;
- futura integração com `mz_phone`;
- identidade bancária pública;
- auditoria e comprovantes correlacionados.

O `mz_bank` não é e não deve se tornar a fonte de verdade do dinheiro.

---

## 2. Arquitetura oficial

### 2.1 `mz_core`

Fonte única de:

- identidade interna do jogador;
- `citizenid`;
- cache do jogador;
- saldos `wallet`, `bank` e demais contas canônicas;
- persistência em `mz_player_accounts`;
- locks financeiros;
- validação de fundos;
- movimentações financeiras;
- atomicidade das alterações de saldo;
- criação da referência oficial da transação;
- persistência futura da outbox financeira.

O `mz_core` deve concluir saldo e outbox na mesma transação SQL.

### 2.2 `mz_economy`

Responsável por:

- ledger;
- extrato;
- categorias e motivos;
- relatórios;
- auditoria financeira;
- estatísticas;
- consumo idempotente da outbox;
- reconciliação.

O `mz_economy` nunca mantém saldo paralelo.

### 2.3 `mz_bank`

Responsável por:

- ATM e agência;
- sessões bancárias;
- autenticação por canal;
- validação de proximidade;
- ciclo de vida de cartões;
- identidade bancária pública;
- limites específicos do canal;
- NUI;
- contratos bancários compartilhados;
- adaptação de erros e respostas para cada canal.

O `mz_bank` não escreve saldo no banco de dados e não contorna os serviços financeiros do `mz_core`.

### 2.4 `mz_phone`

Responsável somente pela experiência móvel e pela sessão do aparelho.

O aplicativo bancário:

- consome a API server-to-server do `mz_bank`;
- não chama diretamente operações financeiras do `mz_core`;
- não mantém saldo;
- não cria ledger;
- não transforma dados da NUI em contexto autenticado.

### 2.5 Contas de organizações

O `mz_bank` pode oferecer o canal de acesso, mas não deve ser dono do saldo empresarial.

Antes da Fase 7, o projeto deve definir formalmente se a fonte de verdade das contas organizacionais ficará no `mz_core` ou em um domínio oficial de organizações integrado ao core.

---

## 3. Princípios obrigatórios

1. Existe uma única fonte de verdade para cada saldo.
2. Cartão é credencial; cartão nunca armazena dinheiro.
3. A NUI e o client Lua não são confiáveis.
4. O client nunca escolhe o canal autorizado de uma operação.
5. O servidor deriva identidade, canal, permissões e localização.
6. Nenhum callback client-facing aceita `source`, `citizenid` ou conta interna escolhidos pelo client.
7. Toda movimentação possui `correlationId` oficial.
8. Toda operação repetível possui chave de idempotência.
9. Transferências de saldo são atômicas.
10. Um erro de refresh não transforma uma operação confirmada em operação desconhecida.
11. ATM, agência, telefone e admin possuem autenticação e capacidades diferentes.
12. Cartão bloqueado, revogado ou removido deve perder validade conforme a política do canal.
13. Ledger offline não pode causar perda permanente do evento financeiro.
14. Tabelas legadas nunca participam do fluxo normal.
15. Migração de saldo nunca soma automaticamente valor legado ao oficial.
16. Funcionalidades avançadas não avançam sem aprovação das dependências.

---

## 4. Estados das fases

Usar somente:

- `[ ] Não iniciada`
- `[~] Em implementação`
- `[S] Validada estaticamente`
- `[R] Aprovada em runtime`
- `[!] Bloqueada`
- `[X] Cancelada`

Regras:

- código existente pode continuar em `[~]`;
- revisão de código e sintaxe permitem `[S]`;
- somente evidência em FiveM staging permite `[R]`;
- uma fase dependente não inicia enquanto o gate anterior não estiver aprovado;
- nenhum checklist é marcado por suposição;
- teste não executável deve ser registrado como bloqueio, não como falha de runtime.

---

## 5. Estado real resumido

| Fase | Estado | Observação |
|---|---|---|
| 0 — Estabilização da base atual | `[S]` | B0-01 a B0-10 validados estaticamente; runtime posterior registrado |
| 1 — Validação runtime crítica | `[R]` | Testes manuais no FiveM aprovados conforme resultado fornecido pelo usuário |
| 2 — Identidade bancária pública | `[R]` | P2-A a P2-H aprovados em runtime; 109 casos aprovados e zero falhas conhecidas |
| 3 — Idempotência, outbox e auditoria | `[ ]` | Ledger atual é best effort |
| 4 — API bancária compartilhada | `[~]` | Existem exports parciais, ainda sem autenticação completa de canal |
| 5 — Cartão bancário completo | `[~]` | Emissão, bloqueio e substituição existem parcialmente |
| 6 — Aplicativo no `mz_phone` | `[ ]` | Não existe sessão bancária de telefone aprovada |
| 7 — Contas empresariais | `[ ]` | Domínio do saldo ainda precisa ser decidido |
| 8 — Recursos avançados | `[ ]` | Backlog futuro |

---

# Fase 0 — Estabilização da base atual

**Status:** `[S] Validada estaticamente`

## Objetivo

Corrigir defeitos conhecidos antes de iniciar a validação runtime formal.

Esta fase não adiciona novos produtos bancários.

## Base já existente

- saldo oficial no `mz_core`;
- saque como `bank -> wallet`;
- depósito como `wallet -> bank`;
- transferência entre jogadores online;
- locks financeiros no core;
- persistência antes da atualização de cache;
- ledger passivo no `mz_economy`;
- sessões físicas server-side;
- cartão vinculado ao titular;
- NUI de ATM/agência;
- fluxo legado isolado e aplicação desativada por padrão;
- ausência de eventos financeiros antigos no `mz_bank`.

## Bloqueadores obrigatórios

### B0-01 — Canal controlado pelo client

O callback client-facing não pode usar `payload.channel` para selecionar o fluxo `phone`.

Correção:

- callbacks físicos derivam o canal exclusivamente da sessão;
- o token identifica a sessão e seu canal;
- o fluxo `phone` não é alcançável por callback físico;
- adulterar `channel` retorna erro e não executa operação.

### B0-02 — ATM não comprovado pelo servidor

Uma coordenada próxima ao jogador não prova que existe um ATM.

Correção:

- criar allowlist/cache server-side de ATMs válidos;
- cruzar coordenada observada com um ATM conhecido;
- documentar o tratamento de props não networked;
- negar coordenadas arbitrárias.

### B0-03 — Cartão não revalidado

Operações sensíveis devem aplicar a política de revalidação definida para o canal.

No ATM:

- conferir se a credencial continua ativa;
- conferir se o item continua presente quando essa for a regra;
- invalidar a sessão ao bloquear, revogar ou substituir o cartão;
- impedir uso após remoção do item.

### B0-04 — Estado físico confiado ao client

O servidor deve negar operação quando o jogador:

- estiver morto;
- estiver em veículo, se o canal proibir;
- estiver fora da distância;
- tiver mudado de personagem;
- não possuir ped válido depois da tolerância prevista.

O fechamento client-side continua existindo como UX, não como controle de segurança.

### B0-05 — Resultado financeiro ambíguo

O resultado confirmado da movimentação deve ser separado do refresh visual.

Correção:

- primeiro retornar estado final da operação e referência;
- tratar overview/extrato como dados complementares;
- não responder falha apenas porque o refresh posterior falhou;
- implementar uma chave de idempotência para as operações financeiras atuais;
- persistir ou recuperar o resultado necessário para que retry depois de timeout não movimente saldo novamente.

### B0-06 — Contrato de valores e limites

Decidir e documentar:

- valores devem ser inteiros;
- decimal deve ser rejeitado, não truncado silenciosamente;
- limite por operação;
- existência ou remoção do requisito de limite diário;
- política de taxa e arredondamento;
- valor máximo compatível com o schema do core.

O teste de limite diário não pode permanecer obrigatório se a funcionalidade não existir.

### B0-07 — Inicialização e dependências

Corrigir e comprovar a ordem:

```cfg
ensure oxmysql
ensure ox_lib
ensure mz_core
ensure mz_economy
ensure mz_inventory
ensure mz_bank
```

O arquivo efetivo de recursos do servidor deve iniciar `mz_economy` e `mz_bank`.

### B0-08 — Schema e migrations

Definir uma fonte de verdade para `mz_bank_cards`.

Requisitos:

- migration versionada;
- aplicação idempotente;
- verificação de versão/readiness no runtime;
- nenhuma evolução de schema duplicada entre SQL e `repository.prepare()`;
- falha de migration mantém o serviço indisponível com erro explícito.

### B0-09 — Superfície interna indevida

No fluxo client-facing:

- remover resolução por `citizenid`;
- não devolver identificadores internos ao client;
- não aceitar `recipientType` arbitrário;
- limitar o ATM ao tipo de destinatário oficialmente suportado.

### B0-10 — Segurança do legado

Antes de permitir `mz_bank_legacy_apply`:

- detectar titulares duplicados;
- detectar múltiplas linhas que resolvem para a mesma conta;
- recusar saldos negativos;
- recusar conflitos não aprovados;
- gerar relatório persistente;
- exigir backup e autorização registrados;
- executar em staging antes de produção.

## Critérios de aprovação estática

- [x] Client não seleciona o caminho `phone`.
- [x] Canal físico é obtido da sessão.
- [x] ATM arbitrário é negado.
- [x] Morte e veículo são validados no servidor.
- [x] Cartão bloqueado/revogado perde validade na sessão.
- [x] Remoção do item segue política documentada.
- [x] Valores decimais são tratados conforme contrato.
- [x] Resultado financeiro não depende do refresh posterior.
- [x] Retry da mesma operação não movimenta saldo novamente.
- [x] Nenhum `citizenid` livre é aceito no callback público.
- [x] Inicialização real inclui as dependências.
- [x] Migration possui uma única fonte de verdade.
- [x] Sintaxe Lua e JavaScript aprovada.
- [x] Revisão de abuso client-side aprovada.

## Gate da fase

```text
Fase 0: [S] Validada estaticamente
```

Somente depois desse gate a Fase 1 pode ser executada formalmente.

---

# Fase 1 — Validação runtime crítica

**Status:** `[R] Aprovada em runtime`

**Dependência:** conclusão estática da Fase 0.

**Registro runtime:** o usuário informou em 2026-07-15 que os testes dos Lotes A, B e C e os testes financeiros da Fase 1 foram executados manualmente no FiveM e passaram. Nenhuma evidência adicional foi anexada; zero falhas pendentes conhecidas foram informadas.

## Objetivo

Comprovar em FiveM staging que a base atual preserva saldo, cache, persistência, autenticação e invariantes sob uso normal, abuso e falha.

## Preparação obrigatória

- servidor de staging isolado;
- MySQL com backup e dados descartáveis;
- dois jogadores e dois personagens carregados;
- cartões válidos, bloqueados, revogados e de outro titular;
- comandos ou flags de fault injection;
- queries de conferência;
- captura de console;
- versão dos resources registrada;
- relatório criado antes do primeiro teste.

## Catálogo mínimo

### Inicialização — RT-INIT

- [x] Todos os recursos iniciam na ordem oficial.
- [x] `mz_bank` só fica ready depois do schema.
- [x] Item `bank_card` está disponível.
- [x] Restart do banco não altera saldos.
- [x] Restart da economia não altera saldos.
- [x] Restart do core reconstrói o cache.
- [x] Nenhuma tabela de saldo paralela é criada.
- [x] Nenhum export ou callback fica ausente.

### Sessão e canal — RT-SESSION

- [x] Abrir agência válida.
- [x] Negar agência falsa.
- [x] Abrir ATM válido.
- [x] Negar ATM inexistente.
- [x] Negar abertura distante.
- [x] Negar canal adulterado.
- [x] Negar callback sem sessão.
- [x] Negar token falso, expirado ou de outro jogador.
- [x] Negar token de outro canal.
- [x] Invalidar sessão ao afastar.
- [x] Invalidar ou negar operação ao morrer.
- [x] Invalidar ou negar operação em veículo.
- [x] Limpar sessão no disconnect e restart.

### Cartão — RT-CARD

- [x] ATM sem cartão é negado.
- [x] Cartão válido autentica.
- [x] Cartão de outro titular é negado.
- [x] Cartão bloqueado é negado.
- [x] Cartão revogado é negado.
- [x] Bloqueio durante a sessão impede nova operação.
- [x] Remoção do item durante a sessão segue a política aprovada.

### Depósito e saque — RT-CASH

- [x] Valores válidos preservam `wallet + bank`.
- [x] Todo o saldo permitido pode ser movimentado.
- [x] Saldo insuficiente não altera nenhuma conta.
- [x] Zero, negativo, texto e decimal inválido são negados.
- [x] Limite por operação é respeitado.
- [x] Limite diário é testado somente se implementado.
- [x] Duplo clique não duplica operação.
- [x] Cache e banco permanecem iguais após reconnect.
- [x] Ledger usa a mesma referência da operação.

### Transferência — RT-TRANSFER

- [x] Transferência válida debita e credita uma única vez.
- [x] Destinatário inexistente ou offline é negado corretamente.
- [x] Autotransferência é negada.
- [x] Taxa segue o contrato.
- [x] Transferências cruzadas não causam deadlock.
- [x] Múltiplas transferências não gastam o mesmo saldo.
- [x] Disconnect de uma das pontas não produz estado parcial.
- [x] Falha SQL reverte as duas pontas.
- [x] Cache só muda depois do commit.
- [x] As duas pontas compartilham `correlationId`.

### Resposta ambígua — RT-RETRY

- [x] Timeout do client após commit não duplica retry.
- [x] Reenvio da mesma chave retorna o mesmo resultado.
- [x] Falha de overview não oculta uma transferência confirmada.
- [x] Restart durante operação termina em estado reconciliável.

## Invariantes

Sem taxa:

```text
wallet_antes + bank_antes + saldos_destino_antes
=
wallet_depois + bank_depois + saldos_destino_depois
```

Com taxa:

```text
saldo_total_antes
=
saldo_total_depois + taxa_registrada
```

Para toda operação confirmada:

```text
cache = persistência
```

## Entregável

`RUNTIME_REPORT_PHASE_1.md`, contendo:

- ambiente;
- commit/versão dos recursos;
- migrations;
- casos executados;
- evidências;
- queries antes e depois;
- bugs;
- correções;
- repetições;
- decisão de aprovação.

## Gate

```text
Fase 1: [R] Aprovada em runtime
```

---

# Fase 2 — Identidade bancária pública

**Status:** `[R] Aprovada em runtime`

**Lote P2-A:** `[R] Aprovado em runtime` — 27 testes executáveis aprovados manualmente no MySQL/FiveM staging conforme resultado fornecido pelo usuário; 1 caso não aplicável por ausência deliberada do gerador. Migration v3, schema/readiness e política pura de formato/DV aprovados; criação, backfill, resolução e cutover ainda não iniciados.

**Lote P2-B:** `[R] Aprovado em runtime` — 13 de 13 casos aprovados no MySQL/FiveM staging conforme resultados fornecidos pelo usuário. O repository interno read-only, concorrência, privacidade, ausência de alteração financeira, restart, regressão física, limpeza e desativação do runner foram confirmados. A feature pública permanece desligada, sem criação, DTO, overview, backfill, resolução pública, transferência por conta ou alteração da NUI.

**Lote P2-C:** `[R] Aprovado em runtime` — criação preguiçosa idempotente, geração CSPRNG por `RANDOM_BYTES(4)` ou fallback server-side `crypto.randomBytes(4)` com rejeição uniforme, retry de colisão, DTO próprio e integração ao overview autenticado aprovados em 15 de 15 casos no MySQL/FiveM staging conforme resultados fornecidos pelo usuário. Zero falhas e zero bloqueados. Transferência por server ID, saldos oficiais e fluxos físicos permanecem inalterados. A Fase 2 continua `[~]`.

**Lote P2-D:** `[R] Aprovado em runtime` — 8 de 8 gates aprovados no MySQL/FiveM staging conforme resultados fornecidos pelo usuário. Preview, ACE, confirmação forte, apply controlado, paginação, concorrência, retomada idempotente, estados/falhas injetados, auditoria sem PII e regressão física foram confirmados. Zero falhas e zero bloqueados. Runner e apply ficaram desligados após o teste; nenhum saldo foi lido ou escrito pelo backfill. A Fase 2 continua `[~]`; o P2-E é acompanhado separadamente abaixo.

**Lote P2-E:** `[R] Aprovado em runtime` — 12 de 12 casos aprovados no FiveM staging conforme resultados fornecidos pelo usuário. Resolução privada por rota exata, DTO mínimo mascarado, token CSPRNG de 60 segundos, vínculo ao ator/sessão/canal, revalidação do alvo, respostas antienumeração, limites, cooldown, concorrência, auditoria sem PII e ausência de movimentação financeira foram confirmados. O smoke test físico/financeiro passou e o runner foi desativado. Zero falhas e zero bloqueados; o P2-F é acompanhado separadamente abaixo.

**Lote P2-F:** `[R] Aprovado em runtime` — 16 de 16 casos aprovados no FiveM staging conforme resultados fornecidos pelo usuário. Runner interno 14/14, transferência real de R$1, replay, conflito, persistência, cache, correlationId, estados, concorrência, falhas, privacidade, restart e regressão foram confirmados. Zero falhas e zero bloqueados; runner desativado. Não houve timeout SQL destrutivo real, conforme limitação registrada. Na aprovação isolada deste lote, o P2-G ainda não havia sido implementado.

**Lote P2-G:** `[R] Aprovado em runtime` — 15 de 15 casos aprovados manualmente no FiveM staging conforme resultado fornecido pelo usuário. O cutover para agência/conta/DV, resolução privada, confirmação por token, transferência, idempotência, comprovante, privacidade, estados, restart e regressão física/financeira foram confirmados. Zero falhas e zero bloqueados; na aprovação isolada desse lote, a Fase 2 permaneceu `[~]` até a revisão P2-H.

**Lote P2-H:** `[R] Aprovado em runtime` — a revisão final encontrou e corrigiu a dependência da convar transitória e a ausência dos gates de estado em saque/depósito. Os 3 testes delta foram executados manualmente no FiveM staging e aprovados conforme confirmação do usuário. Zero falhas e zero bloqueados; a Fase 2 foi aprovada em runtime.

## Objetivo

Substituir server ID e identificadores internos por uma identidade bancária persistente.

## Modelo inicial

Tabela sem saldo:

```text
mz_bank_accounts
```

Campos mínimos:

```text
id
citizenid
branch
account_number
check_digit
account_type
status
created_at
updated_at
closed_at
metadata_json
```

## Regras

- saldo permanece no domínio financeiro oficial;
- `citizenid` é apenas chave interna;
- número público é persistente e único;
- dígito possui algoritmo documentado;
- criação é idempotente;
- colisão é resolvida com retry;
- cardinalidade por titular e tipo de conta é explícita;
- conta encerrada não é reutilizada;
- estados de bloqueio, congelamento e encerramento têm semânticas diferentes;
- consulta pública devolve DTO mínimo;
- resolução ocorre exclusivamente no servidor.

## Índices mínimos

- unicidade de `(branch, account_number, check_digit)`;
- unicidade por titular/tipo conforme a política escolhida;
- índice por `citizenid`;
- índice por `status`.

## Entregáveis

- migration idempotente;
- `ACCOUNT_IDENTITY.md`;
- serviço de criação/consulta/resolução;
- backfill controlado para jogadores existentes;
- atualização da NUI;
- transferência por conta pública;
- remoção do server ID como destino definitivo.

## Critérios de aprovação

- [x] Conta duplicada é impossível.
- [x] Repetir criação devolve a mesma conta.
- [x] `citizenid` não aparece na interface pública.
- [x] Server ID não é usado como conta.
- [x] Conta persiste após reconnect e restart.
- [x] Estados da conta são aplicados no servidor.
- [x] Enumeração não expõe dados pessoais.
- [x] Transferência por conta é aprovada em runtime.

---

# Fase 3 — Idempotência, outbox e auditoria

**Status:** `[R] Aprovada em runtime — P3-A a P3-G concluídos`

## Objetivo

Garantir que uma movimentação confirmada nunca perca seu evento e que retries não dupliquem saldo ou extrato.

## Decisão arquitetural

A outbox deve ser gravada pelo `mz_core`, porque somente o core pode persistir saldo e evento na mesma transação.

O `mz_bank` fornece contexto e chave de idempotência. O `mz_economy` consome os eventos.

## Modelo

```text
mz_financial_outbox
```

Campos mínimos:

```text
id
correlation_id
idempotency_key
event_type
source_citizenid
target_citizenid
account
amount
fee
reason
source_resource
source_channel
metadata_json
status
attempts
next_retry_at
created_at
processed_at
last_error
```

## Requisitos

- saldo e outbox na mesma transação;
- unicidade por `correlation_id`;
- unicidade da chave de idempotência dentro do escopo definido;
- worker com claim seguro;
- retry com backoff;
- processamento idempotente no `mz_economy`;
- dead letter;
- reprocessamento administrativo auditado;
- métricas de atraso e falha;
- reconciliação entre outbox e ledger.

## Critérios de aprovação

- [x] `mz_economy` pode ficar offline sem perda de evento.
- [x] Eventos pendentes são processados depois do retorno.
- [x] Retry não duplica saldo.
- [x] Retry não duplica ledger.
- [x] Dois workers não processam o mesmo evento duas vezes.
- [x] Dead letters são visíveis e reprocessáveis.
- [x] Resultado de operação pode ser recuperado pela chave idempotente.

**Revisão de desenho:** `reports/PHASE_3_DESIGN_REVIEW.md` — arquitetura, schema proposto,
contratos privados, claim/lease/retry, dead letter, reconciliação, riscos e lotes P3-A a P3-G.
Nenhum código ou runtime da Fase 3 foi aprovado nesta revisão.

**Lote P3-A:** `[R] Aprovado em runtime` — schemas `mz_financial_outbox` e
`mz_economy_outbox_receipts`, readiness estrutural e flags desligadas implementados conforme
`reports/PHASE_3_P3_A_IMPLEMENTATION.md`. Sete casos foram aprovados manualmente no MySQL/FiveM
staging conforme confirmação do usuário, com zero falhas e zero bloqueados. O fault injection
destrutivo foi não aplicável nesta rodada. Nenhuma escrita financeira, worker ou consumer foi ativado.

**Lote P3-B:** `[R] Aprovado em runtime no escopo funcional` — envelope financeiro v1 e insert atômico de outbox
implementados para `TransferMoneyBetweenAccounts` e `TransferBankBetweenPlayers`, com/sem chave
idempotente. Quatro operações reais geraram quatro eventos `pending`, com saldo correto e zero falha
informada. O retorno às flags desligadas preservou os eventos e restaurou o ledger legado para novas
operações. Concorrência, replay forçado e falha SQL permanecem para o end-to-end. Consumer e worker
continuam pendentes conforme `reports/PHASE_3_P3_B_RUNTIME_APPROVAL.md`.

**Lote P3-C:** `[R] Aprovado em runtime no escopo funcional` — consumer idempotente privado implementado no
`mz_economy`. O contrato aceita somente o invocador server-side `mz_core`, valida integralmente o
envelope v1 e grava recibo mais todas as pernas do ledger em uma única transação SQL. Replay usa o
recibo persistente e IDs `mzoutbox:<outbox_id>:<leg>`. O runner manual de staging fica desativado por
padrão e não altera claim/status da outbox. O usuário confirmou manualmente consumo inicial de
quatro eventos, replay integral, extrato sem duplicidade, saldo preservado e outbox ainda `pending`,
com zero falha informada. Fault injection e gates avançados permanecem para o end-to-end. Dispatcher,
ACK, retry e dead letter ainda não foram implementados.

**Lote P3-D:** `[R] Aprovado em runtime no escopo funcional` — dispatcher server-side implementado no `mz_core`,
desligado por padrão, com preflight privado do consumer, claim atômico por UUID, lease, recuperação
de lease expirado, ACK condicionado ao token, backoff exponencial com jitter e transição técnica para
`dead_letter`. O worker não altera saldo e não oferece endpoint ao client. O usuário confirmou
startup, backlog por replay, operações novas, economy offline, restart, health, smoke físico e
saldo/persistência, com zero falha informada. Concorrência/fault injection avançados permanecem no
end-to-end. Administração/reprocesso de dead letter e reconciliação continuam reservados ao P3-E.

**Lote P3-E:** `[R] Aprovado em runtime no escopo funcional` — administração server-side implementada no `mz_core`,
desligada por padrão, com ACE específica, preview temporário por ID/correlationId, vínculo ao ator,
frase forte, gate separado de aplicação e referência de uso único. O reprocesso valida novamente o
envelope e move somente `dead_letter -> pending`, sem editar payload/saldo/ledger. Reconciliação é
read-only e a retenção de 90 dias é apenas reportada, sem purge. O usuário confirmou 12 de 12 casos
funcionais no MySQL/FiveM staging, com zero falha financeira e zero bloqueados. Administração,
runner e apply foram desligados no teardown. O falso texto `audit_after_failed` foi corrigido e o
delta correspondente foi encerrado pela revisão final P3-G.

**Lote P3-F:** `[R] Aprovado em runtime` — `AddMoney`, `RemoveMoney`, `SetMoney`, ajustes
organizacionais, transferências jogador↔organização e payroll agora persistem as fontes oficiais e a
outbox na mesma transação. O consumer privado aceita os novos envelopes de uma e duas pernas; cache
só muda após commit e o ledger best-effort é apenas fallback com a feature desligada. Payroll ganhou
replay persistente por janela. Lua e buscas estáticas foram aprovados conforme
`reports/PHASE_3_P3_F_IMPLEMENTATION.md`. No runtime, 16 de 16 casos foram aprovados manualmente no
MySQL/FiveM staging conforme resultados fornecidos pelo usuário, incluindo producers pessoais,
economy offline/backlog, restart, ajustes e transferências organizacionais, payroll/replay e smoke
físico, fault SQL organizacional, concorrência real e taxa/refund com falha controlada de entrega. O
P3-F é `[R]` e sua evidência compõe a aprovação final `[R]` da Fase 3.

**Lote P3-G:** `[R] Aprovado em runtime — 6/6 aprovados` — a releitura independente
confirmou ownership, atomicidade, idempotência, consumer privado, claim/lease, retry, dead letter,
administração, reconciliação e produtores atuais. Sintaxe e superfícies client-facing foram
verificadas sem bloqueador estático. Os testes financeiros já aprovados não serão repetidos. Restam
somente seis casos consolidados de resiliência/teardown descritos em
`reports/PHASE_3_P3_G_RUNTIME_CHECKLIST.md`. O runner único, server-side, console-only e sem escrita
de saldo foi validado estaticamente conforme `reports/PHASE_3_P3_G_RUNNER_IMPLEMENTATION.md`; até
sua conclusão. O runner executado no MySQL/FiveM staging passou os cinco deltas técnicos, removeu
todas as fixtures e preservou os saldos. O teardown desligou o runner e confirmou core, dispatcher,
economy, consumer, inventory e banco ready. A decisão final está registrada em
`reports/PHASE_3_FINAL_DECISION.md`; a Fase 3 recebe `[R]`.

---

# Fase 4 — API bancária compartilhada

**Status:** `[R] Aprovada em runtime`

**Aprovação runtime da API v1 (2026-07-19):** smoke físico e runner server-side aprovados pelo
usuário, com `10/10` casos, zero falhas e zero bloqueados. A capability `phone` não foi antecipada.

## Objetivo

Transformar os exports parciais em uma API versionada, autenticada e reutilizável.

## Canais

```text
atm
branch
phone
admin
```

O canal nunca é uma string confiada ao client. Ele é derivado de uma sessão ou capability server-side.

## Capacidades

### ATM

- overview e extrato;
- saque e depósito;
- transferência;
- proximidade obrigatória;
- ATM válido;
- cartão conforme configuração;
- limites físicos.

### Agência

- overview e extrato;
- saque e depósito;
- transferência;
- emissão e substituição de cartão;
- atendimento sem cartão quando configurado;
- proximidade de agência válida.

### Phone

- overview e extrato;
- transferência;
- consulta e bloqueio de cartão;
- nunca saca ou deposita dinheiro físico;
- exige sessão de telefone vinculada ao jogador e aparelho.

### Admin

- ACE/capability específica;
- eventos separados;
- justificativa obrigatória;
- auditoria completa;
- nenhuma alteração silenciosa.

## Contratos mínimos

```lua
GetAccountOverview
GetAccountStatement
GetPublicAccount
ResolveTransferRecipient
Transfer
GetCards
IssueCard
BlockCard
ReplaceCard
GetChannelCapabilities
GetOperationResult
```

## Regras de API

- versão explícita;
- DTOs documentados;
- erros estáveis;
- `correlationId` em toda resposta financeira;
- `idempotencyKey` em todo comando repetível;
- nenhuma interface acessa diretamente `mz_core`;
- nenhum export público devolve segredo de credencial sem necessidade;
- invocador server-to-server é validado conforme política;
- queries e comandos possuem contratos separados;
- logs registram canal efetivo, não canal informado pelo client.

## Critérios de aprovação

- [x] Callback físico não alcança `phone`.
- [x] ATM e agência usam a API oficial.
- [x] Phone pode integrar sem copiar lógica.
- [x] Permissões por canal são testadas.
- [x] DTOs não expõem identificadores internos.
- [x] Erros e versionamento estão documentados.
- [x] Testes de abuso e replay são aprovados.

---

# Fase 5 — Cartão bancário completo

**Status:** `[~] Em implementação`

**Gate do MVP phone (2026-07-19):** `[R]` aprovado em runtime para consulta sanitizada e bloqueio,
com revalidação, invalidação de sessão e ausência de segredo no client. A decisão reutiliza os
testes reais das Fases 0, 3 e 4 e está em `reports/PHASE_5_PHONE_MVP_GATE.md`. Emissão/segunda via
continuam exclusivas da agência; os demais critérios abaixo permanecem pendentes e a Fase 5 não é
declarada completa.

## Objetivo

Completar e tornar confiável o ciclo de vida do cartão físico.

## Estados

```text
issuing
active
blocked
revoked
expired
```

## Campos recomendados

```text
card_uid
citizenid
inventory_instance_uid
last_four
status
card_type
issued_at
expires_at
blocked_at
revoked_at
last_used_at
daily_withdraw_limit
failed_pin_attempts
metadata_json
```

## Regras

- cartão não possui saldo;
- credencial é vinculada ao item físico;
- clone de metadata não cria nova credencial válida;
- cartão bloqueado invalida autenticação e sessões conforme política;
- revogado nunca volta a ativo;
- segunda via usa novo UID;
- a credencial antiga só é revogada depois da entrega confirmada;
- falha parcial fica reconciliável;
- emissão e substituição possuem lock/idempotência;
- máximo de cartões ativos é garantido por transação e constraint adequada;
- inventário e banco possuem rotina de reconciliação.

## PIN

PIN permanece desativado até existir:

- mecanismo criptográfico aprovado;
- hash lento com salt;
- segredo/pepper server-side;
- comparação segura;
- rate limit persistente;
- limite de tentativas;
- bloqueio temporário;
- proteção contra replay;
- reset autenticado em agência;
- proibição de logs;
- revisão de segurança.

## Critérios de aprovação

- [ ] Emissão simultânea não duplica cartão ativo.
- [ ] Segunda via simultânea é idempotente.
- [ ] Falha de inventário mantém o cartão anterior válido.
- [ ] Falha de cobrança ou entrega é reconciliada.
- [ ] Cartão bloqueado perde validade imediatamente conforme contrato.
- [ ] Cartão removido segue a política documentada.
- [ ] Cartão de outro titular é negado.
- [ ] Clone de credencial é detectado.
- [ ] Histórico e auditoria estão disponíveis.

---

# Fase 6 — Aplicativo bancário no `mz_phone`

**Status:** `[R] Aprovada em runtime`

**P6-A — consultas reais (2026-07-19):** `[R]` aprovado em runtime. Foi implementada uma
sessão exclusiva do canal `phone`, vinculada no servidor ao jogador e ao aparelho, com saldo,
conta pública, extrato e cartões em modo somente leitura. Token, `citizenid`, IDs internos e
segredos não chegam à NUI. Transferência, saque, depósito, emissão, bloqueio e substituição
permanecem fail-closed neste lote. O usuário confirmou no FiveM a carga dos dados reais e o estado
indisponível sem encerrar o restante do telefone quando `mz_bank` está parado.

**P6-B — transferência pelo telefone (2026-07-19):** `[R]` aprovado em runtime. O aplicativo
resolve o destinatário exclusivamente por agência, conta pública e dígito, mostra nome parcial e
rota mascarada, exige confirmação e executa a transferência oficial idempotente. O
`resolutionToken`, a chave idempotente e os identificadores internos permanecem somente no
servidor. O comprovante usa o `correlationId` oficial. O usuário confirmou manualmente no FiveM a
transferência com os dois jogadores online e a ausência de duplicidade por duplo clique. A negação
de destinatário offline também foi confirmada. Zero falhas pendentes conhecidas foram informadas;
não foram fornecidos logs ou evidências SQL adicionais.

**P6-C — cartões no telefone (2026-07-19):** `[R]` aprovado em runtime. O aplicativo lista
somente o DTO sanitizado do próprio titular e permite bloquear cartão `active` após confirmação
explícita. A NUI recebe apenas `cardRef` opaco, últimos quatro dígitos, estado e datas públicas; a
credencial persistida, titular interno e metadata permanecem no servidor. O comando é vinculado à
sessão `phone`, revalida o personagem, altera somente a credencial oficial e invalida sessões
físicas que utilizavam o cartão. O usuário confirmou manualmente no FiveM a mudança para
`blocked`, a recusa posterior no ATM e a preservação do saldo. Isolamento e referência falsa foram
consolidados das aprovações das Fases 4 e 5, sem repetição. Emissão, desbloqueio e segunda via
continuam fora do telefone. Zero falhas pendentes conhecidas foram informadas.

**P6-D — favoritos bancários (2026-07-19):** `[R]` aprovado em runtime. Um favorito só pode ser
criado a partir de uma transferência confirmada e persiste no domínio de preferências do
`mz_phone`, sem saldo e sem `citizenid` do destinatário. A NUI recebe apenas referência opaca,
apelido, agência e conta mascarada. Cada uso resolve novamente a rota pública pelo `mz_bank`, exige
destinatário online e passa pela mesma confirmação/idempotência do P6-B. O usuário confirmou no
MySQL/FiveM staging o ciclo de salvar, persistir, usar e remover o favorito. Zero falhas pendentes
conhecidas foram informadas; não foram fornecidos logs ou queries adicionais.

**P6-E — notificações bancárias (2026-07-20):** `[R]` aprovado em runtime.
Transferências confirmadas no canal `phone` geram avisos persistentes de envio e recebimento no
`mz_phone`. Cada ponta é deduplicada no MySQL pelo `correlationId` oficial, portanto replay,
recuperação após timeout e duplo clique não criam avisos repetidos. O contrato é exclusivamente
server-side, aceita somente chamada do `mz_bank` e resolve os dois personagens no servidor. A NUI
recebe apenas título, valor e direção; não recebe `citizenid`, `source`, saldo ou rota. Falha ou
indisponibilidade do telefone é registrada depois do commit e nunca altera o resultado financeiro.
O usuário confirmou manualmente no FiveM staging os dois avisos sem duplicidade e uma única
movimentação. Não foram fornecidos logs, capturas ou resultado da query SQL de conferência.

**Limpeza de produção (2026-07-20):** `[R]` aprovada após smoke final. Os dez
runners de staging foram removidos do `mz_bank` e `mz_core`, junto com comandos, convars e hooks
de fault injection. Relatórios e evidências históricas foram preservados. Backfill com preview e
administração ACE da outbox permanecem por serem ferramentas operacionais fail-closed. A ordem
canônica agora inicia `mz_phone` depois de `mz_bank`. O usuário executou o smoke único e informou
“certinho”; nenhum log, captura ou query adicional foi fornecido.

**Preparação de frontend (2026-07-15):** o shell demonstrativo do `mz_phone` foi removido do
fluxo de produção. Os gates reais foram implementados e aprovados nos lotes P6-A a P6-E; nenhum
dado fictício voltou ao fluxo final.

## Dependências

- Fase 2 aprovada;
- Fase 3 aprovada;
- Fase 4 aprovada;
- ciclo de cartão necessário ao MVP aprovado.

## MVP

- saldo;
- conta pública;
- extrato;
- transferência;
- confirmação;
- comprovante correlacionado;
- favoritos;
- cartões;
- bloqueio de cartão;
- notificações;
- tratamento de indisponibilidade.

## Segurança

- sessão vinculada ao jogador;
- sessão vinculada ao aparelho;
- token curto e revogável;
- rate limit;
- uma operação simultânea por sessão;
- chave idempotente;
- confirmação de operação sensível;
- encerramento no disconnect;
- revogação ao trocar/remover aparelho;
- auditoria do canal.

## Proibições

O telefone não:

- saca;
- deposita dinheiro físico;
- usa server ID como conta;
- recebe `source` ou `citizenid` da NUI;
- chama diretamente o `mz_core`;
- mantém saldo ou ledger paralelo.

## Critérios de aprovação

- [x] App usa somente a API oficial.
- [x] Sessão falsa ou de outro aparelho é negada.
- [x] Canal adulterado é negado.
- [x] Transferência é idempotente.
- [x] Comprovante corresponde ao ledger.
- [x] Bloqueio de cartão afeta o ATM conforme contrato.
- [x] Nenhuma lógica financeira é duplicada.

---

# Fase 7 — Contas empresariais e organizações

**Status:** `[ ] Não iniciada`

## Pré-requisito arquitetural

Publicar um ADR definindo:

- dono do saldo organizacional;
- schema oficial;
- locks;
- operações canônicas;
- integração com cargos e membros;
- política de fechamento e sucessão;
- ledger e outbox.

O `mz_bank` não cria saldo empresarial próprio.

## Recursos

- conta pública da organização;
- membros e papéis autorizados;
- limites por cargo;
- aprovação conjunta opcional;
- cartão empresarial;
- extrato;
- transferência;
- saque e depósito auditados;
- bloqueio administrativo;
- relatórios.

## Critérios de aprovação

- [ ] Funcionário sem permissão não movimenta conta.
- [ ] Remoção da organização revoga acesso.
- [ ] Mudança de cargo altera permissões.
- [ ] Operação registra jogador e organização.
- [ ] Concorrência não gasta saldo duas vezes.
- [ ] Saldo empresarial não usa saldo pessoal.
- [ ] Outbox e ledger são obrigatórios.

---

# Fase 8 — Recursos financeiros avançados

**Status:** `[ ] Não iniciada`

Esta fase é um backlog de produtos, não um único pacote de implementação.

Possibilidades:

- débito automático;
- cobranças;
- boletos;
- agendamentos;
- empréstimos;
- financiamentos;
- juros;
- cartão de crédito e fatura;
- investimentos e poupança;
- contas compartilhadas;
- integrações com imóveis, veículos, multas e governo.

Cada produto deve receber roadmap próprio contendo:

- regra econômica;
- propriedade do saldo;
- persistência;
- ledger e outbox;
- idempotência;
- segurança;
- concorrência;
- rollback/reconciliação;
- UX;
- testes;
- critérios de runtime.

---

## 6. Plano de testes permanente

### Segurança

- callback fora do contexto;
- token falso, expirado, reutilizado ou de outro jogador;
- canal, coordenada, valor e destinatário adulterados;
- NUI modificada;
- client Lua modificado;
- tentativa de usar ATM inexistente;
- `citizenid` livre;
- cartão de outro titular, bloqueado, revogado ou clonado;
- operação depois de disconnect;
- resource injector.

### Concorrência

- saque e transferência simultâneos;
- depósito e transferência simultâneos;
- transferências inversas;
- transferências circulares;
- duas operações com a mesma idempotency key;
- segunda via simultânea;
- bloqueio durante autenticação;
- worker de outbox concorrente;
- restart durante operação.

### Persistência

- reconnect;
- restart isolado de cada resource;
- restart do servidor;
- falha e timeout MySQL;
- rollback;
- cache divergente;
- ledger offline;
- inventário indisponível;
- migration repetida;
- outbox acumulada e reprocessada.

### UX

- duplo clique e Enter;
- timeout;
- operação confirmada com refresh indisponível;
- overlay/focus;
- mensagens por código;
- formatação de valor;
- conta mascarada;
- teclado e ESC;
- resoluções diferentes;
- restart da NUI;
- browser preview isolado.

### Evidência obrigatória

Cada caso registra:

```text
test_id
phase
environment
preconditions
steps
expected_result
actual_result
financial_invariant
database_evidence
console_evidence
status
executed_by
executed_at
```

---

## 7. Contratos que não podem ser quebrados

### Saldo pessoal

```text
player.money.wallet
player.money.bank
```

### Persistência pessoal

```text
mz_player_accounts
```

### Operações canônicas

```lua
GetMoney
SetMoney
AddMoney
RemoveMoney
TransferMoneyBetweenAccounts
TransferBankBetweenPlayers
```

### Extrato

```lua
GetAccountStatement
```

### Regras

- `mz_bank`, `mz_economy` e `mz_phone` não criam saldo pessoal paralelo;
- `bank_card` não armazena saldo;
- license não é número de conta;
- server ID não é identidade bancária persistente;
- `citizenid` não é identificador público;
- operação financeira confirmada possui referência e resultado recuperável;
- ledger é derivado de evento financeiro persistente.

---

## 8. Legado

Tabelas:

```text
bank_accounts
bank_transactions
```

Elas não participam do fluxo normal.

Ferramentas:

```text
mz_bank_legacy_preview
mz_bank_legacy_apply CONFIRM
```

Regras:

- aplicação desativada por padrão;
- ACE obrigatória;
- servidor vazio;
- backup comprovado;
- preview e relatório persistentes;
- nenhuma soma de saldos;
- somente substituição explicitamente autorizada;
- conflitos e duplicidades bloqueiam aplicação;
- histórico não é importado sem ferramenta offline idempotente;
- tabelas nunca são apagadas automaticamente.

---

## 9. Documentação e entregáveis

Documentos atuais:

- `README.md`;
- `INTEGRATION.md`;
- `TEST_PLAN.md`;
- `LEGACY_BANK_TABLES.md`;
- `BANK_ROADMAP.md`.

O `TEST_PLAN.md` atual é um roteiro preliminar. Antes da Fase 1, ele deve ser reconciliado com os IDs, pré-condições, fault injection, resultados esperados e evidências definidos neste roadmap.

Documentos a criar nas fases correspondentes:

- `ARCHITECTURE.md`;
- `SECURITY_MODEL.md`;
- `ACCOUNT_IDENTITY.md`;
- `PHONE_API.md`;
- ADR de contas organizacionais;
- `RUNTIME_REPORT_PHASE_N.md`.

Cada relatório de fase contém:

- versão dos arquivos;
- migrations;
- decisões;
- riscos;
- testes executados;
- evidências;
- bugs e correções;
- limitações;
- status final;
- checklist pendente.

---

## 10. Ordem oficial

1. Fase 0 — estabilizar a base atual.
2. Fase 1 — aprovar a base em runtime.
3. Fase 2 — criar identidade bancária pública.
4. Fase 3 — implementar idempotência, outbox e auditoria.
5. Fase 4 — concluir a API compartilhada.
6. Fase 5 — completar cartões.
7. Fase 6 — integrar o aplicativo.
8. Fase 7 — criar contas empresariais após ADR.
9. Fase 8 — abrir roadmaps independentes para produtos avançados.

Antes da aprovação da Fase 1, não implementar:

- PIX;
- QR Code;
- aplicativo bancário;
- conta empresarial;
- crédito;
- empréstimo;
- investimento;
- boletos;
- transferência offline.

Antes da aprovação da Fase 3, nenhum novo canal financeiro deve ser liberado em produção.

---

## 11. Próxima tarefa oficial

Próxima tarefa oficial: revisar o estado real da Fase 4 — API bancária compartilhada — e concluir
somente os contratos mínimos necessários para ATM, agência e futura integração do `mz_phone`. Não
iniciar a integração financeira do phone antes da aprovação da Fase 4.

Resultado atual:

```text
Fase 0: [S] Validada estaticamente
Fase 1: [R] Aprovada em runtime
Fase 2: [R] Aprovada em runtime
Fase 3: [R] Aprovada em runtime
P3-A: [R] Aprovado em runtime
P3-B: [R] Aprovado em runtime no escopo funcional
P3-C: [R] Aprovado em runtime no escopo funcional
P3-D: [R] Aprovado em runtime no escopo funcional
P3-E: [R] Aprovado em runtime no escopo funcional
P3-F: [R] Aprovado em runtime — 16/16 aprovados
P3-G: [R] Aprovado em runtime — 6/6 aprovados
P2-A: [R]
P2-B: [R]
P2-C: [R]
P2-D: [R]
P2-E: [R]
P2-F: [R]
P2-G: [R] Aprovado em runtime
P2-H: [R] Aprovado em runtime
```

A aprovação runtime foi registrada a partir dos resultados fornecidos pelo usuário após execução manual no FiveM, sem anexos adicionais e sem falhas pendentes conhecidas.
