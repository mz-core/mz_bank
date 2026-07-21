# Fase 6 — Implementação do P6-B

Data: 2026-07-19  
Estado: **P6-B `[S]` validado estaticamente; runtime pendente**  
Fase 6: **`[~]` Em implementação**

## Resultado

O aplicativo MZ Bank passou a permitir transferência online por identidade bancária pública. O
fluxo reutiliza integralmente resolução P2-E, transferência P2-F, API v1 da Fase 4, idempotência,
locks, saldo e ledger oficiais do `mz_core`.

## Fluxo implementado

```text
NUI informa agência + conta + dígito + valor
  -> mz_phone server resolve a sessão/aparelho/personagem
  -> mz_bank resolve a conta pública e o titular online
  -> NUI recebe somente nome parcial e rota mascarada
  -> confirmação explícita
  -> mz_phone server usa resolutionToken e idempotencyKey privados
  -> mz_bank revalida origem, alvo, estado e sessão
  -> mz_core executa a transferência atômica
  -> comprovante recebe correlationId oficial
  -> overview/extrato são atualizados sem alterar o resultado financeiro
```

## Arquivos alterados

| Arquivo | Alteração |
|---|---|
| `mz_bank/config.lua` | limite inteiro do canal `phone`, somente para transferência |
| `mz_bank/server/account_resolution.lua` | ator interno P2-E passa a aceitar sessão `phone` validada |
| `mz_bank/server/service.lua` | executor financeiro comum para sessão já validada e refresh phone |
| `mz_bank/server/phone_service.lua` | resolução, concorrência e transferência na sessão phone |
| `mz_bank/server/api.lua` | roteamento de resolve/transfer/resultado para o canal phone |
| `mz_phone/server/bank.lua` | intents privados, confirmação, idempotência, recuperação e recibo |
| `mz_phone/web/app.js` | estado transiente do fluxo de transferência |
| `mz_phone/web/apps/bank.js` | formulário, confirmação e comprovante reais |
| `mz_phone/web/css/apps/bank.css` | componentes visuais do fluxo seguindo o padrão do telefone |
| `mz_bank/BANK_ROADMAP.md` | estado estático do P6-B |

## Contratos reais reutilizados

- `MZBankAccountResolution.Resolve`;
- `MZBankAccountResolution.ValidateResolutionToken`;
- `MZBankAccountResolution.InvalidateResolutionToken`;
- `MZBankAccountService.CanAccountPerform`;
- `MZBankBridge.TransferBankBetweenPlayers`;
- `exports['mz_core']:TransferBankBetweenPlayers`;
- `exports['mz_core']:GetOperationResult` através da API oficial;
- persistência de idempotência em `mz_account_idempotency`;
- ledger/outbox/correlationId oficiais já aprovados nas Fases 2 e 3.

## Segurança

- o client nunca envia `source`, `citizenid`, canal ou server ID;
- o destinatário é resolvido no servidor a partir da rota pública completa;
- `resolutionToken` nunca é enviado à NUI;
- `idempotencyKey` é gerada e mantida no servidor do `mz_phone`;
- uma referência opaca de confirmação é vinculada ao source e à sessão;
- destinatário e valor inteiro são fixados no intent server-side antes da tela de confirmação;
- o token de resolução expira em 60 segundos e é revalidado antes do débito;
- destinatário offline, indisponível, bloqueado ou o próprio remetente é negado;
- o valor precisa chegar ao banco como inteiro positivo e respeitar o limite do canal;
- a sessão bloqueia operação concorrente;
- duplo clique reutiliza o mesmo intent/chave e não movimenta saldo novamente;
- erros ambíguos consultam `GetOperationResult` antes de declarar falha;
- resultado concluído fica em cache curto server-side para repetição segura da resposta;
- a NUI recebe somente nome parcial, rota mascarada, valor, taxa e correlationId.

## Invariantes financeiras

- nenhum saldo ou ledger foi criado no `mz_phone` ou `mz_bank_accounts`;
- saldo permanece em `player.money.bank`/`mz_player_accounts` via `mz_core`;
- taxa continua definida por `Config.TransferFeePercent`, com arredondamento `floor`;
- destinatário precisa estar online; nenhuma transferência offline foi criada;
- falha no refresh posterior não reverte nem transforma sucesso financeiro em falha;
- saque e depósito continuam proibidos no telefone.

## Validações estáticas

- sintaxe Lua dos arquivos server-side alterados: aprovada com `luac -p`;
- sintaxe JavaScript de `app.js` e `apps/bank.js`: aprovada com `node --check`;
- zero chamada direta do `mz_phone` ao `mz_core`, `mz_economy`, MySQL ou SQL;
- zero `citizenid`, token, `resolutionToken`, `idempotencyKey`, card UID ou server ID nos contratos
  client/NUI;
- resolução e transferência utilizam somente exports reais da API v1;
- `phone` possui apenas limite de transferência, sem limite de saque/depósito;
- fluxo físico não foi substituído e continua usando sua própria sessão.

## Não implementado

- transferência offline;
- PIX ou QR Code;
- favoritos;
- agendamento;
- contas empresariais;
- saque ou depósito pelo telefone;
- bloqueio de cartão pelo app (próximo lote separado);
- notificações push persistentes.

## Runtime pendente

Executar o roteiro em `mz_phone/docs/MZ_BANK_APP_P6_B_RUNTIME_CHECKLIST.md`. Não marcar P6-B como
`[R]` antes da transferência real, comprovante, extrato e proteção contra repetição serem
confirmados no FiveM.
