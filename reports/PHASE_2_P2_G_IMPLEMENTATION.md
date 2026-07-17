# Fase 2 — Implementação do Lote P2-G

Data: 2026-07-17  
Estado: **VALIDADO ESTATICAMENTE**

```text
Fase 2: [~] Em implementação
P2-A: [R]
P2-B: [R]
P2-C: [R]
P2-D: [R]
P2-E: [R]
P2-F: [R]
P2-G: [S] Validado estaticamente
P2-H: NÃO IMPLEMENTADO
```

## 1. Diagnóstico

O P2-F já fornecia a transferência server-side segura por `resolutionToken`, mas a NUI física ainda
solicitava server ID e chamava o contrato legado. Não havia consumidor executável externo dos exports
legados `ResolveRecipient` e `Transfer` no workspace.

O P2-G realizou exclusivamente o cutover do ATM/agência para identidade bancária pública. Nenhuma
regra financeira, migration, saldo, ledger, card, phone ou transferência offline foi criada.

## 2. Escopo implementado

- substituição do campo server ID por agência, conta de oito dígitos e DV;
- resolução privada do destinatário pelo contrato real do P2-E;
- confirmação explícita com nome parcial e rota mascarada;
- confirmação financeira pelo contrato real do P2-F;
- comprovante visual com destinatário parcial, rota mascarada, valor e `correlationId` oficial;
- idempotência da NUI vinculada à rota e ao valor, preservando a chave em falha ambígua;
- expiração local do preview conforme TTL retornado pelo servidor;
- remoção dos callbacks/exports executáveis baseados em server ID;
- atualização da documentação de integração e do roadmap.

## 3. Arquivos alterados

| Arquivo | Alteração |
|---|---|
| `server/main.lua` | callback de resolução física e cutover do callback de transferência para P2-F; remoção dos exports legados |
| `server/service.lua` | remoção da resolução/transferência por server ID; promoção dos contratos P2-E/P2-F ao fluxo físico |
| `client/main.lua` | DTOs NUI restritos a rota e token opaco |
| `html/index.html` | campos agência/conta/DV, confirmação e comprovante |
| `html/script.js` | máquina de UI, token, idempotência, confirmação e receipt |
| `html/style.css` | componentes novos usando a paleta e estrutura existentes |
| `INTEGRATION.md` | contrato físico final documentado |
| `BANK_ROADMAP.md` | P2-G marcado `[S]`, sem aprovação runtime |
| `reports/PHASE_2_P2_G_IMPLEMENTATION.md` | este relatório |
| `reports/PHASE_2_P2_G_RUNTIME_CHECKLIST.md` | validação runtime pendente |

## 4. Contratos reais usados

```text
MZBankService.ResolvePublicRecipient(source, route, { token })
MZBankAccountResolution.Resolve(actor, route)
MZBankService.TransferByPublicAccount(source, resolutionToken, amount, context)
MZBankAccountResolution.ValidateResolutionToken(actor, token)
MZBankBridge.TransferBankBetweenPlayers(source, targetCitizenId, amount, metadata)
exports['mz_core']:TransferBankBetweenPlayers(...)
```

O client nunca escolhe `source` ou `citizenid`. O servidor deriva ator, sessão e canal pelo callback e
token físico; o destino interno vem somente da resolução privada e é revalidado antes do core.

## 5. DTOs finais da NUI

Resolução:

```js
{ branch, accountNumber, checkDigit }
```

Resposta mínima usada na confirmação:

```js
{
  resolutionToken,
  expiresIn,
  recipient: { displayName, branch, accountMasked, accountTypeLabel }
}
```

Transferência:

```js
{ resolutionToken, amount, idempotencyKey }
```

O comprovante usa apenas valor, nome parcial, conta mascarada e `correlationId`. Não recebe
`citizenid`, license, source, ID SQL, número completo de cartão ou metadata interna.

## 6. Decisões

- Agência permanece editável, com valor inicial `0001`.
- Conta exige oito dígitos e DV exige um dígito antes da chamada server-side.
- O preview não autoriza a transferência: o token é revalidado e consumido no servidor.
- Cancelar/corrigir descarta o token no client; o token server-side expira e também é limpo com a sessão.
- Em erro ambíguo, a chave de idempotência permanece para permitir recuperação/replay.
- Os exports por server ID foram removidos porque não havia consumidores executáveis e manter dois
  contratos finais criaria ambiguidade.
- Os runners anteriores continuam inertes por padrão e não participam do fluxo P2-G.

## 7. Validações estáticas

- `node --check html/script.js`: aprovado;
- parsing Lua de `server/main.lua`, `server/service.lua` e `client/main.lua`: aprovado;
- busca no código executável por `recipientValue`, `transfer-target`, `ResolveRecipient` e
  `MZBankService.Transfer`: zero ocorrências no fluxo final;
- callback de resolução aceita somente agência/conta/DV;
- callback financeiro aceita somente token/valor/idempotência;
- nenhuma alteração em `mz_core`, `mz_economy`, `mz_phone`, migrations ou schema;
- nenhuma coluna/tabela/saldo/ledger paralelo criado;
- animação ATM, alinhamento, ciclo da sessão e estados amarelo/verde/vermelho não foram alterados;
- depósito, saque, extrato, autenticação e fechamento permaneceram no mesmo contrato.

A tentativa de inspeção visual automatizada pelo navegador local ficou indisponível no ambiente do
Codex. Isso não invalida a sintaxe, mas mantém layout e interação como itens de runtime.

## 8. Riscos e testes pendentes

- conferir legibilidade dos três campos na resolução real do FiveM;
- validar teclado físico, soft keys, cancelamento, expiração e duplo clique;
- confirmar que conta bloqueada/frozen/closed, destino offline e autotransferência são negados;
- conferir replay, saldo/cache/persistência e receipt com `correlationId` real;
- repetir smoke de ATM/agência, animação, slot, depósito, saque e extrato.

Todos estão detalhados em `PHASE_2_P2_G_RUNTIME_CHECKLIST.md`. Nenhum deles foi marcado como
executado ou aprovado.

## 9. Itens explicitamente não implementados

- P2-H e decisão final da Fase 2;
- canal ou aplicativo `phone`;
- transferência offline;
- PIX, QR Code, contas empresariais ou produtos financeiros;
- saldo ou ledger em `mz_bank_accounts`;
- alteração dos serviços financeiros do `mz_core`;
- novo export público de transferência.

## 10. Próximo lote recomendado

Executar integralmente o checklist runtime do P2-G. Com todos os gates registrados, iniciar somente o
P2-H para revisão independente, regressão completa e decisão da Fase 2.

