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
| 0 — Estabilização da base atual | `[~]` | Base funcional, com bloqueadores estáticos conhecidos |
| 1 — Validação runtime crítica | `[!]` | Bloqueada até a conclusão da Fase 0 |
| 2 — Identidade bancária pública | `[ ]` | Ainda usa server ID no fluxo atual |
| 3 — Idempotência, outbox e auditoria | `[ ]` | Ledger atual é best effort |
| 4 — API bancária compartilhada | `[~]` | Existem exports parciais, ainda sem autenticação completa de canal |
| 5 — Cartão bancário completo | `[~]` | Emissão, bloqueio e substituição existem parcialmente |
| 6 — Aplicativo no `mz_phone` | `[ ]` | Não existe sessão bancária de telefone aprovada |
| 7 — Contas empresariais | `[ ]` | Domínio do saldo ainda precisa ser decidido |
| 8 — Recursos avançados | `[ ]` | Backlog futuro |

---

# Fase 0 — Estabilização da base atual

**Status:** `[~] Em implementação`

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

- [ ] Client não seleciona o caminho `phone`.
- [ ] Canal físico é obtido da sessão.
- [ ] ATM arbitrário é negado.
- [ ] Morte e veículo são validados no servidor.
- [ ] Cartão bloqueado/revogado perde validade na sessão.
- [ ] Remoção do item segue política documentada.
- [ ] Valores decimais são tratados conforme contrato.
- [ ] Resultado financeiro não depende do refresh posterior.
- [ ] Retry da mesma operação não movimenta saldo novamente.
- [ ] Nenhum `citizenid` livre é aceito no callback público.
- [ ] Inicialização real inclui as dependências.
- [ ] Migration possui uma única fonte de verdade.
- [ ] Sintaxe Lua e JavaScript aprovada.
- [ ] Revisão de abuso client-side aprovada.

## Gate da fase

```text
Fase 0: [S] Validada estaticamente
```

Somente depois desse gate a Fase 1 pode ser executada formalmente.

---

# Fase 1 — Validação runtime crítica

**Status:** `[!] Bloqueada`

**Dependência:** conclusão estática da Fase 0.

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

- [ ] Todos os recursos iniciam na ordem oficial.
- [ ] `mz_bank` só fica ready depois do schema.
- [ ] Item `bank_card` está disponível.
- [ ] Restart do banco não altera saldos.
- [ ] Restart da economia não altera saldos.
- [ ] Restart do core reconstrói o cache.
- [ ] Nenhuma tabela de saldo paralela é criada.
- [ ] Nenhum export ou callback fica ausente.

### Sessão e canal — RT-SESSION

- [ ] Abrir agência válida.
- [ ] Negar agência falsa.
- [ ] Abrir ATM válido.
- [ ] Negar ATM inexistente.
- [ ] Negar abertura distante.
- [ ] Negar canal adulterado.
- [ ] Negar callback sem sessão.
- [ ] Negar token falso, expirado ou de outro jogador.
- [ ] Negar token de outro canal.
- [ ] Invalidar sessão ao afastar.
- [ ] Invalidar ou negar operação ao morrer.
- [ ] Invalidar ou negar operação em veículo.
- [ ] Limpar sessão no disconnect e restart.

### Cartão — RT-CARD

- [ ] ATM sem cartão é negado.
- [ ] Cartão válido autentica.
- [ ] Cartão de outro titular é negado.
- [ ] Cartão bloqueado é negado.
- [ ] Cartão revogado é negado.
- [ ] Bloqueio durante a sessão impede nova operação.
- [ ] Remoção do item durante a sessão segue a política aprovada.

### Depósito e saque — RT-CASH

- [ ] Valores válidos preservam `wallet + bank`.
- [ ] Todo o saldo permitido pode ser movimentado.
- [ ] Saldo insuficiente não altera nenhuma conta.
- [ ] Zero, negativo, texto e decimal inválido são negados.
- [ ] Limite por operação é respeitado.
- [ ] Limite diário é testado somente se implementado.
- [ ] Duplo clique não duplica operação.
- [ ] Cache e banco permanecem iguais após reconnect.
- [ ] Ledger usa a mesma referência da operação.

### Transferência — RT-TRANSFER

- [ ] Transferência válida debita e credita uma única vez.
- [ ] Destinatário inexistente ou offline é negado corretamente.
- [ ] Autotransferência é negada.
- [ ] Taxa segue o contrato.
- [ ] Transferências cruzadas não causam deadlock.
- [ ] Múltiplas transferências não gastam o mesmo saldo.
- [ ] Disconnect de uma das pontas não produz estado parcial.
- [ ] Falha SQL reverte as duas pontas.
- [ ] Cache só muda depois do commit.
- [ ] As duas pontas compartilham `correlationId`.

### Resposta ambígua — RT-RETRY

- [ ] Timeout do client após commit não duplica retry.
- [ ] Reenvio da mesma chave retorna o mesmo resultado.
- [ ] Falha de overview não oculta uma transferência confirmada.
- [ ] Restart durante operação termina em estado reconciliável.

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

**Status:** `[ ] Não iniciada`

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

- [ ] Conta duplicada é impossível.
- [ ] Repetir criação devolve a mesma conta.
- [ ] `citizenid` não aparece na interface pública.
- [ ] Server ID não é usado como conta.
- [ ] Conta persiste após reconnect e restart.
- [ ] Estados da conta são aplicados no servidor.
- [ ] Enumeração não expõe dados pessoais.
- [ ] Transferência por conta é aprovada em runtime.

---

# Fase 3 — Idempotência, outbox e auditoria

**Status:** `[ ] Não iniciada`

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

- [ ] `mz_economy` pode ficar offline sem perda de evento.
- [ ] Eventos pendentes são processados depois do retorno.
- [ ] Retry não duplica saldo.
- [ ] Retry não duplica ledger.
- [ ] Dois workers não processam o mesmo evento duas vezes.
- [ ] Dead letters são visíveis e reprocessáveis.
- [ ] Resultado de operação pode ser recuperado pela chave idempotente.

---

# Fase 4 — API bancária compartilhada

**Status:** `[~] Em implementação`

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

- [ ] Callback físico não alcança `phone`.
- [ ] ATM e agência usam a API oficial.
- [ ] Phone pode integrar sem copiar lógica.
- [ ] Permissões por canal são testadas.
- [ ] DTOs não expõem identificadores internos.
- [ ] Erros e versionamento estão documentados.
- [ ] Testes de abuso e replay são aprovados.

---

# Fase 5 — Cartão bancário completo

**Status:** `[~] Em implementação`

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

**Status:** `[ ] Não iniciada`

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

- [ ] App usa somente a API oficial.
- [ ] Sessão falsa ou de outro aparelho é negada.
- [ ] Canal adulterado é negado.
- [ ] Transferência é idempotente.
- [ ] Comprovante corresponde ao ledger.
- [ ] Bloqueio de cartão afeta o ATM conforme contrato.
- [ ] Nenhuma lógica financeira é duplicada.

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

```text
Concluir os bloqueadores B0-01 a B0-10 e submeter a Fase 0 a nova revisão estática.
```

Resultado esperado:

```text
Fase 0: [S] Validada estaticamente
Fase 1: [ ] Liberada para execução em staging
```

Se algum bloqueador permanecer:

```text
Fase 0: [!] Bloqueada
Bloqueador:
Impacto:
Correção necessária:
Testes afetados:
```

O projeto não deve iniciar a identidade pública ou expandir a API enquanto a base aceitar adulteração de canal, ATM arbitrário ou operação sem revalidação adequada.
