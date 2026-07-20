# Fase 4 — Implementação da API bancária compartilhada

Data: 2026-07-19  
Estado: **VALIDADA ESTATICAMENTE; RUNTIME PENDENTE**

```text
Fase 4: [~] Em implementação
API v1: [S] Validada estaticamente
Runtime: NÃO EXECUTADO
```

## Resultado

Foi criada uma única fachada server-to-server, `MZBankAPI`, para consultas e comandos bancários.
Os callbacks físicos de overview, saque, depósito, resolução e transferência passaram a usar essa
fachada. A API não cria saldo, ledger ou canal financeiro paralelo: operações continuam no
`mz_core`, extrato no `mz_economy` e identidade pública em `mz_bank_accounts`.

O `mz_phone` foi autorizado apenas como resource chamador futuro. Nenhuma capability `phone`,
callback de telefone ou operação pelo aparelho foi criada; sem sessão válida, a API nega o acesso.

## Arquivos alterados

- `mz_bank/config.lua`: versão 1, allowlist e mensagens estáveis.
- `mz_bank/fxmanifest.lua`: carrega a fachada antes de `server/main.lua`.
- `mz_bank/server/api.lua`: API compartilhada, DTOs e referências opacas de cartão.
- `mz_bank/server/service.lua`: contratos internos de conta pública, capacidades e emissão.
- `mz_bank/server/main.lua`: callbacks físicos e exports oficiais passam pela API.
- `mz_bank/server/p4_runtime_runner.lua`: runner temporário console-only, com fixtures em memória.
- `mz_bank/bridge/server.lua`: ponte read-only para resultado idempotente.
- `mz_core/server/accounts/service.lua`: consulta autenticada do resultado persistido.
- `mz_core/server/accounts/exports.lua`: export real `GetOperationResult` com escopo do invocador.
- `mz_bank/INTEGRATION.md`: contrato público v1 documentado.

## Contratos v1

- `GetAccountOverview`
- `GetAccountStatement` (`GetStatement` é alias legado)
- `GetPublicAccount`
- `ResolveTransferRecipient`
- `Transfer`
- `Withdraw` e `Deposit` para o adaptador físico
- `GetCards`
- `IssueCard`
- `BlockCard`
- `ReplaceCard` (`RequestReplacementCard` é alias legado)
- `GetChannelCapabilities`
- `GetOperationResult`
- `GetAPIVersion`

Chamadores externos precisam estar em `Config.SharedAPI.AllowedResources` e enviar
`context.apiVersion = 1`. Versão incorreta falha com `api_version_unsupported`, ausência de versão
com `api_version_required` e resource não autorizado com `api_forbidden`.

## Segurança e DTOs

- o canal efetivo vem exclusivamente da sessão validada por `MZBankService`;
- a matriz fixa permite `mz_bank -> atm/branch` e reserva `mz_phone -> phone`; por isso o telefone
  não consegue reutilizar nem mesmo um token físico válido;
- nenhum parâmetro público seleciona `phone`, `admin`, `atm` ou `branch`;
- `source` é o jogador autenticado pelo runtime e não há `citizenid` no contrato;
- cartão público usa `cardRef` opaco vinculado ao source/token;
- `card_uid`, ID SQL, titular, license, segredo e metadata interna não saem pela API;
- resultado recuperado é reduzido a operação, confirmação, correlação, replay e taxa;
- `GetOperationResult` é read-only e usa o escopo real do invocador no `mz_core`;
- dinheiro físico continua proibido fora de sessão ATM/agência válida.

## Decisões

1. A API foi adicionada como fachada, sem duplicar queries ou regras financeiras.
2. O serviço físico continua autoridade de sessão, distância, ped, cartão e canal.
3. `mz_phone` pode consumir os mesmos contratos futuramente, mas a capability phone pertence à
   Fase 6 e não foi antecipada.
4. O export de cartões foi endurecido: a listagem oficial não devolve mais `card_uid`.
5. A recuperação persistente foi implementada no domínio que possui a idempotência, `mz_core`, e
   sanitizada pelo banco antes de retornar.

## Validação estática

- sintaxe Lua aprovada nos arquivos alterados; `config.lua` usa hashes com crase do runtime FiveM,
  sintaxe que o `luac` genérico não reconhece;
- nenhum evento de rede, callback NUI ou export foi adicionado em `server/api.lua`;
- nenhuma escrita em saldo ou ledger foi adicionada ao `mz_bank`;
- nenhuma query foi duplicada na fachada;
- callbacks físicos não enviam canal nem `citizenid` à API;
- exports usados em `mz_core`, `mz_economy` e `mz_inventory` foram confirmados no código real.

## Riscos e runtime pendente

- consumidores antigos de `GetCards` devem migrar de `card_uid` para `cardRef`;
- restart de `mz_bank` invalida corretamente referências opacas de cartão;
- o smoke físico foi aprovado pelo usuário; versão/allowlist, isolamento de canal, DTOs e adapter
  de replay permanecem no runner controlado;
- o runner P4 é desativado por padrão e não possui evento de rede, callback NUI ou export;
- a integração real do telefone continua pendente e não é aprovada por este lote.

Próximo passo: executar `PHASE_4_RUNTIME_CHECKLIST.md`; após aprovação, fechar a Fase 4 e iniciar
somente o gate mínimo de cartões exigido pelo MVP antes da Fase 6.
