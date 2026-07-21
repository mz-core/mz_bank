# Fase 6 — Implementação do P6-E

Data: 2026-07-19  
Estado: **P6-E `[S]` validado estaticamente; runtime pendente**  
Fase 6: **`[~]` Em implementação**

## Resultado

O canal `phone` agora cria notificações reais, persistentes e deduplicadas para as duas pontas de
uma transferência confirmada: `-R$valor` para o remetente e `+R$valor` para o destinatário. O
saldo, a atomicidade, o ledger, a outbox e o `correlationId` continuam exclusivamente nos serviços
financeiros oficiais do `mz_core`.

## Contrato e fluxo

1. `mz_bank` confirma a transferência no `mz_core`.
2. Somente depois do commit, chama o export server-side
   `mz_phone:CreateBankTransferNotifications` com sources, valor e referência oficial.
3. O `mz_phone` aceita exclusivamente `GetInvokingResource() == 'mz_bank'`.
4. Os dois personagens são resolvidos novamente no servidor.
5. Cada aviso é inserido com chave `bank_transfer:<correlationId>:out|in`.
6. A constraint única evita duplicidade; o preview NUI só é emitido quando a linha acabou de ser
   criada.
7. Em replay, uma ponta ausente pode ser recuperada e uma ponta já persistida não se repete.

O resultado da notificação é best-effort e posterior ao commit. Erro SQL, resource parado ou
falha no export gera auditoria, mas não muda a resposta financeira confirmada.

## Schema evoluído

`mz_phone_notifications` recebeu:

- `dedupe_key VARCHAR(180) NULL`;
- `UNIQUE KEY uq_mz_phone_notifications_dedupe (citizenid, dedupe_key)`.

Linhas antigas permanecem válidas porque `NULL` pode se repetir. A preparação é idempotente,
consulta `INFORMATION_SCHEMA` antes de adicionar coluna ou índice e não apaga dados.

O JSON persistido contém somente versão, tipo, direção, valor e `correlationId`. Não contém saldo,
rota, `source`, `citizenid`, license, cartão ou metadata financeira.

## Arquivos alterados

- `mz_phone/server/repository.lua`;
- `mz_phone/server/service.lua`;
- `mz_phone/server/main.lua`;
- `mz_phone/sql/mz_phone.sql`;
- `mz_phone/web/components/notifications.js`;
- `mz_phone/README.md`;
- `mz_bank/server/service.lua`;
- `mz_bank/INTEGRATION.md`;
- `mz_bank/BANK_ROADMAP.md`;
- `mz_phone/docs/MZ_BANK_APP_P6_E_RUNTIME_CHECKLIST.md`;
- este relatório.

## Segurança e invariantes

- não existe evento de rede, callback NUI ou export client-facing para criar notificações;
- o export rejeita qualquer resource diferente de `mz_bank`;
- sources e identidades são validados no `mz_phone` e nunca vêm da NUI;
- somente transferência confirmada no canal `phone` aciona o fluxo;
- o aviso não participa da transação financeira e não escreve saldo;
- a unicidade persistente protege replay, timeout recuperado, concorrência e duplo clique;
- o frontend recebe apenas texto sanitizado de direção/valor;
- ATM, agência, cartão, favoritos e transferência física não foram alterados.

## Validações estáticas

- `luac -p` aprovado para os quatro arquivos Lua alterados;
- `node --check` aprovado para o componente visual de notificações;
- DDL conferido com coluna nullable e índice único composto;
- queries parametrizadas e `INSERT IGNORE` protegido pela constraint real;
- busca confirmou ausência de novos campos de saldo ou ledger;
- busca confirmou ausência de `citizenid`, `source` ou rota no payload client-facing;
- falha do export fica contida por `pcall` depois do commit.

## Runtime pendente

Executar somente o caso consolidado em
`mz_phone/docs/MZ_BANK_APP_P6_E_RUNTIME_CHECKLIST.md`. Não marcar P6-E ou a Fase 6 como `[R]`
antes da confirmação manual no MySQL/FiveM staging.

## Fora do escopo

- transferência offline;
- listagem pública de notificações;
- PIX, QR Code, contas organizacionais ou novos produtos;
- alteração de saldos, ledger ou outbox;
- conclusão integral da Fase 6 antes do runtime e da revisão final.
