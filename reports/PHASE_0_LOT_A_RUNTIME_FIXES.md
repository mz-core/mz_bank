# MZ Bank — Correções de falhas runtime do Lote A

Data: 2026-07-15  
Rodada: `LOT-A-RUNTIME-OBS-01`, repetição 1.

## Estado

Foi tratada somente a falha real informada na abertura. A correção passou por validação de sintaxe e harness controlado, mas **ainda não foi repetida no FiveM**. Nenhum teste foi aprovado e a Fase 0 não foi marcada como `[S]` ou `[R]`.

## Falha real recebida

Relato preservado no checklist:

> “diz que n e possivel validar o personagem quando vou abrir o banco”

Correspondência confirmada no código:

- mensagem: `Config.Locale.invalid_ped`;
- retorno: `invalid_ped`;
- caminho de abertura: `MZBankService.OpenSession -> resolvePhysicalContext -> getServerPlayerState`.

Na primeira execução não foram fornecidos canal, coordenada, screenshot, build dos artifacts ou detalhe do native. Depois da primeira correção, a falha foi repetida e o console real fornecido foi:

```text
[script:mz_bank] [mz_bank] session denied source=2 error=invalid_ped detail=entity_missing
```

Esse resultado foi preservado no checklist. Canal e ponto exatos continuam não informados.

## Causa raiz identificável no código

A abertura original fazia uma única amostragem server-side do ped. Qualquer indisponibilidade transitória de `GetPlayerPed`, entidade, coordenadas, health ou estado de veículo encerrava a tentativa imediatamente com `invalid_ped`.

Isso era inconsistente com a sessão já aberta, que possuía uma tolerância prevista de 3 segundos para ped temporariamente indisponível. Além disso, todas as etapas retornavam o mesmo código sem detalhe interno, tornando o console incapaz de distinguir:

- ped ainda ausente;
- entity handle ainda não reconhecido;
- falha de coordenadas;
- falha de health;
- falha do estado de veículo.

A repetição com `detail=entity_missing` isolou a causa persistente: `GetPlayerPed` retornou handle não zero, mas `DoesEntityExist` devolveu falso para esse player ped. A validação interrompia o fluxo antes de tentar as demais leituras server-side.

A configuração versionada do starter contém `set onesync on`, e outros resources do projeto usam `GetPlayerPed`/`GetEntityCoords` server-side. Isso é evidência do contrato esperado no repositório, não prova de que o servidor onde a falha ocorreu iniciou exatamente com essa configuração.

## Correção mínima aplicada

Arquivo alterado: `mz_bank/server/service.lua`.

1. O `source` é convertido para string ao chamar `GetPlayerPed`, compatível com a assinatura server-side.
2. Somente `invalid_ped` transitório é repetido a cada 250 ms, por no máximo 3 segundos.
3. `player_dead` e `vehicle_forbidden` não recebem retry e continuam sendo recusados imediatamente.
4. Coordenada e ponto continuam validados exclusivamente no servidor; não foi criado fallback para posição informada pelo client.
5. A falha persistente continua retornando `invalid_ped`, agora com detalhe interno no log/console, por exemplo `ped_missing` ou `get_entity_coords_failed`.
6. Na primeira correção, a mesma função de estado físico continuou protegendo as operações posteriores; apenas a abertura recebeu a espera limitada.

Depois da repetição com `entity_missing`, foi aplicada uma segunda correção mínima:

7. `DoesEntityExist` deixou de ser um veto para player ped, pois produziu falso negativo comprovado no runtime.
8. A validade continua sendo comprovada no servidor por `GetPlayerPed` não zero, coordenadas numéricas, health numérico/positivo e estado de veículo numérico.
9. Falha em qualquer uma dessas leituras continua retornando `invalid_ped`; morte e veículo continuam negados pelos códigos próprios.

Nenhum saldo, operação financeira, callback de transferência, cartão, tabela ou contrato do Lote B foi alterado.

## Detalhes de diagnóstico possíveis

Se a abertura ainda falhar, o console server agora imprime:

```text
[mz_bank] session denied source=<source> error=invalid_ped detail=<detail>
```

Valores atuais de `detail`:

- `get_player_ped_failed`;
- `ped_missing`;
- `get_entity_coords_failed`;
- `coords_missing`;
- `get_entity_health_failed`;
- `health_missing`;
- `get_vehicle_ped_is_in_failed`;
- `vehicle_state_missing`.

O detalhe é interno e não é devolvido à NUI.

## Validações executadas fora do FiveM

- `server/service.lua` passou em `luac -p`;
- harness carregando o arquivo real: 11/11 verificações, exit code `0`;
- ped ausente nas três primeiras leituras e válido na quarta: abertura aprovada;
- ped ausente durante toda a janela: recusado após 13 amostras/12 esperas, sem loop ilimitado;
- personagem morto: recusado imediatamente em uma amostra;
- personagem em veículo: recusado imediatamente em uma amostra;
- ATM falso: continuou retornando `atm_invalid`;
- não houve execução de FiveM, movimentação ou aprovação runtime.

Após a evidência `entity_missing`, um segundo harness focado passou em 9/9 verificações:

- `DoesEntityExist=false` não bloqueia quando handle, coordenadas, health e veículo server-side são válidos;
- `DoesEntityExist` não é mais consultado como autoridade;
- coordenadas ausentes continuam negadas após retry limitado;
- morte e veículo continuam negados imediatamente;
- ATM falso continua negado;
- `server/service.lua` passou novamente em `luac -p`.

## Testes que precisam ser repetidos

### Repetição obrigatória da falha

1. `RTA-OPEN-01` — agência válida.
2. `RTA-OPEN-03` — ATM válido catalogado.

Como o relato não identificou o canal, ambos precisam ser repetidos. Em caso de nova falha, anexar a linha completa com `detail`.

### Regressão de segurança da abertura

3. `RTA-OPEN-02` — agência falsa.
4. `RTA-OPEN-04` — ATM inexistente/fora da allowlist.
5. `RTA-OPEN-05` — abertura distante com ponto real.
6. `RTA-CHAN-01` — channel adulterado na abertura.

### Regressão do estado físico compartilhado

7. `RTA-PHYS-02` — morte durante sessão.
8. `RTA-PHYS-03` — entrada em veículo.
9. `RTA-PHYS-05` — ped indisponível após tolerância.

### Regressão de UX dependente da abertura

10. `RTA-ANIM-01` — início e alinhamento da animação ATM.
11. `RTA-UI-01` — estados amarelo e verde.
12. `RTA-UI-03` — fechamento correto da NUI e foco.

Todos permanecem **NÃO EXECUTADOS APÓS A CORREÇÃO**.

## Critério para encerrar esta falha

A falha só pode ser considerada corrigida em runtime quando:

- agência e ATM válidos abrirem com ped vivo e a pé;
- pontos falsos, distância e canal adulterado continuarem negados;
- morte, veículo e ped persistentemente inválido continuarem negados;
- não houver erro Lua/native no console;
- animação, slot e NUI continuarem corretos;
- evidência e resultado real forem preenchidos no checklist.

## Segunda repetição informada

Resultado real recebido após remover o veto de `DoesEntityExist`:

> “abriu certinho agora”

A falha original `invalid_ped/detail=entity_missing` está **CORRIGIDA NO CENÁRIO RELATADO**. Como o canal/ponto, console e os demais passos não foram informados, `RTA-OPEN-01` e `RTA-OPEN-03` não foram individualmente aprovados e os testes de regressão continuam necessários.

Classificação atual: **FALHA ORIGINAL CORRIGIDA NO CENÁRIO RELATADO; LOTE A PENDENTE DE RUNTIME**.
