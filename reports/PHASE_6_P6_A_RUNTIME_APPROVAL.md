# Fase 6 — Aprovação runtime do P6-A

Data: 2026-07-19  
Ambiente: FiveM staging  
Origem da evidência: resultados fornecidos pelo usuário após execução manual

## Resultado consolidado

| Métrica | Resultado |
|---|---:|
| Casos definidos | 2 |
| Executados | 2 |
| Aprovados | 2 |
| Falhas | 0 |
| Bloqueados | 0 |

## Evidências registradas

- o aplicativo abriu corretamente no shell real do `mz_phone`;
- saldo, conta pública, extrato e cartões reais foram visualizados;
- com `mz_bank` parado, o telefone permaneceu funcional;
- somente o aplicativo bancário apresentou serviço indisponível;
- não foi informado uso de dados fictícios ou dados antigos no estado indisponível;
- a dependência rígida do manifest foi removida e o teste foi repetido com o comportamento esperado;
- nenhuma divergência ou falha pendente do P6-A foi informada.

As evidências textuais preservadas são os relatos do usuário “abriu certinho consegui ver tudo” e
“agora sim o celular sem o bank fica com serviço indisponivel”. Não foram inventados logs, capturas
ou resultados SQL adicionais.

## Invariantes preservadas

- o saldo continua exclusivamente no `mz_core`;
- `mz_bank_accounts` continua sem saldo;
- o `mz_phone` consome apenas a API oficial do `mz_bank`;
- token, `citizenid`, device binding e IDs internos não são enviados à NUI;
- saque e depósito permanecem proibidos no telefone;
- transferência e bloqueio de cartão não foram antecipados no P6-A;
- ATM, agência e seus comportamentos físicos permanecem cobertos pelas aprovações anteriores.

## Limitações

- o binding lógico do aparelho usa o número de telefone enquanto não existe UID de instância física;
- esta aprovação não cobre transferência, comprovante, favoritos, bloqueio de cartão ou notificações;
- a Fase 6 completa permanece em implementação.

## Decisão final

```text
P6-A: [R] Aprovado em runtime
Fase 6: [~] Em implementação
Falhas pendentes conhecidas do P6-A: 0
```

Próximo lote: P6-B — resolução, confirmação e transferência idempotente pelo aplicativo.
