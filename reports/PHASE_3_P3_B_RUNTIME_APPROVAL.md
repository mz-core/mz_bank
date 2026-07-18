# MZ Bank — Aprovação runtime funcional do P3-B

Data: 2026-07-17  
Ambiente informado: MySQL/FiveM staging  
Origem: execução manual confirmada pelo usuário

## Decisão

```text
P3-B: [R] Aprovado em runtime no escopo funcional
8 casos/gates aprovados
0 falhas
0 bloqueados
1 não aplicável
4 gates avançados ou partes pendentes
```

## Evidência registrada

Com escrita da outbox habilitada temporariamente:

```text
id=1 transfer_between_accounts amount=100 pending
id=2 transfer_between_accounts amount=100 pending
id=3 bank_transfer amount=10 pending
id=4 bank_transfer amount=10 pending
```

O usuário confirmou:

- depósito e saque alteraram os saldos corretamente;
- duas transferências de 10 foram recebidas;
- existe exatamente uma outbox por operação executada;
- os eventos persistiram como `pending`;
- o extrato legado não recebeu esses lançamentos enquanto a outbox estava ativa;
- após restaurar as flags para `false`, uma nova operação voltou ao extrato legado;
- desligar a feature não apagou ou processou indevidamente as quatro linhas.

## Limitações preservadas

- nenhum consumer existe ainda; as quatro linhas devem permanecer intactas para o P3-C;
- taxa diferente de zero não foi informada;
- replay forçado/duplo clique não foi evidenciado separadamente;
- concorrência real e falha SQL controlada não foram executadas;
- o JSON integral não foi anexado para inspeção runtime;
- logs e versões do ambiente não foram fornecidos.

Esses itens não são tratados como aprovados. Eles permanecem nos gates end-to-end da Fase 3.

## Estado

O P3-B comprova o cutover funcional `saldo + outbox` e fornece eventos reais para o próximo lote.
Não aprova consumer, worker, retry, dead letter ou a Fase 3 completa.

O próximo lote permitido é somente P3-C: consumer idempotente no `mz_economy`, inicialmente sem
worker automático, usando os eventos `pending` como evidência de consumo posterior.
