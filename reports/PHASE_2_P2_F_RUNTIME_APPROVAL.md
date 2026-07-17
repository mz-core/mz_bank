# Fase 2 — Aprovação runtime do Lote P2-F

Data: 2026-07-17  
Ambiente: MySQL/FiveM staging  
Origem: resultados fornecidos pelo usuário após execução real

## Decisão

```text
P2-F: [R] Aprovado em runtime
Casos: 16
Aprovados: 16
Falhas: 0
Bloqueados: 0
```

## Evidências

- runner interno: `executed=14 passed=14 failed=0`;
- transferência real de `R$1`: remetente `-1`, destinatário `+1`, taxa `0`;
- replay recuperado sem segunda movimentação;
- conflito de idempotência negado sem alteração de saldo;
- cache, persistência e linha de idempotência coerentes;
- correlationId oficial presente;
- origem não ativa, alvo indisponível, autotransferência e valores inválidos negados;
- concorrência injetada com oito chamadas e um único commit lógico;
- erro ambíguo injetado preservou capacidade de recuperação;
- auditoria sem token ou PII;
- smoke test físico/financeiro confirmado pelo usuário;
- restart confirmado e runner desativado.

## Limitação registrada

Não foi provocado um timeout destrutivo real na infraestrutura SQL. A recuperação após commit foi
validada pela transferência real seguida de replay persistente, e o ramo de erro ambíguo foi
validado por fault injection server-side. Nenhuma evidência adicional é inferida.

## Invariantes

- saldo permanece exclusivamente no `mz_core`/`mz_player_accounts`;
- `mz_bank_accounts` continua sem saldo;
- locks, transação, cache, ledger e idempotência permanecem no core;
- destinatário veio do token revalidado e foi passado ao core como citizenid interno;
- nenhum citizenid, ID SQL ou source alvo foi publicado ao client;
- não existe transferência offline, outbox ou ledger paralelo;
- P2-G, cutover da NUI e integração phone não foram implementados nesta aprovação.

```text
Fase 2: [~] Em implementação
P2-F: [R] APROVADO EM RUNTIME
```

O próximo lote permitido é somente o P2-G, conforme `PHASE_2_DESIGN_REVIEW.md`.
