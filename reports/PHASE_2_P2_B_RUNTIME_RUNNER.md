# Fase 2 — Runner temporário do P2-B

Data: 2026-07-15  
Estado: **EXECUTADO EM STAGING; DESATIVADO APÓS OS TESTES**

## 1. Limites

O runner está em `server/p2b_runtime_runner.lua`, carregado exclusivamente como `server_script`.
No estado padrão, `mz_bank_p2b_runtime_runner = 0`, o arquivo termina antes de registrar qualquer
comando, evento, callback, export ou thread.

O runner:

- aceita somente o console do servidor (`source == 0`);
- não registra evento de rede, callback NUI ou export;
- usa vetores fixos, sem aceitar titular ou rota como argumento;
- chama diretamente os dois métodos reais de `MZBankRepository`;
- não contém `INSERT`, `UPDATE`, `DELETE` ou chamada financeira;
- mascara os titulares sintéticos e números de conta nos logs;
- executa 20 buscas concorrentes por owner e 20 por rota;
- produz `PASS`/`FAIL` e resumo para oito casos internos.

## 2. Ativação em staging

Não adicionar a convar ao `server.cfg`. No console do servidor:

```text
set mz_bank_p2b_runtime_runner 1
restart mz_bank
```

Confirmação esperada:

```text
[mz_bank][p2b-runner] enabled staging_only=true command=mz_bank_p2b_runtime_test source=console fixed_vectors=true
```

## 3. Preparação SQL

Executar a seção 5 de `PHASE_2_P2_B_RUNTIME_CHECKLIST.md`. Confirmar primeiro zero colisões e,
somente depois, inserir as duas linhas sintéticas fixas:

```text
P2B_RT_OWNER_A -> 0001/87654321-0 -> active
P2B_RT_OWNER_B -> 0001/99999999-9 -> blocked
```

O runner nunca cria esses registros.

## 4. Snapshots antes

Executar integralmente a seção 6 do checklist e guardar:

- as duas linhas de identidade;
- wallet/bank/dirty dos personagens do smoke test;
- resultado vazio da busca por colunas de saldo paralelo.

## 5. Execução

No console do servidor, sem argumentos:

```text
mz_bank_p2b_runtime_test
```

O resumo esperado, se os oito casos internos passarem, é:

```text
[mz_bank][p2b-runner] SUMMARY executed=8 passed=8 failed=0
```

Copiar todas as linhas entre `START` e `END` para os campos de evidência do checklist. O resumo
sozinho não substitui snapshots SQL nem os cinco casos manuais restantes.

## 6. Snapshots depois e casos manuais

Repetir a seção 6 e comparar integralmente. Depois executar manualmente:

- `P2B-PRIV-01`;
- `P2B-FIN-01`;
- `P2B-REG-01`;
- `P2B-RESTART-01`;
- `P2B-CLEAN-01`.

Não marcar nenhum deles como aprovado apenas pelo resultado do runner.

## 7. Limpeza

Executar somente o `DELETE` exato documentado em `P2B-CLEAN-01`, confirmar duas linhas removidas
e zero linhas sintéticas restantes. O runner não realiza limpeza automaticamente.

## 8. Desativação obrigatória

No console do servidor:

```text
set mz_bank_p2b_runtime_runner 0
restart mz_bank
```

Confirmações obrigatórias:

1. o log `enabled staging_only=true` não aparece após o restart;
2. `mz_bank_p2b_runtime_test` não executa e não produz `START`;
3. `mz_bank` volta a informar readiness normal na versão 3;
4. a convar não foi persistida em nenhum arquivo `.cfg`.

## 9. Decisão atual

Validações estáticas executadas:

```text
luac -p server/p2b_runtime_runner.lua: PASS
luac -p server/repository.lua: PASS
luac -p server/account_identity.lua: PASS
luac -p server/main.lua: PASS
superfície/eventos/exports/escritas proibidas no runner: ZERO
harness isolado: reads=49 cases=8 summary_ok=true default_disabled=true console_only=true
```

O `config.lua` usa literais hash com crase próprios do runtime Cfx/FiveM (`prop_atm_01`, etc.),
portanto o parser Lua genérico não aceita esse arquivo isoladamente. Isso é preexistente e não é
erro do runner; os arquivos server-side envolvidos passaram no parser disponível.

```text
Runner: VALIDADO ESTATICAMENTE
Runner em runtime: APROVADO E DESATIVADO
P2-B: [R] Aprovado em runtime
Fase 2: [~] Em implementação
```

O usuário forneceu os logs do runner com `executed=8 passed=8 failed=0`, confirmou os cinco casos
manuais restantes, a limpeza com resultado esperado e a ausência do comando após desativação e
restart. As saídas SQL integrais não foram anexadas; essa limitação permanece registrada no
checklist e no relatório de aprovação.
