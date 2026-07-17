# Fase 2 — Implementação do Lote P2-E

Data: 2026-07-17  
Estado atual: **P2-E `[R]` — APROVADO EM RUNTIME**  
Validação estática deste relatório: **APROVADA**  
Runtime MySQL/FiveM posterior: **12/12 APROVADOS**, conforme `PHASE_2_P2_E_RUNTIME_APPROVAL.md`

## 1. Escopo implementado

O P2-E implementa somente resolução privada de destinatário:

- lookup exato por agência, número de oito dígitos e DV;
- sessão física autenticada continua sendo a origem do ator/canal;
- conta alvo deve permitir recebimento e o titular deve estar online;
- resposta pública mínima, com nome parcial e rota mascarada;
- token opaco CSPRNG de 128 bits, TTL de 60 segundos e vínculo a ator/sessão/canal/alvo;
- revalidação interna do token para o futuro P2-F;
- limites de 5 tentativas/60 segundos por sessão e 20/hora por citizenid;
- cooldown progressivo após três falhas consecutivas;
- auditoria agregada sem token, nome completo ou rota completa;
- cleanup no fechamento/expiração da sessão e disconnect.

Não existe callback NUI, evento de rede ou export para o P2-E.

## 2. Contratos internos

```lua
MZBankAccountResolution.Resolve(actor, route)
MZBankAccountResolution.ValidateResolutionToken(actor, token)
MZBankAccountResolution.InvalidateResolutionToken(actor, token)
MZBankAccountResolution.CleanupSession(source, sessionToken)
MZBankService.ResolvePublicRecipient(source, route, { token = physicalSessionToken })
```

`actor` é montado exclusivamente pelo servidor com `source`, `citizenid`, token e canal da sessão.
O client não fornece citizenid, source alvo, ID SQL, estado, tipo livre ou card UID.

## 3. DTO mínimo

```lua
{
  ok = true,
  found = true,
  resolutionToken = '<opaco>',
  recipient = {
    displayName = 'Joao S.',
    branch = '0001',
    accountMasked = '****5678-7',
    accountTypeLabel = 'Conta pessoal'
  },
  expiresIn = 60
}
```

O DTO não contém citizenid, source/server ID, ID de tabela, nome completo, metadata, saldo ou estado
interno detalhado do destinatário.

## 4. Privacidade e estados

- não existe busca por nome, telefone, prefixo ou listagem;
- formato/DV inválido retorna `recipient_invalid` antes do lookup;
- conta inexistente, `frozen`, `closed` ou titular offline retorna a mesma resposta
  `recipient_unavailable`;
- `active` e `blocked` podem receber conforme a matriz já definida;
- autotransferência retorna `self_transfer` sem criar token;
- o nome de confirmação usa primeiro nome e inicial do sobrenome;
- auditoria recebe somente resultado, canal e rota mascarada.

## 5. Token e revalidação

O token contém 128 bits obtidos por quatro chamadas à primitiva CSPRNG já aprovada. Ele fica somente
na memória do `mz_bank` e é vinculado a:

- source e citizenid do remetente;
- token e canal da sessão;
- ID/citizenid internos do alvo;
- rota normalizada;
- criação e expiração.

Token falso, expirado ou de outro ator/sessão/canal é negado. A revalidação consulta novamente a
rota, estado e presença online. O P2-E não consome o token financeiramente; isso pertence ao P2-F.

## 6. Rate limits

| Limite | Política |
|---|---|
| sessão/canal | 5 tentativas em 60 segundos |
| ator | 20 tentativas em 3600 segundos |
| cooldown | após 3 falhas; 2, 4, 8... até 30 segundos |
| tokens ativos | máximo 20 por source |

Os contadores curtos ficam em memória e reiniciam com o resource. Tentativas e bloqueios são
auditados persistentemente pelo `mz_core`.

## 7. Arquivos alterados

| Arquivo | Alteração |
|---|---|
| `config.lua` | política do P2-E |
| `bridge/server.lua` | contrato real `GetPlayerByCitizenId` para alvo online |
| `server/account_resolution.lua` | resolução, token, limites, auditoria e cleanup |
| `server/service.lua` | adaptação interna à sessão física; transferência atual preservada |
| `server/main.lua` | status explícito do P2-E no startup |
| `fxmanifest.lua` | carregamento server-side do serviço |
| `BANK_ROADMAP.md` | P2-E registrado; estado atualizado posteriormente para `[R]` |

Nenhum schema, migration, saldo, ledger, client Lua, HTML, CSS ou JavaScript bancário foi alterado.

## 8. Contratos reais usados

- `MZBankRepository.getPublicAccountByRoute`;
- `MZBankAccountIdentity.ValidateRoute` e `IsValidStatus`;
- `MZBankAccountService.CanAccountPerform`;
- `mz_core:GetPlayerByCitizenId` via bridge;
- `mz_core:CreateDetailedLog` via bridge;
- CSPRNG aprovado em P2-C;
- sessão física server-side existente no `MZBankService`.

## 9. Validações estáticas

```text
Lua/JavaScript syntax: PASS
valid route/minimal DTO: PASS
active/blocked receive: PASS
missing/frozen/closed/offline equivalence: PASS
self transfer: PASS
token actor/session binding and expiration: PASS
session rate 5/60s: PASS
actor rate 20/h: PASS
progressive cooldown: PASS
session cleanup: PASS
no citizenid/source/account id in DTO: PASS
no callback/event/export: PASS
no balance/ledger/financial operation: PASS
current server-ID transfer unchanged: PASS
```

Harness local: `PASS P2-E harness logs=43 token_ttl=60 session_limit=5 actor_limit=20 pii=false`.

## 10. Riscos e runtime pendente

- confirmar retorno da CSPRNG e latência no artifact real;
- confirmar nomes parciais com dados reais;
- comprovar equivalência pública entre alvos indisponíveis;
- comprovar TTL, vínculo do token e cleanup em restart/disconnect;
- comprovar rate limits e auditoria persistente no MySQL/FiveM;
- repetir smoke test de ATM, agência, saldo, extrato e transferência atual.

## 11. Itens não implementados

- movimentação financeira por conta pública;
- consumo financeiro do token;
- destinatário offline;
- callback/NUI e cutover do campo server ID;
- `phone`, PIX, QR Code, conta organizacional ou saldo paralelo.

## 12. Estado final

```text
Fase 2: [~] Em implementação
P2-A: [R]
P2-B: [R]
P2-C: [R]
P2-D: [R]
P2-E: [R] Aprovado em runtime
P2-F e seguintes: NÃO IMPLEMENTADOS
```

O checklist `PHASE_2_P2_E_RUNTIME_CHECKLIST.md` foi executado e aprovado posteriormente. O próximo
passo permitido é implementar somente o P2-F, sem antecipar P2-G ou lotes seguintes.
