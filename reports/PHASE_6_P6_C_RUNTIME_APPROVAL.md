# Fase 6 — Aprovação runtime do P6-C

Data: 2026-07-19  
Ambiente: FiveM staging  
Origem da evidência: resultado manual fornecido pelo usuário e evidências runtime anteriores

## Resultado consolidado

| Métrica | Resultado |
|---|---:|
| Casos definidos | 2 |
| Aprovados | 2 |
| Falhas | 0 |
| Bloqueados | 0 |

## Evidência manual do P6-C

O usuário confirmou no FiveM:

- o aplicativo apresentou o cartão como `Bloqueado` após a confirmação;
- o ATM recusou a mesma credencial depois do bloqueio;
- o saldo permaneceu inalterado.

As evidências textuais preservadas são “apareceu cartão bloqueado” e “ATM recusou e o saldo não
mudou”. Não foram inventados logs, capturas ou resultados SQL adicionais.

## Evidências reutilizadas sem repetição

- `PHASE_4_RUNTIME_APPROVAL.md`: `cardRef` opaco vinculado a source/token, referência falsa negada,
  DTO sem `card_uid`, PIN, metadata ou identificador interno e zero escrita financeira;
- `PHASE_5_PHONE_MVP_GATE.md`: consulta sanitizada, bloqueio, revalidação e invalidação de sessão
  aprovados para o escopo do telefone;
- P6-A/P6-B: overview, extrato, indisponibilidade e transferência idempotente já aprovados em
  runtime no aplicativo real.

Esses vetores não foram executados novamente no P6-C.

## Invariantes confirmadas

- o bloqueio altera somente a credencial oficial do cartão;
- a sessão/uso ATM deixa de ser válido após o bloqueio;
- nenhum saldo é debitado ou creditado;
- o telefone continua sem saldo ou ledger paralelo;
- emissão, desbloqueio e segunda via continuam indisponíveis no aplicativo;
- a Fase 5 completa e a Fase 6 completa não são aprovadas por este relatório.

## Limitações

- não foram anexados logs, screenshots ou queries SQL;
- favoritos e notificações ainda não pertencem ao escopo concluído;
- desbloqueio não existe no aplicativo; segunda via permanece na agência.

## Decisão final

```text
P6-C: [R] Aprovado em runtime
Fase 6: [~] Em implementação
Falhas pendentes conhecidas do P6-C: 0
```
