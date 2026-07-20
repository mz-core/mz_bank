# Fase 4 — Aprovação runtime da API bancária compartilhada

Data: 2026-07-19  
Ambiente: FiveM staging  
Origem da evidência: resultados fornecidos pelo usuário após execução manual e runner server-side

```text
Fase 4: [R] Aprovada em runtime
10 aprovados
0 falhas
0 bloqueados
```

## Evidência registrada

O usuário confirmou que o smoke manual solicitado passou: inicialização, ATM, agência, overview,
extrato, depósito, saque, transferência por conta pública, NUI, animação e slot do cartão.

Em seguida, executou o runner temporário da Fase 4 e confirmou o resultado esperado:

```text
executed=6
passed=6
failed=0
sql_writes=0
balance_writes=0
```

Também foi confirmada a desativação do runner após o teste. Não foram adicionadas evidências além
das informações fornecidas pelo usuário e das aprovações runtime anteriores referenciadas pelo
checklist.

## Invariantes aprovadas

- versão explícita e erros estáveis;
- resource chamador sujeito à allowlist;
- `mz_phone` não reutiliza token de ATM/agência;
- canal efetivo continua vindo da sessão server-side;
- DTOs não expõem `citizenid`, license, ID SQL, `card_uid`, PIN ou metadata interna;
- cartões usam `cardRef` opaco vinculado ao source/token;
- idempotency key e correlationId são preservados pelo adapter;
- recuperação de resultado é read-only;
- nenhum saldo, ledger ou escrita SQL foi criado pelo runner;
- saldo oficial, persistência, NUI, animação e fluxos físicos permaneceram funcionais.

## Decisão

Todos os dez casos do checklist estão aprovados, sem falha ou bloqueio conhecido.

**Fase 4: [R] APROVADA EM RUNTIME.**

Próximo passo: concluir somente o gate mínimo da Fase 5 necessário ao MVP do telefone; depois
iniciar a capability `phone` e a integração real da Fase 6.
