# Fase 6 — Smoke final de produção

Data: 2026-07-20  
Estado: **APROVADO**

## PROD-SMOKE-01 — banco e aplicativo após limpeza

1. Reiniciar o servidor pela configuração normal, sem qualquer convar de runner.
2. Confirmar no console a ordem `mz_core`, `mz_economy`, `mz_inventory`, `mz_bank`, `mz_phone` e
   ausência de mensagens `runner enabled` ou `No such export`.
3. Abrir uma agência e um ATM; confirmar NUI, animação e slot.
4. Abrir o aplicativo bancário; confirmar saldo, conta pública, extrato, cartões e favoritos.
5. Com dois jogadores online, transferir um valor pequeno pelo telefone e confirmar comprovante,
   uma única movimentação e as duas notificações.
6. Fechar/reabrir o telefone e confirmar que o restante dos aplicativos continua funcional.

Resultado esperado:

- todos os resources ficam ready sem runner ou fault injection;
- banco físico e aplicativo preservam os comportamentos já aprovados;
- saldo/extrato/comprovante correspondem à única transferência;
- notificações não duplicam;
- nenhuma falha nova aparece no console.

Resultado real: **APROVADO** — após receber o roteiro único do smoke, o usuário informou
“certinho”. A confirmação registra o restart limpo, banco físico, aplicativo, transferência,
comprovante e notificações funcionando conforme o resultado esperado.  
Status: **APROVADO**  
Executado por/data: **usuário / 2026-07-20**  
Evidência/observações: **confirmação textual do usuário; não foram fornecidos logs, capturas ou
queries adicionais**.

```text
Limpeza: [R] Aprovada após smoke
Smoke de produção: APROVADO
Fase 6 funcional: [R] Aprovada em runtime
```
