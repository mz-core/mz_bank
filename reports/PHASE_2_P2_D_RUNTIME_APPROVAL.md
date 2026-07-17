# Fase 2 — Aprovação runtime do Lote P2-D

Data: 2026-07-17  
Ambiente: MySQL/FiveM staging  
Fonte da evidência: resultados fornecidos pelo usuário após execução manual

```text
Fase 2: [~] Em implementação
P2-A: [R]
P2-B: [R]
P2-C: [R]
P2-D: [R] Aprovado em runtime
P2-E e seguintes: NÃO IMPLEMENTADOS
```

## Resultado

| Métrica | Resultado |
|---|---:|
| Gates executados | 8 |
| Aprovados | 8 |
| Falhas | 0 |
| Bloqueados | 0 |
| Não executados | 0 |

## Evidências registradas

1. Startup com schema versão 3, readiness verdadeiro e apply desligado.
2. ACE `mz_bank.accounts.backfill` validada para `group.mz_owner`; nove vetores inválidos negados.
3. Preview read-only: dois jogadores lidos, uma identidade existente e uma ausente, sem criação.
4. Apply controlado: uma identidade criada, uma preservada, zero falhas e retry desnecessário.
5. Repetição idempotente: duas existentes, zero ausentes e zero novas criações.
6. Paginação em duas páginas e oito previews concorrentes sem falha ou escrita.
7. Injeções controladas confirmaram `closed`, colisão recuperada, falha individual, retry e
   restauração das dependências sem escrita em contas.
8. Auditoria confirmou preview/start/completed, sem PII, seguida de abertura física, conta pública,
   saldo, extrato e fechamento da NUI preservados.

## Invariantes

- `mz_bank_accounts` continua sem saldo.
- O backfill não lê nem escreve wallet/bank/dirty.
- Saldos continuam exclusivamente sob os contratos oficiais do `mz_core`.
- Nenhum evento de rede, callback NUI ou export público foi criado pelo runner.
- Nenhum `citizenid`, license ou rota foi incluído na auditoria agregada do runner.
- O runner e o apply foram desligados após a execução e o `mz_bank` permaneceu ready.
- ATM, agência, overview, extrato e NUI permaneceram funcionais conforme confirmação do usuário.

## Limitações preservadas

- A evidência foi fornecida pelo usuário; não foram anexados dumps completos adicionais.
- O runner técnico permanece no resource, mas retorna antes de registrar o comando quando sua
  convar está desligada.
- O P2-D não implementa resolução privada, transferência por conta, cutover da NUI ou `phone`.
- A Fase 2 completa não está aprovada.

## Decisão

```text
P2-D: [R] APROVADO EM RUNTIME
8 aprovados
0 falhas
0 bloqueados
```

Próximo lote autorizado pelo desenho: P2-E — resolução privada, sem movimentação financeira.
