# MZ Bank — Aprovação runtime do Lote A

Data do registro: 2026-07-15  
Escopo: `B0-01`, `B0-02`, `B0-03`, `B0-04` e `B0-09`  
Fonte do resultado: declaração explícita fornecida pelo usuário  
Forma de execução informada: manual, em runtime no FiveM

## Resultado executivo

```text
Lote A: APROVADO EM RUNTIME
29 aprovados
0 falhas
0 bloqueados
```

| Métrica | Quantidade |
|---|---:|
| Testes previstos | 29 |
| Testes executados | 29 |
| Testes aprovados | 29 |
| Testes com falha | 0 |
| Testes bloqueados | 0 |
| Testes não executados | 0 |

Os 29 casos e seus resultados individuais estão preservados em `PHASE_0_LOT_A_RUNTIME_CHECKLIST.md`.

## Ambiente informado

- Plataforma: FiveM.
- Modalidade: execução manual em runtime.
- Executor: usuário/responsável pelo servidor; identificação não fornecida.
- Instância, artifacts/build e OneSync: não fornecidos.
- Mapa/MLO e pacote implantado: não fornecidos.
- Data/hora exata da rodada: não fornecida; resultado comunicado em 2026-07-15.
- Consoles, queries, vídeos e screenshots: não fornecidos.

Nenhum detalhe ausente foi inferido ou criado para complementar a aprovação.

## Funcionalidades verificadas

Conforme os 29 casos aprovados pelo usuário, a rodada cobriu:

- abertura de agência válida e negação de agência falsa/distante;
- abertura de ATM catalogado e negação de ATM inexistente/fora da allowlist;
- negação de canal adulterado e tentativa de alcançar `phone` pelo fluxo físico;
- rejeição de `source`, `citizenid` e `recipientType` arbitrários;
- token falso, expirado e pertencente a outro jogador;
- afastamento, morte, veículo, troca de personagem e ped indisponível;
- cartão próprio válido, de outro titular, bloqueado, revogado e substituído;
- remoção do item físico depois da autenticação;
- limpeza de sessão em disconnect e restart de `mz_bank`;
- início, alinhamento e término da animação do ATM;
- slot amarelo, verde e vermelho;
- fechamento da NUI e liberação de foco/inputs.

## Invariantes observadas

O resultado consolidado informado implica aprovação runtime das invariantes verificadas pelos casos do Lote A:

1. O canal efetivo permanece vinculado à sessão server-side.
2. O fluxo físico não alcança `phone`.
3. Coordenada arbitrária não comprova ATM ou agência.
4. O servidor aplica distância, vida, veículo, ped e identidade do personagem.
5. Token não pode ser reutilizado por outro jogador, depois da expiração ou depois da limpeza da sessão.
6. Cartão e item físico continuam válidos somente enquanto titular, `cardUid` e status correspondem à política.
7. Bloqueio, revogação, substituição ou remoção impedem novas operações protegidas.
8. DTO client-facing não aceita identidade/tipo de destinatário livres nem expõe identificadores internos nos cenários cobertos.
9. NUI, animação e estados amarelo/verde/vermelho permanecem funcionais.

Essas invariantes foram registradas como observadas porque todos os casos correspondentes foram declarados aprovados pelo usuário; não há artefatos adicionais anexados para auditoria independente.

## Estado dos bloqueadores do Lote A

| Bloqueador | Decisão runtime |
|---|---|
| B0-01 — Canal controlado pelo client | ATENDIDO EM RUNTIME |
| B0-02 — ATM não comprovado pelo servidor | ATENDIDO EM RUNTIME |
| B0-03 — Cartão não revalidado | ATENDIDO EM RUNTIME |
| B0-04 — Estado físico confiado ao client | ATENDIDO EM RUNTIME |
| B0-09 — Superfície interna indevida | ATENDIDO EM RUNTIME |

## Limitações

- A aprovação usa o resultado fornecido pelo usuário; build, console, queries e mídia não foram anexados.
- O relatório não reexecuta nem reproduz os testes.
- A aprovação é limitada aos 29 casos do Lote A e não certifica Lote B ou Lote C.
- Não há aprovação de saldo, idempotência, migrations, dependências ou legado além do que pertença diretamente aos casos deste lote.
- O aplicativo phone não foi implementado nem testado como funcionalidade; verificou-se apenas que o fluxo físico não o alcança.
- Nenhum gate geral da Fase 0 é atribuído por este documento.

## Arquivos de documentação relacionados

- `reports/PHASE_0_LOT_A_RUNTIME_CHECKLIST.md`: 29 resultados individuais.
- `reports/PHASE_0_LOT_A_RUNTIME_FIXES.md`: histórico da correção da falha `invalid_ped`.
- `reports/PHASE_0_BLOCKER_MATRIX.md`: estado consolidado dos bloqueadores.

## Decisão final do Lote A

```text
Lote A: APROVADO EM RUNTIME
29 aprovados
0 falhas
0 bloqueados
```

Não há falha informada que exija correção ou repetição nesta rodada. Esta decisão não altera o estado dos itens dos Lotes B e C e não autoriza implementação de phone ou de fases posteriores.

