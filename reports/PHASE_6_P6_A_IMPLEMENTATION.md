# Fase 6 — Implementação do P6-A

Data: 2026-07-19  
Estado: **P6-A `[S]` validado estaticamente; runtime pendente**  
Fase 6: **`[~]` Em implementação**

## Resultado

Foi entregue a primeira fatia real do aplicativo bancário no `mz_phone`: sessão bancária própria
do canal `phone` e consultas de saldo, identidade bancária pública, extrato e cartões. O app não
usa dados fictícios e falha fechado quando o banco, personagem, aparelho ou sessão não estão
disponíveis.

## Escopo exato

- sessão `phone` criada exclusivamente por chamada server-to-server do `mz_phone`;
- vínculo com `source`, `citizenid` resolvido no servidor e número do aparelho resolvido pelo
  serviço real do telefone;
- token opaco guardado somente no servidor do `mz_phone`;
- expiração, renovação por uso, encerramento ao sair do app/telefone, disconnect e resource stop;
- overview real usando saldo `bank` oficial do `mz_core`;
- identidade pública oficial de `mz_bank_accounts`, sem saldo;
- extrato real via contrato do `mz_economy` já encapsulado pelo `mz_bank`;
- listagem sanitizada de cartões;
- estados visuais reais de loading, erro, vazio e conteúdo;
- formatação uniforme do extrato: `+R$10` e `-R$10`.

## Arquivos alterados

| Arquivo | Alteração |
|---|---|
| `mz_bank/config.lua` | política da sessão phone read-only |
| `mz_bank/fxmanifest.lua` | ordem de carregamento do serviço phone |
| `mz_bank/server/service.lua` | readiness interno consultável pelo serviço phone |
| `mz_bank/server/phone_service.lua` | sessão e consultas exclusivas do canal phone |
| `mz_bank/server/api.lua` | roteamento da API v1 por canal e bloqueio de comandos no P6-A |
| `mz_bank/server/main.lua` | exports server-to-server de abertura/fechamento da sessão phone |
| `mz_phone/fxmanifest.lua` | carregamento da integração sem dependência rígida de `mz_bank` |
| `mz_phone/shared/config.lua` | rate limit do domínio bancário |
| `mz_phone/server/bank.lua` | adaptador seguro entre telefone e API oficial |
| `mz_phone/server/callbacks.lua` | evento allowlisted para solicitações bancárias |
| `mz_phone/client/nui.lua` | ponte NUI sem token, canal ou identidade interna |
| `mz_phone/client/phone.lua` | encerramento da sessão ao fechar o aparelho |
| `mz_phone/web/api.js` | request/response bancário com timeout |
| `mz_phone/web/app.js` | estado real de cartões |
| `mz_phone/web/apps/bank.js` | app real somente leitura |
| `mz_phone/web/css/apps/bank.css` | visual compatível com o padrão atual do telefone |

## Contratos reais utilizados

```text
mz_phone server -> mz_bank:OpenPhoneSession
mz_phone server -> mz_bank:GetAccountOverview
mz_phone server -> mz_bank:GetAccountStatement
mz_phone server -> mz_bank:GetCards
mz_phone server -> mz_bank:GetChannelCapabilities
mz_phone server -> mz_bank:ClosePhoneSession

mz_bank -> MZBankBridge.ResolvePlayer
mz_bank -> MZBankBridge.GetMoney
mz_bank -> MZBankBridge.GetStatement
mz_bank -> MZBankAccountService.EnsurePersonalAccount
mz_bank -> MZBankRepository.listCards
```

O `mz_phone` não chama `mz_core`, `mz_economy`, repository ou SQL para obter dados bancários.

## Segurança e DTOs

- a NUI envia apenas `requestId`, ação allowlisted e filtros não sensíveis;
- a NUI não envia `source`, `citizenid`, canal, token ou identificador do aparelho;
- o token e o device binding ficam nos servidores `mz_phone`/`mz_bank`;
- a API determina `channel=phone` pela sessão, não pelo client;
- `citizenid`, `card_uid`, IDs SQL, metadata, licença e segredos são removidos;
- cartões enviados ao frontend contêm somente `last4`, estado e timestamps públicos;
- requests repetidos têm rate limit e timeout;
- troca de personagem/aparelho invalida a sessão;
- saque, depósito, resolução de destinatário, transferência, resultado financeiro, emissão,
  bloqueio e substituição retornam `channel_forbidden` para o canal phone neste lote.

## Ausências confirmadas

- nenhuma coluna, tabela ou cache de saldo foi criado;
- nenhum ledger paralelo foi criado;
- nenhuma migration foi criada;
- nenhuma transferência offline foi implementada;
- nenhum server ID é usado como conta;
- nenhum fluxo físico de ATM/agência foi alterado;
- nenhum dado bancário demonstrativo permanece no app.

## Validações estáticas

- `node --check mz_phone/web/api.js`: aprovado;
- `node --check mz_phone/web/apps/bank.js`: aprovado;
- `luac -p` nos arquivos Lua alterados compatíveis com Lua padrão: aprovado; `mz_bank/config.lua`
  usa hashes com crase próprios do runtime FiveM e teve a nova tabela conferida estruturalmente;
- busca por `citizenid`, token, `cardUid`, `card_uid`, license e `payload.channel` nos arquivos
  client/NUI bancários: zero ocorrências;
- busca por `mz_core`, `mz_economy`, `MySQL` e SQL direto no adaptador phone: zero ocorrências;
- ordem de manifests confirmada: `phone_service.lua` antes de `api.lua` e `bank.lua` antes de
  callbacks;
- `mz_phone` trata `mz_bank` como integração opcional em runtime, permitindo fail-closed sem
  encerrar o restante do telefone; a ordem normal de startup continua sendo controlada pela
  configuração de resources.

## Riscos e runtime pendente

- o número do telefone é o identificador lógico do aparelho porque `RequireItem=false` e o projeto
  ainda não possui contrato de instância física de celular; se esse contrato surgir, o binding deve
  migrar para o UID da instância;
- indisponibilidade do `mz_economy` degrada somente o extrato, não inventa movimentações;
- é necessário confirmar no FiveM o layout, os temas, a expiração/fechamento e a não regressão do
  ATM/agência.

## Itens explicitamente não implementados

- transferência pelo telefone;
- confirmação de destinatário e comprovante;
- favoritos;
- bloqueio de cartão pelo app;
- notificações financeiras;
- saque ou depósito;
- emissão ou segunda via de cartão.

## Próximo lote recomendado

Após aprovação runtime do P6-A, implementar P6-B com resolução pública, confirmação e
transferência idempotente pelo telefone, reutilizando os contratos P2-E/P2-F e a API v1.
