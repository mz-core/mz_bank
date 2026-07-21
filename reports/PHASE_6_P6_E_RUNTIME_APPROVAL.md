# Fase 6 — Aprovação runtime do P6-E

Data: 2026-07-20  
Ambiente: MySQL/FiveM staging  
Origem da evidência: resultado fornecido pelo usuário após execução manual

## Resultado consolidado

| Métrica | Resultado |
|---|---:|
| Casos definidos | 1 |
| Executados | 1 |
| Aprovados | 1 |
| Falhas | 0 |
| Bloqueados | 0 |

## Evidência registrada

Após receber o caso consolidado do P6-E, o usuário informou “confirmado”. A confirmação registra:

- um único aviso negativo para o remetente;
- um único aviso positivo para o destinatário;
- uma única movimentação financeira mesmo com confirmação rápida/repetida;
- ausência de erro de console informado.

Não foram anexados logs, capturas ou resultado da query SQL. Esses artefatos não foram inventados.
A persistência é parte do caminho real que antecede o preview: o client só é notificado depois de
o repository retornar a linha protegida pela constraint de deduplicação.

## Invariantes preservadas

- saldo, locks, idempotência, ledger e outbox permanecem no `mz_core`;
- a notificação usa o `correlationId` oficial e não cria saldo ou ledger paralelo;
- o frontend não recebe `citizenid`, source, rota, cartão ou saldo;
- replay não cria nova linha nem novo preview para a mesma ponta;
- falha posterior no `mz_phone` não transforma commit financeiro em falha;
- ATM, agência, cartões e favoritos permanecem preservados.

## Decisão final

```text
P6-E: [R] Aprovado em runtime
Casos aprovados: 1/1
Falhas: 0
Bloqueados: 0
Falhas pendentes conhecidas do P6-E: 0
```
