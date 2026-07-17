# Fase 2 — Checklist runtime do Lote P2-D

Data: 2026-07-17  
Ambiente: MySQL/FiveM staging com backup restaurável  
Estado: **APROVADO EM RUNTIME**

```text
P2-D: [R] Aprovado em runtime
Runtime P2-D: 8/8 APROVADOS; RUNNER/APPLY DESLIGADOS
Fase 2: [~] Em implementação
```

## 1. Preparação

Não adicionar as convars permanentemente ao `.cfg` nesta rodada.

```text
set mz_bank_public_account_p2c 1
set mz_bank_p2d_backfill_apply 0
restart mz_bank
```

ACE proposta, sem edição automática:

```text
add_ace group.mz_owner mz_bank.accounts.backfill allow
```

Esta é a opção recomendada quando o administrador já pertence a `group.mz_owner`: carregar a ACE
pelo `permissions.cfg` e executar o comando pelo F8/chat dentro do jogo. A verificação então usa as
identifiers reais do jogador. A saída agregada continua sendo registrada no console do servidor.

Para executar diretamente pelo console do servidor durante o staging, conceder temporariamente a
mesma ACE dedicada ao principal real do console:

```text
add_ace system.console mz_bank.accounts.backfill allow
test_ace system.console mz_bank.accounts.backfill
```

O `test_ace` deve retornar `ALLOW`. Depois dos testes, remover a concessão temporária:

```text
remove_ace system.console mz_bank.accounts.backfill allow
```

O console não pode conceder acesso novo a si próprio durante a execução (`Changing ones own access
is not permitted`). Portanto, essa alternativa somente pode ser declarada previamente na
configuração e carregada no boot completo; não usar como comando de autoelevação no txAdmin.

### Runner técnico dos gates restantes

O runner `server/p2d_runtime_runner.lua` é carregado exclusivamente no servidor e retorna sem
registrar comando quando a convar está desligada. Ele não cria conta, não consulta saldo e não
registra evento, callback ou export. As injeções de `closed`, colisão e falha são temporárias,
restauradas antes do resultado, e persistem apenas auditoria agregada.

Ativação deliberada em staging:

```text
set mz_bank_public_account_p2c 1
set mz_bank_p2d_backfill_apply 1
set mz_bank_p2d_runtime_runner 1
restart mz_bank
mz_bank_p2d_runtime_test
```

Encerramento obrigatório após o resumo:

```text
set mz_bank_p2d_runtime_runner 0
set mz_bank_p2d_backfill_apply 0
restart mz_bank
```

Snapshots:

```sql
SELECT citizenid, wallet, bank, dirty
FROM mz_player_accounts
ORDER BY citizenid;

SELECT COUNT(*) AS public_accounts_before
FROM mz_bank_accounts;
```

## 2. Estados

- `NÃO EXECUTADO`
- `APROVADO`
- `FALHOU`
- `BLOQUEADO`
- `NÃO APLICÁVEL`

## 3. Gates consolidados

### P2D-01 — startup, schema e apply desligado

- **Passos:** reiniciar com P2-C ativo e apply `0`; observar status P2-D; tentar apply arbitrário.
- **Esperado:** schema v3 e banco ready; comando registrado; apply negado; nenhuma linha criada.
- **Resultado real/evidência:** execução manual fornecida pelo usuário em 2026-07-17: resource
  iniciou com `status ready=true apply=false`, comando registrado, schema version 3 ready e saldos
  declarados exclusivamente pelo `mz_core`. Após o apply controlado, o usuário desativou novamente
  a convar, reiniciou o resource e confirmou `ready=true apply=false`.
- **Status:** `APROVADO`

### P2D-02 — ACE, argumentos e confirmação

- **Passos:** testar sem ACE e com ACE; batch 0/501/texto; cursor negativo; run_ref, ator, parâmetros e frase adulterados.
- **Esperado:** todos os inválidos negados antes de criação; nenhuma PII no console.
- **Resultado real/evidência:** primeira tentativa fornecida pelo usuário em 2026-07-17 foi
  corretamente negada sem ACE, mas revelou erro da native ao receber `source=0`:
  `Argument at index 0 was null` e `denied source=0 error=backfill_forbidden`. O código foi
  corrigido para validar o console por `IsPrincipalAceAllowed('system.console', ace)`. O runner
  técnico executado pelo usuário em 2026-07-17 retornou `owner_ace_missing`, confirmando que a ACE
  dedicada ainda não estava aplicada ao principal `group.mz_owner` no ambiente carregado. Após
  `exec cfg/permissions.cfg`, o `test_ace` confirmou `true`, mas a segunda execução revelou que o
  runner exigia booleano Lua estrito. O runner foi corrigido para normalizar retornos booleanos,
  numéricos e textuais da native, como o comando real já fazia. Nova execução manual fornecida pelo
  usuário em 2026-07-17 retornou `PASS P2D-02`, `ace=owner`, `vectors=9 rejected` e `writes=0`.
- **Status:** `APROVADO`

### P2D-03 — preview read-only

- **Comando:** `mz_bank_accounts_backfill preview 100 0`
- **Esperado:** `run_ref`, cursor e contagens agregadas; `created=0`; tabela e saldos inalterados; log de preview persistido.
- **Resultado real/evidência:** preview manual fornecido pelo usuário em 2026-07-17 retornou
  `ok=true`, `batch=100`, `after=0`, `next=2`, `read=2`, `existing=1`, `missing=1`, `created=0`,
  `failures=0`, `invalid=0`, `has_more=false`, `zero_balance_changes=true`. Nenhuma criação ocorreu
  durante o preview.
- **Status:** `APROVADO`

### P2D-04 — apply de um lote

- **Preparação:** revisar o preview e então executar:

```text
set mz_bank_p2d_backfill_apply 1
restart mz_bank
mz_bank_accounts_backfill preview 100 0
mz_bank_accounts_backfill apply <run_ref> 100 0 APPLY_PUBLIC_ACCOUNT_BACKFILL
```

- **Esperado:** ausentes criadas, existentes/closed preservadas, falhas/colisões agregadas, cursor retornado e log final persistido.
- **Resultado real/evidência:** apply manual fornecido pelo usuário em 2026-07-17 retornou
  `ok=true`, `run_ref=p2d-1784299654-03bb262224f98e73`, `read=2`, `existing=1`, `created=1`,
  `closed=0`, `collisions=0`, `failures=0`, `retry=false`, `error=none` e
  `zero_balance_changes=true`. Preview posterior retornou `existing=2`, `missing=0`, `created=0`,
  confirmando persistência e ausência de duplicação nessa repetição.
- **Status:** `APROVADO`

### P2D-05 — paginação, repetição, restart e concorrência

- **Passos:** repetir o mesmo cursor; avançar por `next`; interromper entre lotes, reiniciar, gerar novo preview e retomar; concorrer uma lazy creation.
- **Esperado:** nenhuma duplicidade; sucessos anteriores passam a existentes; uma conta pessoal por titular; cursor não pula linha.
- **Resultado real/evidência:** a repetição manual do cursor após o apply retornou `existing=2`,
  `missing=0`, `created=0`, sem duplicação; restart preservou as duas contas. Runner técnico
  executado manualmente pelo usuário em 2026-07-17 aprovou `pages=2`, `concurrent=8`, `failures=0`
  e `writes=0`.
- **Status:** `APROVADO`

### P2D-06 — closed, colisão e falha individual

- **Passos:** usar fixtures descartáveis para closed, colisão recuperável e falha controlada de uma criação.
- **Esperado:** closed contabilizada sem substituição; colisão usa retry; falha é agregada; cursor anterior é devolvido; demais sucessos permanecem.
- **Resultado real/evidência:** runner técnico executado manualmente pelo usuário em 2026-07-17
  aprovou `closed=1`, `created=1`, `collision=1`, `failure=1`, `retry=true`, `writes=0` e
  `dependencies=restored`.
- **Status:** `APROVADO`

### P2D-07 — auditoria e privacidade

- **Query:**

```sql
SELECT action, actor, target, data_json, created_at
FROM mz_logs
WHERE scope = 'bank'
  AND action LIKE 'public_account_backfill_%'
ORDER BY id DESC;
```

- **Esperado:** preview/start/final presentes; somente run_ref, cursores, contagens e códigos; nenhuma lista de citizenids, nomes ou rotas.
- **Resultado real/evidência:** runner técnico executado manualmente pelo usuário em 2026-07-17
  aprovou `rows=3`, ações `preview,start,completed` e `pii=false`.
- **Status:** `APROVADO`

### P2D-08 — invariantes financeiras, regressão e encerramento

- **Passos:** repetir snapshots; abrir ATM/agência; conferir overview; desativar apply e reiniciar.
- **Esperado:** wallet/bank/dirty idênticos; `mz_bank_accounts` sem saldo; NUI/animação/slot e operações atuais preservados; apply volta a ser negado.
- **Resultado real/evidência:** usuário confirmou manualmente em 2026-07-17, após desligar apply e
  reiniciar, que o banco físico abriu, a conta pública apareceu, saldo e extrato permaneceram
  corretos e a NUI fechou normalmente. Console confirmou `ready=true apply=false`, schema 3 e
  saldos exclusivos do `mz_core`.
- **Status:** `APROVADO`

## 4. Resultado consolidado

| Métrica | Resultado |
|---|---:|
| Gates | 8 |
| Executados | 8 |
| Aprovados | 8 |
| Falhas | 0 |
| Bloqueados | 0 |
| Não executados | 0 |

Os oito gates foram executados e registrados. O usuário confirmou o encerramento operacional com
`mz_bank_p2d_runtime_runner=0` e `mz_bank_p2d_backfill_apply=0` após restart. Os gates foram
consolidados para evitar repetir testes já aprovados sem regressão.
