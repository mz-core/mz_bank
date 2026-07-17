# MZ Bank — Decisão final da Fase 2

Data: 2026-07-17  
Ambiente informado: MySQL/FiveM staging  
Origem dos resultados: execuções manuais confirmadas pelo usuário

## 1. Decisão

```text
Fase 2: [R] Aprovada em runtime
P2-A: [R]
P2-B: [R]
P2-C: [R]
P2-D: [R]
P2-E: [R]
P2-F: [R]
P2-G: [R]
P2-H: [R]
```

## 2. Resultado consolidado

| Escopo | Aprovados | Falhas | Bloqueados |
|---|---:|---:|---:|
| P2-A a P2-G | 106 | 0 | 0 |
| P2-H delta final | 3 | 0 | 0 |
| **Fase 2** | **109** | **0** | **0** |
| Regressão Fase 1 já registrada | 43 | 0 | 0 |

O P2-A possui adicionalmente um caso registrado como não aplicável. Não há teste não executado ou
bloqueado conhecido nos gates críticos usados para esta decisão.

## 3. Gates aprovados

- migration v3 aditiva, idempotente e fail-closed;
- tabela pública sem saldo e sem alteração de `mz_player_accounts`;
- uma conta pessoal vitalícia por `citizenid`, rota única e não reutilizável;
- criação CSPRNG idempotente com proteção de concorrência e retry de colisão;
- readiness, restart e rollback funcional compatível com v3;
- backfill em staging com ACE, preview, confirmação forte, lotes, retry e auditoria;
- resolução exata server-side com DTO mínimo, rate limit, cooldown e token curto;
- estados `active`, `blocked`, `frozen` e `closed` aplicados pelo servidor;
- transferência online por conta pública usando somente o serviço financeiro oficial do `mz_core`;
- idempotência, replay, concorrência, persistência, cache, ledger e `correlationId` preservados;
- server ID removido do contrato final da NUI;
- nenhum `citizenid`, source, license ou ID SQL exposto ao client;
- ATM, agência, cartão, sessões, animação, alinhamento, slot, NUI, saque, depósito e extrato preservados;
- zero saldo paralelo, ledger paralelo ou transferência offline.

## 4. Limitações preservadas

- evidências detalhadas não foram anexadas; os relatórios registram a declaração do usuário;
- timeout SQL destrutivo real não foi provocado no P2-F; replay persistente e fault injection cobriram
  o ramo relacionado;
- destino de transferência continua precisando estar online;
- estados da conta restringem o canal `mz_bank`, não representam hold financeiro global no core;
- backfill apply e runners continuam desligados por padrão;
- phone, PIX, QR Code, contas empresariais e produtos financeiros não pertencem à Fase 2.

## 5. Estado final

Não há falha, bloqueio, divergência de saldo ou regressão conhecida informada no escopo da Fase 2.

```text
Fase 0: [S] Validada estaticamente
Fase 1: [R] Aprovada em runtime
Fase 2: [R] Aprovada em runtime
```

O próximo passo do roadmap é a Fase 3. Esta decisão não autoriza pular diretamente para o aplicativo
do telefone.

