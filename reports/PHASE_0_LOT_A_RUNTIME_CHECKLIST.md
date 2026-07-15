# MZ Bank — Checklist runtime do Lote A

Data de preparação: 2026-07-15  
Escopo: `B0-01`, `B0-02`, `B0-03`, `B0-04` e `B0-09`.

## Estado deste documento

Todos os testes abaixo estão **NÃO EXECUTADOS**. Este documento não contém aprovação runtime, não marca a Fase 0 como `[S]` e não autoriza avanço de fase.

## Resultado real informado para triagem

### LOT-A-RUNTIME-OBS-01 — Falha ao abrir o banco

- **Relato real preservado:** “diz que n e possivel validar o personagem quando vou abrir o banco”.
- **Mensagem associada no código:** `invalid_ped` / `Nao foi possivel validar seu personagem.`
- **Canal/ponto testado:** `[NÃO INFORMADO — agência ou ATM]`
- **Passos efetivamente executados:** `[INFORMADO APENAS: tentativa de abrir o banco]`
- **Evidência:** `[NÃO FORNECIDA]`
- **Console client/server:** `[NÃO FORNECIDO]`
- **Mapeamento para caso:** `[PENDENTE — repetir RTA-OPEN-01 e RTA-OPEN-03 após a correção]`
- **Primeira repetição após retry:** `FALHOU — a mensagem client-side permaneceu.`
- **Console server preservado:** `[script:mz_bank] [mz_bank] session denied source=2 error=invalid_ped detail=entity_missing`
- **Causa runtime confirmada:** `DoesEntityExist` devolveu falso para o handle não zero retornado por `GetPlayerPed`.
- **Segunda correção:** veto de `DoesEntityExist` removido; validações server-side de handle, coordenadas, health e veículo preservadas.
- **Segunda repetição após a correção:** `PASSOU NO CENÁRIO RELATADO — “abriu certinho agora”.`
- **Canal/ponto da repetição aprovada:** `[NÃO INFORMADO — não usar este resultado para aprovar individualmente RTA-OPEN-01 ou RTA-OPEN-03]`
- **Escopo do resultado:** confirma somente que a falha original `entity_missing` não impediu essa abertura; demais critérios do teste e do Lote A continuam pendentes.

Valores atuais que orientam os resultados esperados:

- sessão: 120 segundos;
- fechamento client-side por distância: 3,0 m;
- validação server-side: 7,5 m;
- correspondência com o catálogo ATM: 2,25 m;
- cartão `bank_card`: obrigatório no ATM e não obrigatório na agência;
- canais físicos existentes: `atm` e `branch`;
- canal `phone`: não implementado.

## Regras de execução e evidência

1. Executar somente em staging, com personagens e saldos descartáveis.
2. Registrar build do servidor, versão dos artifacts, OneSync, mapa/MLO, resources iniciados e configuração efetiva antes de testar.
3. Manter abertos o console do client/F8, o console do servidor e o destino real de `mz_core:CreateDetailedLog`.
4. Para adulteração, usar somente um harness temporário autorizado de staging capaz de chamar os callbacks reais já existentes. Não modificar `mz_bank` durante a rodada. Registrar nome/hash do harness na evidência.
5. Não publicar tokens completos, citizenids ou card UIDs. Nas evidências, usar forma redigida como `abc…xyz`.
6. Quando houver preparação direta de banco/inventário, usar somente personagem descartável, registrar a operação exata e não reutilizar esse personagem em teste financeiro sem restaurar o estado.
7. Para cada caso, preencher `PASSOU`, `FALHOU` ou `BLOQUEADO` somente depois da execução. Teste bloqueado não equivale a aprovado.
8. Capturar erros Lua/JS, stack traces e divergências mesmo quando o resultado visual parecer correto.

## Ambiente da rodada

- **Executor:** `[PENDENTE]`
- **Data/hora:** `[PENDENTE]`
- **Servidor/build/artifacts:** `[PENDENTE]`
- **OneSync:** `[PENDENTE]`
- **Mapa/MLO:** `[PENDENTE]`
- **Commit/pacote implantado:** `[PENDENTE]`
- **Resources e ordem de start:** `[PENDENTE]`
- **Personagem A / source redigido:** `[PENDENTE]`
- **Personagem B / source redigido:** `[PENDENTE]`
- **Ferramenta de captura/adulteração autorizada:** `[PENDENTE]`
- **Snapshot/backup de dados:** `[PENDENTE]`

---

## Abertura física e catálogo

### RTA-OPEN-01 — Agência válida

- **ID:** `RTA-OPEN-01`
- **Pré-condição:** `mz_bank`, `mz_core`, `ox_lib`, `oxmysql` e interação iniciados; personagem A vivo, a pé e carregado; usar uma agência real de `Config.Branches`, preferencialmente `(150.266, -1040.203, 29.374)`.
- **Passos:** 1. aproximar-se normalmente da agência; 2. acionar a interação; 3. aguardar overview; 4. navegar por saldo e extrato; 5. fechar pelo botão/tecla normal.
- **Resultado esperado:** sessão abre como `branch`; NUI recebe foco e mostra dados do personagem; nenhum cartão é exigido com a configuração atual; nenhuma operação ou DTO assume `phone`; fechamento remove foco e sessão.
- **Evidência:** `[PENDENTE — vídeo da aproximação/abertura/fechamento, screenshot da NUI e log bank.session.opened com canal branch]`
- **Console:** `[PENDENTE — colar client/server/log detalhado; registrar inclusive ausência de stack trace]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-OPEN-02 — Agência falsa

- **ID:** `RTA-OPEN-02`
- **Pré-condição:** harness autorizado; personagem A vivo e a pé em ponto pelo menos 10 m distante de todas as entradas de `Config.Branches`; coordenada falsa registrada.
- **Passos:** 1. chamar `mz_bank:server:openSession` com `channel='branch'` e a coordenada falsa; 2. registrar a resposta; 3. tentar usar eventual token retornado somente se, indevidamente, existir.
- **Resultado esperado:** abertura negada com `too_far`; nenhum token utilizável, NUI ou movimentação; tentativa registrada como sessão negada.
- **Evidência:** `[PENDENTE — payload redigido, coordenada usada, resposta completa sem IDs sensíveis e log bank.session.denied]`
- **Console:** `[PENDENTE — colar saída client/server e confirmar ausência de erro Lua]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-OPEN-03 — ATM válido catalogado

- **ID:** `RTA-OPEN-03`
- **Pré-condição:** personagem A possui `bank_card` próprio e ativo; escolher um prop físico cuja coordenada esteja em `Config.ATM.catalog`, por exemplo o ponto próximo a `(-303.33, -829.73, 32.42)` após confirmar o prop no mapa usado.
- **Passos:** 1. aproximar-se a pé; 2. acionar a interação do prop; 3. confirmar slot amarelo; 4. autenticar o cartão; 5. abrir saldo/extrato; 6. sair normalmente.
- **Resultado esperado:** sessão `atm` criada usando o ponto canônico; cartão válido autentica; NUI abre; nenhuma dependência de network ID é exposta; slot e animação seguem os casos de UX abaixo.
- **Evidência:** `[PENDENTE — vídeo do prop/posição, coordenada, resposta redigida e logs de abertura/autenticação]`
- **Console:** `[PENDENTE — client/server/log detalhado, incluindo eventuais avisos de native/entidade]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-OPEN-04 — ATM inexistente/fora da allowlist

- **ID:** `RTA-OPEN-04`
- **Pré-condição:** harness autorizado; personagem A vivo e a pé; escolher coordenada próxima do jogador, mas mais de 2,25 m de toda entrada de `Config.ATM.catalog`.
- **Passos:** 1. registrar posição real do jogador; 2. chamar `openSession` com `channel='atm'` e a coordenada não catalogada; 3. registrar resposta; 4. tentar overview apenas se houver token indevido.
- **Resultado esperado:** `atm_invalid`; nenhum token/NUI/movimentação; proximidade entre jogador e coordenada falsa não é aceita como prova de ATM.
- **Evidência:** `[PENDENTE — posição do jogador, coordenada falsa, menor distância calculada ao catálogo, resposta e log de negação]`
- **Console:** `[PENDENTE — colar client/server; ausência de stack trace]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-OPEN-05 — Abertura distante com ponto real

- **ID:** `RTA-OPEN-05`
- **Pré-condição:** harness autorizado; selecionar agência ou ATM canônico; personagem A posicionado a mais de 7,5 m do ponto.
- **Passos:** 1. registrar posição server-side observável e distância; 2. chamar `openSession` com canal/coordenada canônicos; 3. registrar resposta; 4. confirmar que a NUI não abriu.
- **Resultado esperado:** `too_far`; ponto verdadeiro não autoriza jogador distante; nenhum token ou operação.
- **Evidência:** `[PENDENTE — coordenadas, cálculo de distância, resposta e log bank.session.denied]`
- **Console:** `[PENDENTE — colar client/server/log detalhado]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

## Canal e superfície física

### RTA-CHAN-01 — Channel adulterado na abertura

- **ID:** `RTA-CHAN-01`
- **Pré-condição:** harness autorizado; personagem A junto de um ponto físico válido.
- **Passos:** 1. chamar `openSession` com a coordenada válida e `channel='phone'`; 2. repetir com canal desconhecido e com variação de caixa/espaços não prevista; 3. registrar cada resposta.
- **Resultado esperado:** todas as tentativas não físicas retornam `channel_forbidden`; nenhum token/NUI/operação; somente `atm` ou `branch` exatos são aceitos.
- **Evidência:** `[PENDENTE — matriz payload/resposta e logs de negação, com tokens inexistentes]`
- **Console:** `[PENDENTE — client/server/log detalhado]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-CHAN-02 — Callback físico tentando selecionar phone

- **ID:** `RTA-CHAN-02`
- **Pré-condição:** sessão ATM válida e autenticada; token capturado/redigido pelo harness; nenhum saldo será movimentado.
- **Passos:** 1. chamar o callback `overview` com o token e argumento/contexto extra contendo `channel='phone'`; 2. chamar novamente sem o campo; 3. comparar respostas e logs; 4. não chamar APIs futuras/inexistentes de phone.
- **Resultado esperado:** campo extra não seleciona phone; overview continua pertencendo à sessão ATM ou é negado por assinatura, sem log/metadata `phone`; nenhuma capacidade nova é criada.
- **Evidência:** `[PENDENTE — chamadas redigidas, respostas comparadas e logs mostrando canal atm]`
- **Console:** `[PENDENTE — client/server/log detalhado; confirmar zero ocorrência runtime de fluxo phone]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-B009-01 — source, citizenid e recipientType arbitrários

- **ID:** `RTA-B009-01`
- **Pré-condição:** personagens A e B online; A com sessão ATM autenticada; saldos registrados; harness autorizado.
- **Passos:** 1. invocar o callback físico de transferência com valor inválido/seguro e campos extras `source`, `citizenid`, `recipientType='citizenid'`, `channel='phone'` e `targetId`; 2. usar `recipientValue` que não seja server ID válido para confirmar negação; 3. inspecionar resposta/NUI/logs; 4. confirmar saldos inalterados.
- **Resultado esperado:** campos extras são descartados; destinatário não é resolvido por citizenid/targetId; resposta é `recipient_invalid` ou `recipient_offline`; nenhum identificador interno volta à NUI; saldos não mudam.
- **Evidência:** `[PENDENTE — payload redigido, resposta, antes/depois dos saldos e captura da NUI/network]`
- **Console:** `[PENDENTE — client/server/log detalhado; registrar qualquer identificador indevido]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

## Tokens e sessão

### RTA-TOKEN-01 — Token falso

- **ID:** `RTA-TOKEN-01`
- **Pré-condição:** harness autorizado; personagem A carregado; valor aleatório de 48 caracteres que nunca foi emitido.
- **Passos:** 1. chamar overview com token falso; 2. repetir em saque/depósito usando valor positivo pequeno sem confirmar nova sessão; 3. comparar saldos antes/depois.
- **Resultado esperado:** `invalid_session` em todas as chamadas; nenhuma movimentação; token não é aceito por semelhança/formato.
- **Evidência:** `[PENDENTE — token redigido, respostas e saldos antes/depois]`
- **Console:** `[PENDENTE — bank.session.invalid e ausência de stack trace]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-TOKEN-02 — Token de outro jogador

- **ID:** `RTA-TOKEN-02`
- **Pré-condição:** A e B online; A abre/autentica ATM; harness B recebe somente para o teste uma cópia redigida/controlada do token de A.
- **Passos:** 1. do client/source B, chamar overview com token de A; 2. tentar operação com valor pequeno; 3. conferir contas de A e B; 4. confirmar que a sessão legítima de A não mudou de titular.
- **Resultado esperado:** chamadas de B retornam `invalid_session`; nenhuma leitura ou movimentação na conta A; source é o do callback, não campo do payload.
- **Evidência:** `[PENDENTE — sources redigidos, resposta, saldos A/B e logs]`
- **Console:** `[PENDENTE — client A, client B, servidor e log detalhado]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-TOKEN-03 — Token expirado

- **ID:** `RTA-TOKEN-03`
- **Pré-condição:** harness autorizado abre uma sessão válida sem manter a NUI renovando/fechando o token; registrar horário; não fazer callback bem-sucedido por mais de 120 s.
- **Passos:** 1. aguardar pelo menos 121 s; 2. chamar overview com o token antigo; 3. tentar operação não destrutiva/valor controlado; 4. comparar saldo.
- **Resultado esperado:** acesso negado sem movimentação; resposta pode ser `session_expired` se a validação atingir a sessão primeiro ou `invalid_session` se o cleanup periódico já a removeu. Em ambos os casos, token não revive.
- **Evidência:** `[PENDENTE — timestamps, token redigido, respostas e saldo antes/depois]`
- **Console:** `[PENDENTE — bank.session.expired ou bank.session.invalid; ausência de erro Lua]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

## Estado físico durante a sessão

### RTA-PHYS-01 — Afastamento durante sessão

- **ID:** `RTA-PHYS-01`
- **Pré-condição:** ATM válido, cartão autenticado, NUI aberta, posição inicial registrada.
- **Passos:** 1. afastar-se normalmente além de 3 m e depois além de 7,5 m; 2. observar fechamento client-side; 3. pelo harness, tentar reutilizar o token antigo já distante; 4. comparar saldo.
- **Resultado esperado:** NUI/foco/animação encerrados; token fechado ou recusado (`invalid_session`/`too_far`); servidor não executa operação a distância; log registra fechamento ou distância.
- **Evidência:** `[PENDENTE — vídeo com distância, estado da NUI, resposta do token antigo e saldo]`
- **Console:** `[PENDENTE — client/server, bank.session.too_far ou bank.session.closed]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-PHYS-02 — Morte durante sessão

- **ID:** `RTA-PHYS-02`
- **Pré-condição:** sessão ATM autenticada e NUI aberta; método real de morte em staging definido.
- **Passos:** 1. matar o personagem mantendo observação do client/server; 2. observar NUI/animação/foco; 3. tentar reutilizar o token antigo; 4. conferir saldo.
- **Resultado esperado:** NUI fecha, animação termina e foco é liberado; token não executa nova ação; erro/log pode ser `player_dead` ou `invalid_session` conforme a ordem entre fechamento client e validação server-side.
- **Evidência:** `[PENDENTE — vídeo, resposta do token antigo e saldo antes/depois]`
- **Console:** `[PENDENTE — client/server e bank.session.physical_state_denied/closed]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-PHYS-03 — Entrada em veículo

- **ID:** `RTA-PHYS-03`
- **Pré-condição:** sessão física aberta a pé; veículo disponível junto ao ponto sem impedir a preparação.
- **Passos:** 1. entrar no veículo durante a sessão; 2. observar fechamento; 3. tentar reutilizar o token; 4. tentar abrir nova sessão ainda no veículo.
- **Resultado esperado:** sessão/NUI encerradas; token antigo negado; abertura no veículo não prossegue; server-side pode retornar `vehicle_forbidden`; nenhuma operação executada.
- **Evidência:** `[PENDENTE — vídeo, respostas e log físico]`
- **Console:** `[PENDENTE — client/server, vehicle_forbidden ou fechamento anterior]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-PHYS-04 — Troca de personagem

- **ID:** `RTA-PHYS-04`
- **Pré-condição:** A possui sessão/token; fluxo real e suportado de logout/seleção de personagem disponível; segundo personagem na mesma conexão.
- **Passos:** 1. capturar/redigir token de A; 2. usar o fluxo oficial para trocar de personagem; 3. tentar overview/operação com token antigo; 4. abrir sessão nova com o personagem atual.
- **Resultado esperado:** token antigo retorna `player_not_loaded` ou `invalid_session`; nenhuma conta do personagem anterior é exposta/movimentada; somente nova sessão usa o novo citizenid server-side.
- **Evidência:** `[PENDENTE — sequência de troca, respostas, identidades redigidas e saldos separados]`
- **Console:** `[PENDENTE — mensagem de identity mismatch/cleanup e ausência de IDs na NUI]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-PHYS-05 — Ped indisponível após tolerância

- **ID:** `RTA-PHYS-05`
- **Pré-condição:** staging permite reproduzir despawn/transição legítima de ped sem desconectar; sessão capturada; método documentado.
- **Passos:** 1. tornar o ped indisponível; 2. manter a condição por mais de 3 s; 3. tentar callback com token antigo; 4. restaurar o ped e tentar reutilizar o token.
- **Resultado esperado:** após a tolerância, `invalid_ped` elimina a sessão; restaurar o ped não revive o token; nenhuma movimentação.
- **Evidência:** `[PENDENTE — método, timestamps, respostas e saldos]`
- **Console:** `[PENDENTE — bank.session.physical_state_denied com invalid_ped]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO; se não houver método seguro, marcar BLOQUEADO]`

## Cartões e item físico

### RTA-CARD-01 — Cartão válido do próprio titular

- **ID:** `RTA-CARD-01`
- **Pré-condição:** A possui exatamente um item `bank_card` próprio; metadata e linha `mz_bank_cards` correspondem; status `active`.
- **Passos:** 1. abrir ATM; 2. confirmar amarelo; 3. autenticar; 4. confirmar verde; 5. executar refresh e uma operação controlada autorizada; 6. conferir saldos/extrato.
- **Resultado esperado:** autenticação e chamadas subsequentes aprovadas; o mesmo cartão é revalidado; operação usa serviços do `mz_core`; nenhum identificador interno aparece na NUI.
- **Evidência:** `[PENDENTE — item/linha redigidos, vídeo, resposta, saldos e extrato]`
- **Console:** `[PENDENTE — client/server/log financeiro e ausência de stack trace]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-CARD-02 — Cartão de outro titular

- **ID:** `RTA-CARD-02`
- **Pré-condição:** com ferramenta administrativa real, colocar no inventário descartável de A somente um `bank_card` cuja metadata/credencial ativa pertença a B; registrar como o vínculo foi preparado.
- **Passos:** 1. abrir ATM como A; 2. tentar autenticar; 3. observar slot; 4. tentar overview/operação; 5. conferir contas A/B.
- **Resultado esperado:** `card_owner_mismatch`; slot vermelho e retorno para amarelo na recusa inicial; nenhuma conta exposta ou movimentada.
- **Evidência:** `[PENDENTE — metadata/UID redigidos, resposta, vídeo do slot e saldos A/B]`
- **Console:** `[PENDENTE — bank.card.denied com card_owner_mismatch]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-CARD-03 — Cartão bloqueado

- **ID:** `RTA-CARD-03`
- **Pré-condição:** A autentica cartão ativo; em staging, bloquear a mesma credencial pelo fluxo real de agência/export autorizado ou preparação controlada registrada, mantendo o item.
- **Passos:** 1. confirmar slot verde antes do bloqueio; 2. bloquear; 3. imediatamente chamar refresh/operação com token antigo; 4. observar slot/fechamento; 5. tentar nova autenticação com o item bloqueado.
- **Resultado esperado:** nenhuma nova operação; sessão antiga invalidada ou retorna `card_blocked`; slot fica vermelho antes de fechar; nova autenticação retorna `card_blocked`; saldos inalterados.
- **Evidência:** `[PENDENTE — método de bloqueio, status antes/depois, vídeo, respostas e saldos]`
- **Console:** `[PENDENTE — bank.card.blocked e bank.card.session_invalidated/denied]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-CARD-04 — Cartão revogado

- **ID:** `RTA-CARD-04`
- **Pré-condição:** A autentica cartão ativo; alterar somente a credencial descartável para `revoked` pelo fluxo real ou preparação SQL controlada e registrada; item permanece presente.
- **Passos:** 1. chamar refresh/operação com token antigo; 2. observar vermelho/fechamento; 3. abrir nova sessão e tentar autenticar com o item revogado; 4. conferir saldo.
- **Resultado esperado:** sessão antiga não executa operação; erro estável `card_invalid` ou sessão já invalidada; nova autenticação recusada; item presente não substitui status ativo; saldos inalterados.
- **Evidência:** `[PENDENTE — alteração registrada, linha redigida, vídeo, respostas e saldos]`
- **Console:** `[PENDENTE — bank.card.session_invalidated/denied, sem stack trace]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-CARD-05 — Cartão substituído

- **ID:** `RTA-CARD-05`
- **Pré-condição:** A possui cartão antigo ativo; replacement habilitado/acionado pelo contrato real em agência com token de agência; registrar UIDs redigidos e itens antes/depois.
- **Passos:** 1. concluir substituição; 2. confirmar nova credencial ativa e antiga revogada; 3. tentar token antigo capturado, se ainda disponível; 4. remover temporariamente o item novo no personagem descartável, deixando apenas o antigo, e tentar autenticar; 5. restaurar o novo e autenticar novamente.
- **Resultado esperado:** token antigo não opera; somente cartão antigo retorna `card_invalid`; cartão novo próprio/ativo autentica; nenhuma seleção implícita revive credencial substituída; saldo muda apenas pela taxa configurada, se houver.
- **Evidência:** `[PENDENTE — sequência, UIDs redigidos, status, itens, taxa/saldos e respostas]`
- **Console:** `[PENDENTE — bank.card.replaced/session_invalidated e erros de autenticação]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-CARD-06 — Remoção do item após autenticação

- **ID:** `RTA-CARD-06`
- **Pré-condição:** ATM autenticado com slot verde; ferramenta real de inventário capaz de remover o mesmo item sem alterar a credencial; UID redigido registrado.
- **Passos:** 1. remover o item; 2. imediatamente acionar refresh e depois operação controlada; 3. observar slot vermelho e fechamento após aproximadamente 900 ms; 4. tentar reutilizar token; 5. conferir saldo.
- **Resultado esperado:** primeira chamada protegida retorna `card_not_found`/negação e elimina sessão; nenhuma operação; slot vermelho antes do fechamento; token posterior `invalid_session`; saldo inalterado.
- **Evidência:** `[PENDENTE — inventário antes/depois, vídeo do slot/fechamento, respostas e saldo]`
- **Console:** `[PENDENTE — bank.card.session_invalidated com card_not_found]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

## Ciclo de vida

### RTA-LIFE-01 — Disconnect

- **ID:** `RTA-LIFE-01`
- **Pré-condição:** A com sessão ATM autenticada; token redigido capturado; B disponível para observar servidor se necessário.
- **Passos:** 1. desconectar A sem fechar a NUI; 2. confirmar `playerDropped`; 3. reconectar; 4. com harness autorizado, tentar token antigo; 5. abrir sessão nova.
- **Resultado esperado:** sessão e rate limits antigos removidos; token anterior retorna `invalid_session`; NUI antiga não reaparece; nova sessão usa token novo.
- **Evidência:** `[PENDENTE — timestamps, disconnect/reconnect, tokens redigidos e respostas]`
- **Console:** `[PENDENTE — playerDropped/cleanup, ausência de stack trace]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-LIFE-02 — Restart de `mz_bank`

- **ID:** `RTA-LIFE-02`
- **Pré-condição:** permissão de console para `restart mz_bank`; A com NUI ATM aberta, cartão verde e animação ativa; token redigido capturado.
- **Passos:** 1. executar `restart mz_bank` no console autorizado; 2. observar imediatamente NUI, foco e ped; 3. aguardar readiness; 4. tentar token antigo; 5. abrir sessão nova.
- **Resultado esperado:** NUI fecha, foco libera e tarefas/animação param no resource stop; token antigo não existe após restart; resource volta ready sem erro; nova sessão funciona somente com novo token.
- **Evidência:** `[PENDENTE — vídeo contínuo, comando/horário, resposta antiga/nova e readiness]`
- **Console:** `[PENDENTE — stop/start completos, prepare/readiness e qualquer erro Lua/SQL]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

## Animação, slot e fechamento da NUI

### RTA-ANIM-01 — Início e alinhamento da animação ATM

- **ID:** `RTA-ANIM-01`
- **Pré-condição:** ATM físico válido/catálogo; personagem A a pé, vivo e sem tarefa; câmera lateral disponível para gravação.
- **Passos:** 1. aproximar-se de ângulo oblíquo; 2. abrir ATM; 3. observar giro para a entidade; 4. aguardar pelo menos 2 s; 5. autenticar e permanecer na NUI.
- **Resultado esperado:** ped se alinha ao prop (ou à coordenada se a entidade local não for reencontrada) e inicia `PROP_HUMAN_ATM`; cenário permanece/reinicia enquanto a sessão ATM está aberta; sem teleport brusco ou animação duplicada.
- **Evidência:** `[PENDENTE — vídeo lateral do alinhamento e início, coordenada/prop usado]`
- **Console:** `[PENDENTE — client console; registrar erros de entity/scenario/native]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-ANIM-02 — Fim da animação

- **ID:** `RTA-ANIM-02`
- **Pré-condição:** cenário ATM ativo e NUI aberta.
- **Passos:** 1. sair normalmente; 2. repetir abrindo e forçando fechamento por distância; 3. repetir por restart no caso específico; 4. observar tarefas do ped após cada fechamento.
- **Resultado esperado:** `ClearPedTasks` encerra o cenário; ped recupera controle; animação não reinicia depois de `isOpen=false`; nenhum loop residual.
- **Evidência:** `[PENDENTE — vídeo dos três fechamentos e controle recuperado]`
- **Console:** `[PENDENTE — client/server; ausência de thread/task error]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-UI-01 — Estados amarelo e verde

- **ID:** `RTA-UI-01`
- **Pré-condição:** ATM válido; cartão próprio/ativo presente; captura de tela com cores confiáveis.
- **Passos:** 1. abrir ATM sem autenticar; 2. registrar texto/cor do slot; 3. autenticar; 4. registrar texto/cor novamente.
- **Resultado esperado:** abertura mostra amarelo `INSIRA O CARTAO`; autenticação válida mostra verde `CARTAO INSERIDO`; nenhuma informação interna aparece na conta, extrato ou mensagens.
- **Evidência:** `[PENDENTE — screenshots amarelo/verde e inspeção do payload NUI redigido]`
- **Console:** `[PENDENTE — client/NUI console e servidor]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-UI-02 — Estado vermelho na retirada/recusa

- **ID:** `RTA-UI-02`
- **Pré-condição:** preparar duas rodadas: cartão inválido/outro titular antes de autenticar e item válido removido após slot verde.
- **Passos:** 1. tentar cartão recusado e observar vermelho `CARTAO RECUSADO`; 2. confirmar retorno para amarelo após aproximadamente 900 ms; 3. autenticar cartão válido; 4. remover o item e acionar refresh; 5. observar vermelho antes do fechamento; 6. em saída voluntária autenticada, observar vermelho `RETIRE O CARTAO`.
- **Resultado esperado:** recusa inicial usa vermelho e volta para amarelo; invalidação após autenticação usa vermelho e fecha; retirada voluntária usa vermelho/ejecting antes de fechar; verde nunca permanece após item inválido.
- **Evidência:** `[PENDENTE — vídeo contínuo das três variantes, com tempos aproximados]`
- **Console:** `[PENDENTE — NUI/client/server e erros de cartão correspondentes]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

### RTA-UI-03 — Fechamento correto da NUI e foco

- **ID:** `RTA-UI-03`
- **Pré-condição:** testar agência e ATM; ferramenta para confirmar que teclado/mouse voltam ao jogo.
- **Passos:** 1. fechar por botão/ESC; 2. fechar por afastamento; 3. fechar por morte; 4. fechar por veículo; 5. fechar por expiração; 6. fechar por cartão invalidado; 7. fechar por restart; 8. após cada caso, mover câmera/personagem e tentar reabrir legitimamente.
- **Resultado esperado:** `app.hidden`, foco NUI liberado, inputs recuperados, animação encerrada quando ATM, token anterior negado e reabertura legítima possível; nenhum overlay, cursor ou processamento fica preso.
- **Evidência:** `[PENDENTE — matriz de vídeos/screenshots por causa de fechamento e tentativa de reabertura]`
- **Console:** `[PENDENTE — client/NUI/server por variante; registrar reason de fechamento quando disponível]`
- **Resultado real:** `[NÃO EXECUTADO — preencher PASSOU/FALHOU/BLOQUEADO e observações]`

---

## Resumo da rodada — preencher somente após execução

- **Total previsto:** 29 testes.
- **PASSOU:** `[PENDENTE]`
- **FALHOU:** `[PENDENTE]`
- **BLOQUEADO:** `[PENDENTE]`
- **NÃO EXECUTADO:** `29`
- **Falhas que exigem repetição:** `[PENDENTE]`
- **Evidências anexadas em:** `[PENDENTE]`
- **Decisão runtime do Lote A:** `[NÃO AVALIADA — este checklist não aprova runtime]`
