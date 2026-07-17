# Fase 2 — Checklist runtime do Lote P2-F

Data: 2026-07-17  
Ambiente esperado: MySQL/FiveM staging  
Estado: **APROVADO**

```text
Fase 2: [~] Em implementação
P2-E: [R] Aprovado em runtime
P2-F: [R] Aprovado em runtime
Runtime P2-F: APROVADO
```

## 1. Limite

O P2-F não possui callback, evento ou export novo. Seus casos internos usam
`server/p2f_runtime_runner.lua`, server-side, staging-only, desativado por padrão e sem input do
client. O modo interno usa fixtures em memória e restaura dependências. O modo real usa os métodos
P2-E/P2-F e o core oficiais, movimentando uma única vez o valor explicitamente configurado.

Não alterar a NUI, não iniciar P2-G, não habilitar phone e não criar transferência offline.

Estados permitidos: `NÃO EXECUTADO`, `APROVADO`, `FALHOU`, `BLOQUEADO`, `NÃO APLICÁVEL`.

## 2. Execução

### 2.1 Runner interno — sem saldo real

No console:

```text
refresh
set mz_bank_p2b_runtime_runner 0
set mz_bank_p2d_runtime_runner 0
set mz_bank_p2e_runtime_runner 0
set mz_bank_p2f_runtime_allow_transfer 0
set mz_bank_public_account_p2c 1
set mz_bank_p2f_runtime_runner 1
restart mz_bank
mz_bank_p2f_runtime_test
```

Resultado esperado:

```text
SUMMARY mode=internal executed=14 passed=14 failed=0
```

### 2.2 Runner financeiro real — movimenta saldo

Pré-condições:

- dois jogadores reais online;
- ambos com conta pública;
- remetente com saldo suficiente;
- definir os **server IDs numéricos**, nunca citizenids;
- escolher valor entre 1 e 1.000;
- após o restart, o remetente abre e mantém ATM/agência abertos.

Exemplo para remetente source `1`, destinatário source `2` e valor `1`:

```text
set mz_bank_p2f_runtime_actor_source 1
set mz_bank_p2f_runtime_target_source 2
set mz_bank_p2f_runtime_amount 1
set mz_bank_p2f_runtime_allow_transfer 1
restart mz_bank
```

Depois do restart, abrir o banco no personagem remetente e executar no console do servidor:

```text
mz_bank_p2f_runtime_transfer
```

O comando executa uma transferência real, um replay com a mesma chave e um conflito controlado. O
saldo deve mudar somente na primeira confirmação. Resultado esperado:

```text
PASS P2F-REAL detail=... replay=true conflict=true persistence=true correlation=set
```

### 2.3 Desativação

Após as evidências e o smoke test:

```text
set mz_bank_p2f_runtime_allow_transfer 0
set mz_bank_p2f_runtime_runner 0
restart mz_bank
mz_bank_p2f_runtime_test
mz_bank_p2f_runtime_transfer
```

Os dois últimos comandos devem retornar `No such command`.

## 3. Snapshots obrigatórios

Antes e depois de cada grupo financeiro, registrar os dois personagens reais:

```sql
SELECT citizenid, wallet, bank, dirty, updated_at
FROM mz_player_accounts
WHERE citizenid IN ('<REMETENTE>', '<DESTINATARIO>')
ORDER BY citizenid;
```

Conferir idempotência e ledger pela chave usada:

```sql
SELECT source_resource, actor_citizenid, idempotency_key, operation,
       request_fingerprint, correlation_id, result_json, created_at
FROM mz_account_idempotency
WHERE source_resource = 'mz_bank'
  AND idempotency_key = '<CHAVE_DO_TESTE>';
```

```sql
SELECT *
FROM mz_economy_ledger
WHERE correlation_id = '<CORRELATION_ID>'
ORDER BY id;
```

O nome real da tabela de ledger deve ser confirmado antes da query; não inventar tabela se o schema
do ambiente usar outro nome.

## 4. Casos

### P2F-01 — serviço interno e ausência de superfície pública

- **Esperado:** método interno disponível; nenhum callback/evento/export/NUI/phone P2-F.
- **Resultado real/evidência:** runner confirmou serviço disponível e ausência de superfície client-facing.
- **Status:** `APROVADO`

### P2F-02 — transferência active → active

- **Passos:** emitir token válido; transferir valor inteiro com chave nova.
- **Esperado:** uma única movimentação; correlationId oficial; token consumido; saldos/cache/SQL coerentes.
- **Resultado real/evidência:** teste real confirmou `amount=1`, `fee=0`, remetente `-1`, destinatário `+1`, persistência e correlationId.
- **Status:** `APROVADO`

### P2F-03 — destino blocked recebível

- **Esperado:** transferência permitida; estado não exposto ao consumidor.
- **Resultado real/evidência:** runner interno confirmou `blocked_target=receivable`.
- **Status:** `APROVADO`

### P2F-04 — estados da origem

- **Vetores:** origem `blocked`, `frozen` e `closed`.
- **Esperado:** todos negados para saída antes da chamada financeira; saldo intacto.
- **Resultado real/evidência:** três estados negados antes da chamada financeira.
- **Status:** `APROVADO`

### P2F-05 — alvo alterado após preview

- **Vetores:** alvo passa para `frozen`/`closed`, fica offline ou muda a fixture esperada.
- **Esperado:** token rejeitado; nenhuma chamada financeira e nenhuma alteração de saldo.
- **Resultado real/evidência:** revalidação injetada negou alvo indisponível sem chamada financeira.
- **Status:** `APROVADO`

### P2F-06 — vínculo, expiração e consumo do token

- **Vetores:** token falso, expirado, outro source/citizenid/sessão/canal; reutilização após sucesso.
- **Esperado:** todos negados; somente contexto original antes do consumo pode confirmar.
- **Resultado real/evidência:** token inválido/autotransferência negados e token confirmado consumido.
- **Status:** `APROVADO`

### P2F-07 — valor, limite e taxa

- **Vetores:** decimal, zero, negativo, texto, NaN/infinito, acima do limite e valor válido.
- **Esperado:** somente inteiro positivo dentro do limite chega ao core; taxa e arredondamento iguais ao fluxo atual.
- **Resultado real/evidência:** sete vetores inválidos foram negados antes do core; teste real confirmou inteiro e taxa zero configurada.
- **Status:** `APROVADO`

### P2F-08 — saldo insuficiente e overflow

- **Esperado:** erro oficial normalizado; token terminal consumido; nenhum débito/crédito parcial.
- **Resultado real/evidência:** falha terminal de saldo insuficiente foi normalizada e consumiu o token sem resultado parcial.
- **Status:** `APROVADO`

### P2F-09 — replay com nova resolução

- **Passos:** confirmar operação; emitir novo token; repetir mesma chave, alvo, valor e taxa.
- **Esperado:** resultado recuperado com `replayed=true`; mesmo correlationId; saldo e ledger não duplicados.
- **Resultado real/evidência:** teste financeiro real confirmou replay, correlationId estável e ausência de segunda movimentação.
- **Status:** `APROVADO`

### P2F-10 — conflito de idempotência

- **Passos:** repetir a chave com alvo, valor ou taxa diferente.
- **Esperado:** `idempotency_conflict`; zero nova movimentação.
- **Resultado real/evidência:** teste financeiro real confirmou conflito e ausência de nova movimentação.
- **Status:** `APROVADO`

### P2F-11 — duplo clique e concorrência

- **Esperado:** lock/busy/idempotência impedem duplicidade; exatamente uma movimentação confirmada.
- **Resultado real/evidência:** oito chamadas concorrentes injetadas resultaram em um único commit; replay real não duplicou saldo.
- **Status:** `APROVADO`

### P2F-12 — falha SQL e timeout após commit

- **Esperado:** falha antes do commit não move saldo; resposta ambígua pode ser recuperada com nova resolução e mesma chave; nunca duplicar.
- **Resultado real/evidência:** erro ambíguo injetado preservou o token; commit real seguido de replay confirmou recuperação sem duplicidade. Não foi provocado timeout de infraestrutura destrutivo.
- **Status:** `APROVADO`

### P2F-13 — destinatário offline e autotransferência

- **Esperado:** erro estável, nenhum crédito SQL direto, nenhuma fila/outbox e nenhum saldo alterado.
- **Resultado real/evidência:** ambos negados com resposta uniforme/estável, token terminal consumido e sem fila offline.
- **Status:** `APROVADO`

### P2F-14 — privacidade e auditoria

- **Esperado:** NUI/client não recebe citizenid, source alvo, ID SQL, token em log ou rota completa desnecessária; correlationId preservado.
- **Resultado real/evidência:** 26 auditorias observadas pelo runner sem token ou PII; correlationId confirmado no teste real.
- **Status:** `APROVADO`

### P2F-15 — regressão do fluxo atual

- **Passos:** abrir ATM/agência; overview/extrato; depósito, saque e transferência atual por server ID; fechar NUI.
- **Esperado:** fluxo atual, animação, alinhamento, slot e serviços oficiais permanecem funcionais.
- **Resultado real/evidência:** usuário confirmou manualmente o smoke test como aprovado no FiveM.
- **Status:** `APROVADO`

### P2F-16 — restart e limpeza

- **Passos:** reiniciar `mz_bank`; tentar token anterior; confirmar readiness; repetir smoke.
- **Esperado:** token em memória deixa de existir; saldos persistidos permanecem corretos; serviço volta ready.
- **Resultado real/evidência:** usuário confirmou restart funcional e runner desativado após os testes.
- **Status:** `APROVADO`

## 5. Invariantes

1. O destinatário financeiro vem somente do token server-side revalidado.
2. O core recebe `citizenid` estável, nunca valor arbitrário do client.
3. Exatamente uma operação financeira corresponde a uma chave/payload.
4. Sucesso financeiro não vira falha por erro posterior de overview/extrato.
5. `mz_bank_accounts` não contém saldo.
6. Não existe escrita direta em `mz_player_accounts` pelo `mz_bank`.
7. Destinatário permanece online.
8. P2-G, phone, PIX e transferência offline não são antecipados.

## 6. Consolidado

| Métrica | Resultado |
|---|---:|
| Casos | 16 |
| Executados | 16 |
| Aprovados | 16 |
| Falhas | 0 |
| Bloqueados | 0 |
| Não executados | 0 |

```text
P2-F: [R] Aprovado em runtime
Runtime P2-F: APROVADO
16 aprovados
0 falhas
0 bloqueados
```

Resultados fornecidos pelo usuário após execução no FiveM staging em 2026-07-17. Evidências:

- `SUMMARY mode=internal executed=14 passed=14 failed=0`;
- `PASS P2F-REAL detail=amount=1 fee=0 sender_delta=-1 target_delta=1 replay=true conflict=true persistence=true correlation=set`;
- smoke test manual aprovado;
- runner e autorização de transferência real desativados.
