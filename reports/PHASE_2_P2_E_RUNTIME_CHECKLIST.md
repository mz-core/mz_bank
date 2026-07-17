# Fase 2 — Checklist runtime do Lote P2-E

Data: 2026-07-17  
Ambiente esperado: MySQL/FiveM staging  
Estado: **APROVADO**

```text
Fase 2: [~] Em implementação
P2-E: [R] Aprovado em runtime
Runtime P2-E: APROVADO
```

## 1. Limite da validação

O P2-E não possui callback, evento ou export público. Os casos internos devem ser executados pelo
runner `server/p2e_runtime_runner.lua`, server-side, staging-only, desativado por padrão e sem aceitar
input do client. Ele usa fixtures exclusivamente em memória, chama o serviço real P2-E, restaura as
dependências ao terminar e não movimenta saldo. Somente logs de auditoria podem ser persistidos.

Não movimentar saldo, não alterar a NUI e não testar transferência por conta nesta rodada.

Estados permitidos: `NÃO EXECUTADO`, `APROVADO`, `FALHOU`, `BLOQUEADO`, `NÃO APLICÁVEL`.

### Execução em staging

No console do servidor:

```text
set mz_bank_public_account_p2c 1
set mz_bank_p2e_runtime_runner 1
restart mz_bank
mz_bank_p2e_runtime_test
```

O comando não recebe argumentos. O resumo esperado é `executed=12 passed=12 failed=0`. O item
`P2E-12-INTERNAL` comprova somente que o runner não chamou serviços financeiros; a abertura física,
NUI, animação, slot e transferência atual continuam exigindo o smoke test manual descrito em
`P2E-12`.

Após capturar o console e executar o smoke test manual:

```text
set mz_bank_p2e_runtime_runner 0
restart mz_bank
mz_bank_p2e_runtime_test
```

O último comando deve responder `No such command`, comprovando que o runner ficou inerte.

## 2. Casos

### P2E-01 — startup e superfície privada

- **Pré-condições:** schema 3; feature pública ligada somente em staging.
- **Passos:** reiniciar `mz_bank`; conferir status P2-E; buscar callbacks/eventos/exports.
- **Esperado:** `ready=true`, `enabled=true`, TTL 60; nenhum endpoint client-facing.
- **Resultado real/evidência:** runner executado no FiveM staging; `ready=true enabled=true ttl=60 private=true`.
- **Status:** `APROVADO`

### P2E-02 — rota ativa e DTO mínimo

- **Passos:** resolver rota exata de conta `active` pertencente a jogador online.
- **Esperado:** nome parcial, agência, conta mascarada, token opaco e `expiresIn=60`; nenhuma PII.
- **Resultado real/evidência:** runner retornou DTO mascarado, nome parcial, token opaco e TTL 60.
- **Status:** `APROVADO`

### P2E-03 — conta blocked recebível

- **Passos:** resolver conta `blocked` online.
- **Esperado:** resolução permitida para recebimento; estado interno não aparece no DTO.
- **Resultado real/evidência:** runner confirmou `blocked=receivable state=private`.
- **Status:** `APROVADO`

### P2E-04 — formato, DV e enumeração

- **Passos:** agência/número/DV inválidos; rota inexistente; contas frozen/closed; titular offline.
- **Esperado:** inválidos retornam `recipient_invalid`; os quatro alvos indisponíveis têm resposta
  pública idêntica `recipient_unavailable` e não revelam nome/estado/existência.
- **Resultado real/evidência:** runner confirmou formato inválido negado e quatro vetores indisponíveis com resposta uniforme.
- **Status:** `APROVADO`

### P2E-05 — autotransferência

- **Passos:** resolver a própria rota.
- **Esperado:** `self_transfer`, sem token e sem dado adicional.
- **Resultado real/evidência:** runner confirmou `self_transfer=denied token=false`.
- **Status:** `APROVADO`

### P2E-06 — vínculo e expiração do token

- **Passos:** validar token correto; falso; alterado; outro source/citizenid/sessão/canal; expirar
  após 60 segundos; fechar sessão; disconnect; restart.
- **Esperado:** somente o contexto original antes do TTL valida; demais retornam erro estável sem
  revelar o alvo.
- **Resultado real/evidência:** runner confirmou vínculo a source/citizenid/sessão/canal, TTL 60 e limpeza do token.
- **Status:** `APROVADO`

### P2E-07 — revalidação do alvo

- **Passos:** após emitir token, colocar alvo frozen/closed, desconectar ou alterar a rota fixture.
- **Esperado:** token deixa de validar e é removido; nenhum saldo muda.
- **Resultado real/evidência:** runner confirmou revalidação de estado/presença e remoção do token inválido.
- **Status:** `APROVADO`

### P2E-08 — limite 5/60 segundos

- **Passos:** realizar cinco resoluções admitidas na mesma sessão/canal e tentar a sexta.
- **Esperado:** cinco admitidas; sexta `rate_limited`; restart documentadamente reinicia contador.
- **Resultado real/evidência:** runner admitiu cinco tentativas e limitou a sexta.
- **Status:** `APROVADO`

### P2E-09 — limite 20/hora e cooldown

- **Passos:** distribuir 20 tentativas entre sessões do mesmo ator; tentar a 21ª; em fixture
  separada provocar três ou mais falhas consecutivas.
- **Esperado:** 21ª limitada; cooldown 2/4/8... até 30 s; limites não vêm do client.
- **Resultado real/evidência:** runner admitiu 20 tentativas, limitou a 21ª e aplicou cooldown após três falhas.
- **Status:** `APROVADO`

### P2E-10 — capacidade e concorrência

- **Passos:** concorrência controlada e tentativa de exceder 20 tokens ativos por source.
- **Esperado:** tokens únicos; nenhuma troca de alvo; excesso negado; zero escrita financeira.
- **Resultado real/evidência:** runner concluiu 20 chamadas concorrentes com 20 tokens únicos e excesso negado.
- **Status:** `APROVADO`

### P2E-11 — auditoria e privacidade

- **Query:**

```sql
SELECT action, actor, target, data_json, created_at
FROM mz_logs
WHERE scope = 'bank'
  AND action LIKE 'bank.public_account.resolve.%'
ORDER BY id DESC;
```

- **Esperado:** accepted, invalid, unavailable, rate_limited, self_transfer e token_rejected quando
  aplicáveis; nenhum token, nome completo, citizenid alvo ou rota completa no `data_json`.
- **Resultado real/evidência:** runner verificou 74 registros capturados, seis ações esperadas, sem PII e sem token.
- **Status:** `APROVADO`

### P2E-12 — não regressão financeira e física

- **Passos:** snapshot de `mz_player_accounts`; executar todos os casos; repetir snapshot; abrir ATM
  e agência; consultar overview/extrato; executar transferência atual por server ID.
- **Esperado:** testes de resolução não alteram saldo/ledger; fluxo físico, animação, slot e NUI
  preservados; transferência atual continua oficial e única.
- **Resultado real/evidência:** controle interno confirmou zero chamadas financeiras e zero escrita de saldo; usuário confirmou o smoke test manual no FiveM como aprovado.
- **Status:** `APROVADO`

## 3. Resultado consolidado

| Métrica | Resultado |
|---|---:|
| Casos | 12 |
| Executados | 12 |
| Aprovados | 12 |
| Falhas | 0 |
| Bloqueados | 0 |
| Não executados | 0 |

Resultado fornecido pelo usuário após execução no FiveM staging em 2026-07-17. O console registrou
`SUMMARY executed=12 passed=12 failed=0`; o smoke test físico/financeiro foi confirmado como aprovado.
Após os testes, o usuário confirmou que o runner foi desativado e que o comando retornou o resultado
esperado (`No such command`).

```text
P2-E: [R] Aprovado em runtime
12 aprovados
0 falhas
0 bloqueados
```
