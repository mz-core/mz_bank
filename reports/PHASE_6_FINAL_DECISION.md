# Fase 6 — Decisão final

Data: 2026-07-20  
Ambiente: MySQL/FiveM staging  
Decisão: **Fase 6 `[R]` aprovada em runtime**

## Lotes concluídos

| Lote | Resultado |
|---|---|
| P6-A — saldo, conta, extrato, cartões e indisponibilidade | `[R]` |
| P6-B — transferência, confirmação e comprovante | `[R]` |
| P6-C — listagem e bloqueio de cartão | `[R]` |
| P6-D — favoritos bancários | `[R]` |
| P6-E — notificações deduplicadas | `[R]` |

## Gates finais

- o aplicativo consome somente a API server-side oficial do `mz_bank`;
- sessão e canal são determinados no servidor e vinculados ao personagem/aparelho;
- saldo, locks, idempotência, ledger e outbox pertencem ao `mz_core`;
- conta pública substitui server ID no aplicativo;
- transferência exige destinatário online, confirmação e valor inteiro;
- duplo clique/replay não duplica movimentação nem notificação;
- comprovante usa a referência financeira oficial;
- bloqueio do cartão no telefone invalida seu uso posterior no ATM;
- favoritos não armazenam saldo nem `citizenid` do destinatário;
- indisponibilidade do banco não encerra o restante do telefone;
- nenhum saldo, ledger ou contrato financeiro paralelo foi criado no `mz_phone`.

## Evidências consideradas

A decisão consolida os relatórios runtime de P6-A, P6-B, P6-C, P6-D e P6-E. Para o P6-E, a
evidência fornecida foi a confirmação textual do usuário após o teste manual solicitado. Não foram
anexados logs, capturas ou query SQL e nenhum dado adicional foi inventado.

## Limitações intencionais

- transferência offline continua proibida;
- o binding lógico do aparelho usa o número de telefone, pois ainda não existe UID físico do item;
- emissão, desbloqueio e segunda via permanecem fora do aplicativo;
- PIX, QR Code, contas organizacionais e produtos financeiros não pertencem à Fase 6;
- runners, comandos e hooks de staging foram removidos; relatórios históricos permanecem.

## Decisão

```text
Fase 6: [R] Aprovada em runtime
Lotes aprovados: 5/5
Falhas pendentes conhecidas da Fase 6: 0
Limpeza de produção: [R] Aprovada após smoke final
Estado do MVP banco + aplicativo: CONCLUÍDO
```
