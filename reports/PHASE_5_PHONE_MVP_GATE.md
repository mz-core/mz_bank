# Fase 5 — Gate mínimo de cartões para o MVP do telefone

Data: 2026-07-19  
Decisão: **APROVADO EM RUNTIME PARA O ESCOPO DO MVP PHONE**

```text
Fase 5 completa: [~] Em implementação
Gate de cartões do MVP phone: [R] Aprovado em runtime
PIN: DESATIVADO
```

## Escopo necessário ao MVP

O aplicativo definido na Fase 6 precisa somente de:

- consulta sanitizada dos cartões do próprio jogador;
- últimos quatro dígitos, estado e datas públicas;
- bloqueio de cartão ativo;
- invalidação imediata de sessões que usam a credencial bloqueada;
- ausência de saldo no cartão;
- ausência de `card_uid`, PIN, titular interno e metadata no client;
- falha fechada quando cartão, item, titular ou sessão não puderem ser revalidados.

Emissão e segunda via continuam disponíveis apenas na agência. O telefone não emitirá nem
substituirá cartões no MVP.

## Evidências reais reaproveitadas

Não foram solicitados testes repetidos. Este gate reutiliza evidências runtime já registradas:

1. `PHASE_0_LOT_A_RUNTIME_APPROVAL.md`: cartão válido, outro titular, bloqueado, revogado,
   substituído, item removido, sessão e slot — 29/29 aprovados no Lote A.
2. `PHASE_3_P3_F_RUNTIME_APPROVAL.md`: taxa e compensação após falha controlada de entrega,
   consistência de saldo/outbox/ledger — 16/16 aprovados no P3-F.
3. `PHASE_4_RUNTIME_APPROVAL.md`: `cardRef` opaco, DTO sem `card_uid`, vínculo source/token,
   referência falsa negada e isolamento de canal — 10/10 aprovados na Fase 4.

Os resultados foram fornecidos pelo usuário após execução manual/runner no FiveM staging.

## Invariantes aprovadas para o telefone

- `mz_bank_cards` não contém saldo;
- saldo permanece em `player.money.wallet`, `player.money.bank` e `mz_player_accounts`;
- consulta e bloqueio passam pela API v1 do `mz_bank`;
- o client recebe `cardRef`, nunca a credencial persistida;
- cartão bloqueado deixa de autenticar e invalida sessão correspondente;
- item ausente ou de outro titular falha fechado;
- `mz_phone` não acessa tabela, inventário, `mz_core` ou `mz_economy` diretamente;
- PIN permanece desligado.

## Itens da Fase 5 completa que permanecem pendentes

- estado persistente `issuing`;
- constraint física adicional para concorrência de emissão;
- idempotência persistente específica de emissão/segunda via;
- `inventory_instance_uid` persistido na credencial;
- expiração e `last_used_at`;
- limites diários específicos do cartão;
- rotina administrativa completa de reconciliação inventário/credencial;
- histórico dedicado de todo o ciclo de vida;
- qualquer implementação de PIN.

Esses itens não são usados pelo MVP do telefone e não foram marcados como concluídos. A Fase 5
permanece `[~]`; somente seu gate obrigatório para consulta/bloqueio no app recebe `[R]`.

## Decisão

O ciclo necessário ao MVP — listar com DTO seguro e bloquear com invalidação imediata — possui
evidência estática e runtime suficiente. A dependência de cartões da Fase 6 está satisfeita sem
declarar a Fase 5 completa.

**Próximo passo: iniciar a Fase 6 com sessão phone vinculada ao jogador e aparelho.**
