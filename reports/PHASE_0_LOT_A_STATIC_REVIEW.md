# MZ Bank — Revisão estática independente do Lote A

Data: 2026-07-15  
Escopo: `B0-01`, `B0-02`, `B0-03`, `B0-04` e `B0-09`.

## Decisão

O Lote A está **APROVADO ESTATICAMENTE após três correções restritas ao próprio lote**. Não foi encontrado bloqueio estático remanescente nos cenários solicitados.

Esta decisão não aprova runtime, não valida a Fase 0 e não marca a Fase 0 como `[S]`. Coordenadas no mapa real, server natives/OneSync, inventário ativo, movimentações e comportamento visual continuam **PENDENTES DE RUNTIME**.

## Método independente

A revisão foi refeita a partir dos arquivos atuais de código, sem aceitar os relatórios anteriores como evidência. Foram usados:

1. leitura das superfícies reais em `client/main.lua`, `client/interact.lua`, `server/main.lua`, `server/service.lua`, `bridge/server.lua`, `config.lua` e NUI;
2. busca negativa por canais, identificadores, tipos de destinatário e callbacks antigos;
3. carregamento do `server/service.lua` real em harness Lua com player, ped, inventário, credencial, relógio e repository controlados;
4. carregamento do `server/main.lua` real com captura dos callbacks registrados e argumentos efetivamente encaminhados;
5. asserções estruturais da animação, alinhamento, fechamento da NUI e estados do slot;
6. parsing de todos os arquivos Lua e JavaScript do resource.

O harness não simula ou aprova o engine FiveM. Ele exercita o código Lua real com dependências determinísticas para verificar decisões e DTOs.

## Defeitos encontrados e corrigidos

### A-REV-01 — janela inicial sem comparação de distância

- **Classificação:** CORRIGIDO.
- **Arquivo:** `server/service.lua`, função `validateSession`.
- **Falha reproduzida:** depois de abrir e autenticar junto ao ATM, mover a posição controlada para 100 metros e chamar overview dentro do intervalo inicial retornava sucesso.
- **Causa:** `INITIAL_POSITION_GRACE_MS` ignorava a comparação de distância durante os primeiros dois segundos, embora abertura e estado físico fossem válidos.
- **Correção:** a distância da posição server-side para `session.coords` agora é comparada em toda validação que possui ped válido, inclusive imediatamente após a abertura. A tolerância prevista para ped temporariamente indisponível foi preservada.
- **Regressão:** o mesmo ataque retorna `too_far` e elimina a sessão.

### A-REV-02 — identificador interno no extrato da NUI

- **Classificação:** CORRIGIDO.
- **Arquivo:** `server/service.lua`, função `normalizeStatement`.
- **Falha reproduzida:** `transaction_id` do ledger era copiado para `statement[].id`, embora a NUI não o utilizasse.
- **Correção:** o campo foi removido do DTO normalizado. Tipo, descrição, valor, saldo posterior e data foram preservados.
- **Regressão:** resposta de overview com linha contendo `transaction_id=991` não possui `statement[].id`.

### A-REV-03 — slot permanecia verde após invalidação física do cartão

- **Classificação:** CORRIGIDO.
- **Arquivos:** `client/main.lua` e `html/script.js`.
- **Falha:** a revalidação server-side negava item removido ou cartão bloqueado/revogado, mas uma sessão anteriormente autenticada podia manter o slot visual verde até outra ação/fechamento.
- **Correção:** erros de revalidação em sessão já autenticada enviam `cardRejected`, mudam o slot para vermelho e fecham a sessão/NUI após 900 ms. Recusa durante a autenticação inicial mantém o comportamento existente de vermelho e retorno para amarelo.
- **Preservação:** não houve alteração de layout, cenário ATM, alinhamento, cores CSS ou fluxo de retirada voluntária.

O valor mock de conta usado somente no modo browser também foi trocado por `Conta corrente`, eliminando um exemplo visual de formato de identificador. Isso não altera o payload do FiveM.

## Resultados por cenário solicitado

| Cenário | Classificação | Evidência estática |
|---|---|---|
| `channel` adulterado após abertura | APROVADO ESTATICAMENTE | overview e operações usam token; `context.channel` extra é ignorado; permissões vêm de `session.channel` |
| callback físico tentando `phone` | APROVADO ESTATICAMENTE | `CHANNEL_PERMISSIONS` contém somente `atm`/`branch`; abertura `phone` retorna `channel_forbidden`; nenhum `phone` ocorre no código Lua/JS |
| token falso | APROVADO ESTATICAMENTE | `validateSession` exige igualdade com `Sessions[source].token`; harness retornou `invalid_session` |
| token expirado | APROVADO ESTATICAMENTE | expiração remove a sessão e retorna `session_expired`; relógio controlado confirmou o caminho |
| token de outro jogador | APROVADO ESTATICAMENTE | sessões são indexadas pelo `source` obtido do callback; reutilização por outro source retornou `invalid_session` |
| coordenada arbitrária | APROVADO ESTATICAMENTE | `cloneCoords` apenas normaliza; agência cruza `Config.Branches` e ATM passa obrigatoriamente por `resolveKnownAtm` |
| ATM fora da allowlist | APROVADO ESTATICAMENTE | ponto desconhecido retorna `atm_invalid`; harness negou coordenadas fora do catálogo |
| distância | CORRIGIDO | bypass inicial removido; posição distante é negada desde a primeira validação após abertura |
| morte | APROVADO ESTATICAMENTE | `GetEntityHealth <= 0` retorna `player_dead` e elimina a sessão |
| veículo | APROVADO ESTATICAMENTE | `GetVehiclePedIsIn ~= 0` retorna `vehicle_forbidden` e elimina a sessão |
| ped | APROVADO ESTATICAMENTE | existência/coords/health/vehicle são lidos no servidor; ped inválido depois da tolerância retorna `invalid_ped` |
| personagem | APROVADO ESTATICAMENTE | citizenid atual precisa coincidir com o citizenid vinculado à sessão; troca retorna `player_not_loaded` e elimina a sessão |
| cartão bloqueado | APROVADO ESTATICAMENTE | credencial com status `blocked` retorna `card_blocked`; bloqueio chama `invalidateCardSessions` |
| cartão revogado | APROVADO ESTATICAMENTE | qualquer status diferente de `active` é recusado e a sessão é removida |
| cartão substituído | APROVADO ESTATICAMENTE | sessão continua presa ao `session.cardUid`; novo item não substitui implicitamente a credencial autenticada; credenciais antigas são revogadas |
| item removido | APROVADO ESTATICAMENTE | ausência do mesmo `cardUid` no inventário retorna `card_not_found` e remove a sessão |
| `source`/`citizenid` enviados pelo client | APROVADO ESTATICAMENTE | `source` vem do `ox_lib`; callback de transferência reconstrói o DTO e não lê `payload.source`/`payload.citizenid` |
| `recipientType` arbitrário | APROVADO ESTATICAMENTE | campo não existe no código atual e é descartado pelo callback; resolvedor aceita somente server ID inteiro/online |
| vazamento de identificadores internos | CORRIGIDO | token é opaco; conta é genérica; resolução retorna só nome; `transaction_id` foi removido do extrato da NUI |
| disconnect | APROVADO ESTATICAMENTE | `playerDropped` chama `CleanupSource`, removendo sessão e rate limits; harness confirmou token inválido depois da limpeza |
| resource stop | APROVADO ESTATICAMENTE | servidor percorre `GetPlayers()` e limpa fontes; client limpa tarefas, foco e NUI; harness confirmou o handler server-side |
| animação ATM e alinhamento | APROVADO ESTATICAMENTE | permanecem `PROP_HUMAN_ATM`, `TaskTurnPedToFaceEntity`, fallback por coordenada, `TaskStartScenarioInPlace` e `ClearPedTasks` |
| NUI e slot | CORRIGIDO | HTML/CSS preservados; amarelo=`waiting`, verde=`inserted`, vermelho=`ejecting/error`; rejeição server-side agora alcança `error` |

## Evidência dos testes automatizados

### Harness do serviço — diagnóstico

Antes da correção:

- 21 verificações aprovadas;
- 2 falhas reproduzidas: distância imediata e identificador do extrato.

Depois da correção:

- 21/21 verificações aprovadas;
- exit code `0`.

O conjunto pós-correção cobriu abertura/autenticação válida, token opaco, conta genérica, ausência de ID no extrato, token falso/de outro jogador/expirado, canal injetado, phone, coordenadas, allowlist, distância imediata, morte, veículo, ped, personagem, cartão bloqueado/revogado/substituído, item removido e cleanup.

### Harness dos callbacks públicos

- 15/15 verificações aprovadas;
- foram encontrados somente os seis callbacks atuais: `openSession`, `authenticate`, `overview`, `withdraw`, `deposit` e `transfer`;
- payload malicioso com `recipientType`, `source`, `citizenid`, `channel` e `targetId` resultou no DTO interno contendo somente `value=recipientValue`;
- overview ignorou contexto extra;
- evento de fechamento usou o `source` do evento;
- handlers de disconnect/resource stop executaram cleanup;
- exit code `0`.

### Asserções de animação/NUI

- 12/12 invariantes aprovadas;
- cenário, alinhamento por entidade/coordenada, início e limpeza da animação presentes;
- quatro estados do slot presentes;
- CSS preserva amarelo, verde e vermelho;
- rejeição server-side alcança o estado vermelho;
- NUI não referencia `transaction.id`/`transaction_id`;
- mock usa conta genérica.

### Sintaxe

- 9/9 arquivos Lua passaram em `luac -p`;
- literais hash em backticks do FiveM foram normalizados somente no stream enviado ao parser Lua de estoque;
- 1/1 arquivo JavaScript passou em `node --check`;
- exit code `0`.

## Buscas negativas

No código Lua/JS atual:

- `phone`: 0 ocorrências;
- `recipientType`: 0 ocorrências;
- `payload.source`: 0 ocorrências;
- `payload.citizenid`: 0 ocorrências;
- `GetSourceByCitizenId`: 0 ocorrências;
- `accountMask`: 0 ocorrências;
- `transaction_id` e `row.id`: 0 ocorrências;
- callbacks antigos além dos seis atuais: 0.

`payload.channel` possui somente duas ocorrências em `server/service.lua`: leitura na tentativa de abrir a sessão e auditoria da tentativa negada. Ele não é usado por overview, extrato ou movimentações, e valores diferentes de `atm`/`branch` terminam em `channel_forbidden`.

## Arquivos alterados nesta revisão

- `mz_bank/server/service.lua`: distância sem bypass inicial e DTO de extrato sem ID interno;
- `mz_bank/client/main.lua`: estado autenticado e sinalização de cartão invalidado;
- `mz_bank/html/script.js`: tratamento visual `cardRejected` e conta mock genérica;
- `mz_bank/reports/PHASE_0_LOT_A_STATIC_REVIEW.md`: este relatório.

Nenhuma funcionalidade de phone, PIX, conta pública, destinatário offline, outbox ou conta empresarial foi adicionada. Os serviços financeiros do `mz_core` não foram alterados.

## Pendente de runtime

Os itens abaixo são **PENDENTES DE RUNTIME**, não bloqueios estáticos:

1. confirmar os 112 pontos do catálogo no build/mapa/MLO efetivamente usado;
2. confirmar atualização e disponibilidade de ped, coordenadas, health e veículo no OneSync real, inclusive após spawn e troca de personagem;
3. testar a tolerância de ped inválido sem aceitar operação depois do prazo;
4. confirmar que o inventário ativo reflete remoção, bloqueio, revogação e substituição imediatamente;
5. executar adulterações reais dos callbacks e observar console/logs;
6. validar saldo/cache/persistência/extrato em saque, depósito e transferência;
7. observar alinhamento, início/reinício/fim da animação, foco e fechamento da NUI;
8. observar amarelo ao abrir, verde após autenticar e vermelho ao retirar, recusar ou invalidar o cartão;
9. testar disconnect e restart durante cada estado da sessão.

## Estado final desta etapa

- Lote A: **APROVADO ESTATICAMENTE após correções**.
- Bloqueios estáticos do Lote A: nenhum encontrado após regressão.
- Runtime: **PENDENTE DE RUNTIME**.
- Fase 0: não marcada como `[S]`.
