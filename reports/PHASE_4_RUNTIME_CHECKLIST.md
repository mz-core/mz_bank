# Fase 4 — Checklist runtime enxuto da API compartilhada

Data de criação: 2026-07-19  
Ambiente: FiveM staging  
Estado: **APROVADO**

Estados: `NÃO EXECUTADO`, `APROVADO`, `FALHOU`, `BLOQUEADO`.

## Runner seguro para os casos restantes

O runner usa somente fixtures em memória, não movimenta saldo, não escreve SQL e não bloqueia
cartão real. Ele complementa — sem repetir — o smoke físico já aprovado pelo usuário:

```text
set mz_bank_p4_runtime_runner 1
restart mz_bank
mz_bank_p4_runtime_test
set mz_bank_p4_runtime_runner 0
restart mz_bank
```

Resultado esperado: seis linhas `PASS`, resumo `executed=6 passed=6 failed=0` e, depois da
desativação, `No such command mz_bank_p4_runtime_test`.

| ID | Teste | Resultado esperado | Resultado real | Evidência | Status |
|---|---|---|---|---|---|
| P4-01 | Reiniciar `mz_core`, `mz_economy`, `mz_inventory`, `mz_bank` nessa ordem | Banco ready; sem erro de API; API v1 disponível | Resource iniciou corretamente, conforme confirmação do usuário após execução manual | FiveM staging, resultado fornecido pelo usuário | APROVADO |
| P4-02 | Abrir ATM e agência | Sessão física abre; canal/capacidades correspondem ao ponto real | ATM e agência abriram corretamente | FiveM staging, resultado fornecido pelo usuário | APROVADO |
| P4-03 | Overview e extrato em ATM/agência | DTO sem citizenid, license, ID SQL, `card_uid` ou metadata interna | Funcionalidade visual e sanitização automatizada aprovadas | FiveM staging + `PASS P4-DTO-01`, fornecidos pelo usuário | APROVADO |
| P4-04 | Depósito, saque e transferência pública de R$ 1 | Uma movimentação por chave; correlationId presente; saldo/extrato corretos | Depósito, saque e transferência funcionaram corretamente | FiveM staging, resultado fornecido pelo usuário | APROVADO |
| P4-05 | Repetir a mesma transferência com a mesma chave | Nenhum novo débito; replay recupera a mesma correlação | Adapter preservou chave/correlação; deduplicação financeira já aprovada nos testes reais P2-F/P3-F | `PASS P4-REPLAY-01` + evidência runtime anterior, confirmado pelo usuário | APROVADO |
| P4-06 | Agência: listar cartões e bloquear por `cardRef` | Lista sem `card_uid`; bloqueio válido; ref falsa negada | DTO, vínculo da referência e recusa de referência falsa aprovados com fixture sem escrita | `PASS P4-CARD-01`, fornecido pelo usuário | APROVADO |
| P4-07 | Versão ausente/incorreta e resource não autorizado | `api_version_required`, `api_version_unsupported`, `api_forbidden` | Versão e allowlist retornaram os erros esperados | `PASS P4-SEC-01`, fornecido pelo usuário | APROVADO |
| P4-08 | Token falso, expirado, de outro jogador e `channel=phone` no payload | Todos negados; payload não muda canal efetivo | Isolamento phone/físico aprovado; demais vetores preservam aprovação runtime do Lote A | `PASS P4-SEC-02` + `PHASE_0_LOT_A_RUNTIME_APPROVAL.md` | APROVADO |
| P4-09 | Chamada do `mz_phone` sem capability phone | Fail-closed; sem dados e sem operação | `mz_phone` não reutilizou canal físico; retorno financeiro sanitizado e read-only | `PASS P4-SEC-02` e `PASS P4-RESULT-01`, fornecidos pelo usuário | APROVADO |
| P4-10 | Restart final e smoke da NUI/animação/slot | NUI, animação, slot e fluxos físicos preservados | NUI, animação, slot e fluxos físicos confirmados | FiveM staging, resultado fornecido pelo usuário | APROVADO |

## Invariante SQL

```sql
SELECT column_name
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name = 'mz_bank_accounts'
  AND LOWER(column_name) IN ('balance', 'wallet', 'bank', 'money', 'amount');
```

Resultado obrigatório: zero linhas.

Para P4-04/P4-05, conferir a chave em `mz_account_idempotency`, o evento em
`mz_financial_outbox`, receipt e pernas esperadas no ledger. A repetição não pode criar nova
movimentação. Não registrar `citizenid`, token completo ou `cardRef` completo no relatório público.

```text
Casos: 10
Aprovados: 10
Falhas: 0
Bloqueados: 0
Não executados: 0
Fase 4: [R] Aprovada em runtime
```
