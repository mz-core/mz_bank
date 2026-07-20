# Fase 3 — Aprovação runtime do P3-E

Data: 2026-07-17  
Ambiente informado: MySQL/FiveM staging  
Origem: resultados fornecidos pelo usuário após execução manual

## Resultado

```text
P3-E: [R] Aprovado em runtime no escopo funcional
Casos: 12
Aprovados: 12
Falhas financeiras: 0
Bloqueados: 0
Não executados: 0
```

Foram confirmados:

- administração desligada sem comando registrado e ACE ausente negada;
- reconciliação read-only com divergências e backlog em zero;
- seletor inexistente com resposta mínima e zero escrita;
- preview válido com referência opaca e TTL de 120 segundos;
- apply desligado e confirmação incorreta negados;
- ator divergente e preview expirado negados;
- transição controlada `dead_letter -> pending -> processed`;
- replay pelo consumer sem duplicar recibo ou ledger;
- referência de preview de uso único;
- exatamente um recibo e duas pernas para a outbox testada;
- auditorias de preview, solicitação e conclusão persistidas;
- retenção apenas reportada, sem purge;
- runner, administração e gate de apply desligados ao final.

## Evidências registradas

O usuário forneceu linhas integrais de readiness, health, reconcile, preview, bloqueio por apply,
reprocesso e ACK por replay. As consultas SQL confirmaram a outbox novamente `processed`, um recibo,
duas pernas e uma auditoria para cada ação administrativa esperada. Para o runner negativo e o
teardown, o usuário declarou que os resultados esperados foram obtidos; os logs integrais desses dois
passos não foram anexados e nenhum detalhe adicional foi inferido.

## Correção durante o runtime

O primeiro retorno positivo exibiu simultaneamente `ok=true` e `error=audit_after_failed`, embora a
auditoria `dead_letter_reprocess_completed` estivesse persistida. A causa era a expressão Lua
`afterAudit and nil or ...`, que não pode produzir `nil` pelo idioma `and/or`. O retorno foi alterado
para uma atribuição condicional explícita e validado com `luac`. O caminho financeiro não falhou e
não foi repetido somente para reproduzir o texto; esse delta será observado no end-to-end P3-G.

## Limites

Esta aprovação encerra o escopo funcional do P3-E. Ela não aprova os produtores financeiros ainda
fora da outbox, concorrência/fault injection final, P3-F, P3-G, Fase 3 completa ou canal `phone`.

## Decisão

O P3-E está aprovado em runtime no escopo funcional. A Fase 3 permanece `[~] Em implementação` e
o próximo lote oficial é o P3-F — cobertura dos produtores financeiros restantes.
