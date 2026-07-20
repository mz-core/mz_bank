# Fase 3 — Implementação do runner final P3-G

Data: 2026-07-19  
Estado: **VALIDADO ESTATICAMENTE; RUNTIME NÃO EXECUTADO**

## Objetivo

Executar em um único comando os seis deltas finais de resiliência da Fase 3, sem repetir operações
financeiras já aprovadas e sem alterar saldos reais.

## Arquivos alterados

| Arquivo | Alteração |
|---|---|
| `mz_core/server/accounts/p3g_runtime_runner.lua` | runner SQL com fixtures reservadas, console-only e desligado por padrão |
| `mz_core/server/accounts/outbox_dispatcher.lua` | pausa o loop automático somente enquanto a convar do runner P3-G estiver ativa |
| `mz_bank/reports/PHASE_3_P3_G_RUNTIME_CHECKLIST.md` | ativação, comando, resultado esperado, cleanup e teardown |
| `mz_bank/reports/PHASE_3_P3_G_RUNNER_IMPLEMENTATION.md` | registro desta implementação de teste |

## Garantias

- nenhuma chamada a `AddMoney`, `RemoveMoney`, `SetMoney`, transferência, payroll ou conta de org;
- snapshots agregados de wallet, bank, dirty e saldo organizacional antes/depois;
- fixtures usam somente `P3G_RT_OWNER` e razões `p3g_runtime_*`;
- cleanup limita-se às fixtures reservadas;
- nenhum evento de rede, callback NUI ou export;
- comandos aceitam exclusivamente `source == 0`;
- runner inerte quando `mz_core_p3g_runtime_runner=0`;
- dispatcher normal fica pausado somente com o runner ativo, evitando disputa não controlada;
- consumer real do `mz_economy` e repositories reais do `mz_core` são exercitados;
- falha SQL do consumer é dirigida por conflito de transaction ID exclusivamente na fixture;
- o conflito técnico é removido antes da consolidação.

## Cobertura

1. dois claims concorrentes reais no MySQL;
2. recuperação de lease expirado;
3. consumer commitado antes do ACK e replay posterior;
4. reschedule/backoff e décima tentativa em dead letter;
5. rollback atômico de recibo + ledger após falha SQL;
6. remoção das fixtures e igualdade dos saldos agregados.

## Validação estática

```text
outbox_dispatcher.lua: luac aprovado
p3g_runtime_runner.lua: luac aprovado
superfícies públicas encontradas: 0
escritas em saldo encontradas: 0
```

## Runtime pendente

Executar o procedimento de `PHASE_3_P3_G_RUNTIME_CHECKLIST.md`. Somente o resultado
`executed=6 passed=6 failed=0` e o teardown confirmado permitem decidir a Fase 3.

```text
P3-G runner: [S] Validado estaticamente
P3-G runtime: NÃO EXECUTADO
Fase 3: [~] Em implementação
```

