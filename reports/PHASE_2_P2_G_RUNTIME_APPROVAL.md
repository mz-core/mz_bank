# Fase 2 — Aprovação runtime do Lote P2-G

Data: 2026-07-17  
Ambiente: FiveM staging  
Origem da evidência: resultado fornecido pelo usuário após execução manual integral

```text
P2-G: [R] Aprovado em runtime
15 aprovados
0 falhas
0 bloqueados
```

## Resultado consolidado

| Métrica | Resultado |
|---|---:|
| Casos definidos | 15 |
| Executados | 15 |
| Aprovados | 15 |
| Falhas | 0 |
| Bloqueados | 0 |
| Não executados | 0 |

## Funcionalidades confirmadas

- inicialização e readiness do `mz_bank`;
- campos agência, conta e DV no lugar do server ID;
- resolução de destinatário com nome parcial e conta mascarada;
- confirmação e cancelamento sem movimentação indevida;
- rejeição de rota inválida, token inválido/expirado/de outro jogador e payload adulterado;
- transferência confirmada, duplo clique, replay e idempotência;
- rejeição de saldo insuficiente, valores inválidos, autotransferência, offline e estados restritos;
- comprovante seguro com `correlationId`;
- ATM, agência, animação, alinhamento, NUI e slot preservados;
- saque, depósito, extrato, restart e limpeza sem regressão.

## Invariantes observadas

- server ID não integra mais o contrato final de transferência física;
- nenhum `citizenid`, source, license ou ID SQL é exposto pela NUI;
- o token é revalidado no servidor antes da transferência;
- saldo/cache/persistência permanecem sob os serviços oficiais do `mz_core`;
- `mz_bank_accounts` continua sem saldo;
- não houve movimentação duplicada nem falha pendente conhecida;
- phone, transferência offline e P2-H não foram antecipados.

## Evidência e limitações

O usuário confirmou que todos os casos do
`reports/PHASE_2_P2_G_RUNTIME_CHECKLIST.md` foram executados e passaram. Não foram fornecidos logs,
queries, vídeos ou capturas adicionais nesta aprovação; portanto, o relatório registra somente essa
evidência declarada, sem inventar anexos.

## Decisão

```text
P2-G: [R] Aprovado em runtime
Fase 2: [~] Em implementação
```

O próximo passo permitido é o P2-H — revisão estática independente, regressão integral e decisão
final da Fase 2. Esta aprovação não implementa o aplicativo do telefone.

