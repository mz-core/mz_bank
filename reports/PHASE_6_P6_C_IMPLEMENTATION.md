# Fase 6 — Implementação do P6-C

Data: 2026-07-19  
Estado: **P6-C `[S]` validado estaticamente; runtime pendente**  
Fase 6: **`[~]` Em implementação**

## Resultado

O aplicativo MZ Bank passou a oferecer consulta sanitizada e bloqueio confirmado dos cartões do
próprio personagem. O lote reutiliza a API v1, a sessão `phone` e o gate mínimo de cartões já
aprovado na Fase 5. Nenhuma emissão, substituição ou operação financeira foi adicionada.

## Fluxo implementado

```text
mz_bank lista cartões do titular autenticado
  -> API troca card_uid por cardRef opaco vinculado a source + token
  -> mz_phone envia à NUI somente DTO público
  -> jogador escolhe cartão active e confirma o bloqueio
  -> NUI devolve somente cardRef
  -> mz_phone revalida sessão/aparelho/personagem
  -> mz_bank resolve cardRef no servidor
  -> repository bloqueia somente cartão active do mesmo citizenid
  -> sessões físicas ligadas à credencial são invalidadas
  -> app recarrega a lista e mostra o estado blocked
```

## Arquivos alterados

| Arquivo | Alteração |
|---|---|
| `mz_bank/server/service.lua` | executor interno comum de bloqueio para identidade e canal já validados |
| `mz_bank/server/phone_service.lua` | capability e comando de bloqueio na sessão `phone` |
| `mz_bank/server/api.lua` | resolução do `cardRef` e roteamento para o serviço do canal |
| `mz_bank/config.lua` | documentação atualizada das capacidades do telefone |
| `mz_bank/INTEGRATION.md` | contrato de cartões por agência/telefone |
| `mz_phone/server/bank.lua` | adaptador seguro e ação `block_card` |
| `mz_phone/web/app.js` | estado transiente da confirmação |
| `mz_phone/web/apps/bank.js` | botão, confirmação, erro e retorno visual |
| `mz_phone/web/css/apps/bank.css` | componentes visuais seguindo o padrão atual |
| `mz_bank/BANK_ROADMAP.md` | estado estático do P6-C |

## Contratos reais reutilizados

- `MZBankRepository.listCards(citizenid)`;
- `MZBankRepository.blockCard(citizenid, cardUid)`;
- `MZBankAPI.GetCards` e `MZBankAPI.BlockCard`;
- sessão `MZBankPhoneService` vinculada a source, personagem e aparelho;
- invalidação já existente das sessões físicas que usam a credencial bloqueada;
- auditoria `bank.card.blocked` pelo bridge oficial.

## Segurança e invariantes

- a NUI envia apenas `cardRef`; não envia `source`, `citizenid`, canal ou `card_uid`;
- o `cardRef` é opaco, temporário e válido somente para a mesma fonte e token de sessão;
- o servidor resolve novamente o personagem e exige que o cartão pertença ao titular;
- somente a transição `active -> blocked` é aceita;
- repetição ou referência antiga termina em `card_invalid`, sem segunda alteração;
- uma sessão não executa bloqueio e transferência simultaneamente;
- o bloqueio não altera saldo, outbox financeira ou ledger;
- `mz_phone` não acessa MySQL, `mz_core`, `mz_economy` ou inventário diretamente;
- emissão, desbloqueio e segunda via continuam indisponíveis no telefone;
- ATM e agência preservam seus contratos atuais.

## Validações estáticas

- sintaxe Lua dos quatro arquivos server-side envolvidos: aprovada com `luac -p`;
- sintaxe JavaScript de `app.js` e `apps/bank.js`: aprovada com `node --check`;
- nenhuma query SQL ou chamada direta a domínio financeiro foi adicionada ao `mz_phone`;
- nenhum `card_uid`, ID SQL, metadata, PIN ou identificador do titular foi incluído no DTO da NUI;
- `IssueCard` e `ReplaceCard` continuam negados para o chamador `mz_phone`;
- nenhuma migration ou tabela foi criada;
- nenhum saldo ou ledger paralelo foi criado.

## Riscos e runtime pendente

- confirmar no FiveM que um cartão ativo muda visualmente e no banco para `blocked`;
- confirmar que uma sessão ATM autenticada com esse cartão deixa de operar imediatamente;
- confirmar que duplo clique, `cardRef` antigo e referência de outro jogador não alteram dados;
- confirmar que saldo, transferência, NUI física e restante do telefone não sofreram regressão.

Roteiro: `mz_phone/docs/MZ_BANK_APP_P6_C_RUNTIME_CHECKLIST.md`.

## Itens explicitamente não implementados

- emissão, desbloqueio ou segunda via pelo telefone;
- remoção do item físico;
- PIN;
- favoritos, notificações push, PIX, QR Code ou transferência offline;
- conclusão integral das Fases 5 ou 6.

## Próximo passo

Executar somente o checklist runtime do P6-C. Não marcar `[R]` antes da confirmação manual no
FiveM.
