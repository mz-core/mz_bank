# Fase 6 — Implementação do P6-D

Data: 2026-07-19  
Estado: **P6-D `[S]` validado estaticamente; runtime pendente**  
Fase 6: **`[~]` Em implementação**

## Resultado

O aplicativo passou a salvar, listar, usar e remover destinatários favoritos. O favorito é uma
preferência do personagem no `mz_phone`; não é uma conta, não possui saldo e não substitui a
resolução oficial do `mz_bank`.

## Decisões

- o favorito somente nasce de uma transferência já confirmada;
- a NUI nunca fornece a rota que será persistida;
- o servidor reaproveita a rota validada mantida no intent concluído;
- o apelido inicial é o nome parcial já devolvido pela resolução segura;
- a NUI recebe `favoriteRef`, agência e conta mascarada, nunca ID SQL ou número completo salvo;
- selecionar um favorito envia apenas `favoriteRef` e valor inteiro;
- antes de nova transferência, a rota é resolvida e revalidada novamente pelo P2-E/P6-B;
- destinatário offline, bloqueado, encerrado ou inexistente continua sendo negado;
- limite padrão: 12 favoritos por personagem;
- repetição da mesma rota atualiza o favorito existente por constraint única.

## Persistência

Tabela idempotente: `mz_phone_bank_favorites`.

| Campo | Uso |
|---|---|
| `id` | chave interna, nunca enviada à NUI |
| `owner_citizenid` | dono interno do favorito, resolvido pelo servidor |
| `label` | nome parcial/apelido exibido |
| `branch` | agência pública |
| `account_number` | número público da conta |
| `check_digit` | dígito público |
| `account_type` | atualmente `personal` |
| timestamps | criação e atualização |

Não existe coluna de saldo, target `citizenid`, license, metadata financeira ou segredo. Não foi
criada foreign key entre resources porque a compatibilidade e o ciclo de vida não são garantidos.

## Arquivos alterados

- `mz_phone/shared/config.lua`;
- `mz_phone/sql/mz_phone.sql`;
- `mz_phone/server/repository.lua`;
- `mz_phone/server/bank.lua`;
- `mz_phone/web/app.js`;
- `mz_phone/web/apps/bank.js`;
- `mz_phone/web/css/apps/bank.css`;
- `mz_phone/README.md`;
- `mz_bank/BANK_ROADMAP.md`.

## Segurança e invariantes

- ownership vem da sessão `phone`, nunca do client;
- referências são temporárias e vinculadas ao token atual;
- queries sempre incluem `owner_citizenid` resolvido no servidor;
- criação depende de `confirmationRef` concluída e ainda válida;
- resolução do favorito não confia em rota enviada pela NUI;
- salvar, listar ou remover favorito não movimenta saldo e não cria ledger/outbox;
- a transferência continua nos serviços oficiais do `mz_core` via `mz_bank`;
- nenhum contrato de transferência offline foi criado;
- nenhum acesso direto do frontend ao banco de dados foi criado.

## Validações estáticas

- `luac -p` aprovado para `repository.lua` e `bank.lua`;
- `node --check` aprovado para `app.js` e `apps/bank.js`;
- DDL usa InnoDB, utf8mb4, chave única por dono/rota e aplicação `IF NOT EXISTS`;
- SQL parametrizado em todas as operações;
- DTO de favoritos não contém ID SQL, número completo ou identificador do destinatário;
- busca confirmou ausência de saldo/ledger no novo schema;
- fluxo manual por rota e bloqueio de cartão permanecem preservados.

## Runtime pendente

Executar o caso único em `mz_phone/docs/MZ_BANK_APP_P6_D_RUNTIME_CHECKLIST.md`. Não marcar P6-D como
`[R]` antes da persistência após reopen/restart, uso e remoção do favorito serem confirmados.

## Fora do escopo

- edição livre de rota ou nome;
- favoritos compartilhados entre personagens;
- transferência offline;
- notificações push;
- PIX, QR Code, contas organizacionais ou produtos financeiros;
- conclusão integral da Fase 6.
