# MZ Bank — Aprovação runtime do P3-A

Data: 2026-07-17  
Ambiente informado: MySQL/FiveM staging  
Origem: confirmação do usuário após execução manual

## Decisão

```text
P3-A: [R] Aprovado em runtime
7 aprovados
0 falhas
0 bloqueados
1 não aplicável
```

## Confirmações registradas

- `mz_core` iniciou com schema v1, feature e writes desligados;
- `mz_economy` iniciou com schema v1 e consumer desligado;
- as tabelas e índices foram criados corretamente;
- a segunda inicialização ocorreu sem duplicação ou erro;
- `mz_financial_outbox` permaneceu com zero linhas;
- `mz_economy_outbox_receipts` permaneceu com zero linhas;
- ATM e agência abriram normalmente;
- depósito, saque e transferência atuais passaram;
- saldo, persistência e extrato permaneceram corretos;
- nenhum saldo paralelo ou consumer foi ativado.

## Evidência e limitação

Os resultados foram fornecidos pelo usuário como “certinho” após a sequência de testes indicada.
Logs completos, versões do ambiente e saídas SQL integrais não foram anexados e não são inventados
neste relatório.

O fault injection destrutivo por remoção temporária de índice não foi informado. Ele foi registrado
como `NÃO APLICÁVEL` nesta rodada e permanece como limitação para uma campanha futura de resiliência;
o comportamento fail-closed recebeu validação estática no P3-A.

Esta decisão aprova somente a fundação de schema/readiness. Não aprova escrita atômica, worker,
consumer, retry, dead letter, reconciliação ou a Fase 3 completa.

## Próximo lote

O próximo passo permitido é implementar somente o P3-B: envelope v1 e escrita da outbox na mesma
transação das operações financeiras bancárias atuais. P3-B não deve antecipar o consumer ou worker.
