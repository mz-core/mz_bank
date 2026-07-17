# Fase 2 — Implementação do Lote P2-F

Data: 2026-07-17  
Estado atual: **P2-F `[R]` — APROVADO EM RUNTIME**  
Validação estática deste relatório: **APROVADA**  
Runtime posterior: **16/16 APROVADOS**, conforme `PHASE_2_P2_F_RUNTIME_APPROVAL.md`

## 1. Escopo formal implementado

O P2-F implementa somente a transferência interna por conta pública definida em
`PHASE_2_DESIGN_REVIEW.md`:

- revalidação da sessão física, origem, alvo e `resolutionToken`;
- uso do `citizenid` estável resolvido exclusivamente no servidor;
- chamada ao contrato real `mz_core:TransferBankBetweenPlayers`;
- preservação dos limites inteiros, taxa, idempotência e resposta financeira confirmada;
- destinatário obrigatoriamente online;
- invalidação do token após sucesso ou erro terminal;
- manutenção temporária do token em erro ambíguo para permitir recuperação segura;
- nenhum callback, evento de rede, export, NUI ou consumidor phone novo.

O P2-G não foi antecipado. O formulário atual continua enviando server ID e chama o método legado
`MZBankService.Transfer`.

## 2. Contrato interno

```lua
MZBankService.TransferByPublicAccount(
  source,
  resolutionToken,
  amount,
  {
    token = physicalSessionToken,
    idempotencyKey = idempotencyKey
  }
)
```

O chamador não fornece `citizenid`, source do alvo, ID SQL, estado, tipo de conta ou rota completa.
O `source` é fornecido pelo runtime server-side e a identidade do remetente é derivada da sessão.

## 3. Fluxo implementado

1. valida chave de idempotência;
2. revalida sessão, canal, estado físico, personagem e cartão pelo `runOperation` existente;
3. valida valor inteiro e limite do canal;
4. resolve a identidade do remetente a partir do source;
5. relê a conta pública pessoal da origem;
6. permite saída somente quando a origem está `active`;
7. revalida o token P2-E, a rota, o estado recebível e a presença online do alvo;
8. impede autotransferência;
9. calcula a mesma taxa inteira do fluxo atual;
10. chama `TransferBankBetweenPlayers(source, targetCitizenId, amount, metadata)`;
11. deixa locks, transação, cache, ledger, correlationId e idempotência no `mz_core`;
12. invalida o token após resultado confirmado ou erro terminal;
13. separa o sucesso financeiro do refresh visual pelo contrato já aprovado na Fase 1.

## 4. Estados

| Estado | Origem/saída | Alvo/entrada |
|---|---:|---:|
| `active` | permitido | permitido |
| `blocked` | negado | permitido |
| `frozen` | negado | negado |
| `closed` | negado | negado |

O estado da origem é relido imediatamente antes da validação financeira. O alvo é relido pelo
`ValidateResolutionToken`. Alterações posteriores ao preview invalidam a operação.

## 5. Idempotência e replay

A chave continua sendo validada pelo `mz_bank` e persistida pelo mecanismo oficial
`mz_account_idempotency` do `mz_core`. O fingerprint real usa o `citizenid` estável do alvo, valor e
taxa. O token não participa do fingerprint financeiro.

Após sucesso o token é invalidado. Em resposta perdida, o consumidor futuro deverá resolver o alvo
novamente e repetir a **mesma** chave de idempotência. O core recupera o resultado anterior sem mover
saldo novamente. Em erro ambíguo (`bank_unavailable`, `database_error` ou busy), o token também não é
consumido preventivamente.

## 6. Arquivos alterados

| Arquivo | Alteração |
|---|---|
| `config.lua` | mensagens de estado/indisponibilidade e comentário de fase |
| `server/service.lua` | ator comum P2-E/P2-F e transferência interna por conta pública |
| `server/p2f_runtime_runner.lua` | runner staging-only interno e financeiro, inerte por padrão |
| `fxmanifest.lua` | carregamento server-side do runner inerte |
| `BANK_ROADMAP.md` | estado do P2-F |
| `reports/PHASE_2_P2_F_IMPLEMENTATION.md` | este relatório |
| `reports/PHASE_2_P2_F_RUNTIME_CHECKLIST.md` | preparação da validação runtime |
| documentação do `mz_phone` | dependência P2-F registrada sem publicar consumidor |

Nenhuma migration, tabela ou serviço do `mz_core`, `mz_economy`, `mz_inventory` ou `mz_phone` foi
alterado.

## 7. Contratos reais confirmados

- `MZBankRepository.getPublicAccountByOwner(citizenid)`;
- `MZBankAccountService.CanAccountPerform(status, capability)`;
- `MZBankAccountResolution.ValidateResolutionToken(actor, token)`;
- `MZBankAccountResolution.InvalidateResolutionToken(actor, token)`;
- `MZBankBridge.TransferBankBetweenPlayers(source, targetCitizenId, amount, metadata)`;
- `exports['mz_core']:TransferBankBetweenPlayers(...)`;
- idempotência persistente em `mz_account_idempotency`;
- locks ordenados, transação de duas pontas e atualização de cache no serviço real do `mz_core`.

## 8. Validações estáticas

- sintaxe Lua dos arquivos server-side: aprovada;
- nenhum callback, evento de rede ou export P2-F: aprovado;
- nenhum campo de saldo ou persistência financeira no `mz_bank_accounts`: preservado;
- nenhuma escrita direta em `mz_player_accounts`: preservada;
- chamada financeira única através do bridge/core oficial: confirmada;
- `targetCitizenId` vem somente de `ValidateResolutionToken`: confirmado;
- fluxo atual por server ID não foi substituído: confirmado;
- NUI, animação, alinhamento e slot não foram alterados: confirmado por ausência de mudanças client/UI;
- transferência offline não foi criada: confirmado.

Harness isolado executado sobre os contratos reais do serviço:

```text
PASS P2-F harness confirmed=true stable_target=true token_consumed=true blocked_origin=true
```

## 9. Riscos e runtime pendente

- concorrência e timeout após commit exigem fault injection em staging;
- replay deve ser conferido no ledger, saldos, cache e `mz_account_idempotency`;
- mudança de estado entre preview e confirmação deve ser testada;
- o P2-F ainda não é alcançável pela NUI normal, por decisão de escopo;
- o runner server-side foi criado, mas permanece inerte por padrão e exige convars explícitas;
- o modo financeiro real movimenta somente o valor configurado (máximo 1.000) e exige dois jogadores online.

## 10. Estado final

```text
Fase 2: [~] Em implementação
P2-A: [R]
P2-B: [R]
P2-C: [R]
P2-D: [R]
P2-E: [R]
P2-F: [R] Aprovado em runtime
P2-G e seguintes: NÃO IMPLEMENTADOS
```

O checklist foi executado e aprovado posteriormente. O próximo passo permitido é implementar somente
o P2-G, sem antecipar o P2-H.
