# Fase 6 — Limpeza para produção

Data: 2026-07-20  
Estado: **`[R]` aprovada após smoke final**

## Resultado

A superfície temporária de staging foi removida sem alterar os contratos aprovados do banco,
telefone ou domínio financeiro. Relatórios, checklists e evidências históricas permanecem no
repositório.

## Runners removidos

### mz_bank

- `server/p2b_runtime_runner.lua`;
- `server/p2d_runtime_runner.lua`;
- `server/p2e_runtime_runner.lua`;
- `server/p2f_runtime_runner.lua`;
- `server/p4_runtime_runner.lua`.

As cinco entradas também foram removidas do `fxmanifest.lua`.

### mz_core

- `server/accounts/p3c_runtime_runner.lua`;
- `server/accounts/p3d_runtime_runner.lua`;
- `server/accounts/p3e_runtime_runner.lua`;
- `server/accounts/p3f_runtime_runner.lua`;
- `server/accounts/p3g_runtime_runner.lua`.

Como o `mz_core` carrega `server/accounts/*.lua`, a exclusão dos arquivos remove os comandos do
runtime sem alterar a ordem dos módulos reais.

## Hooks removidos

- falha forçada de entrega de cartão no bridge do `mz_bank`;
- acesso interno à sessão/fixture P2-F no serviço bancário;
- criação/remoção artificial de preview P3-E no administrador da outbox;
- pausa artificial do dispatcher quando o runner P3-G estava ativo.

Busca estática confirmou ausência de `runtime_runner`, `runtime_test`, comandos de runner e
convars de fault injection nos resources executáveis.

## Ferramentas operacionais preservadas

- backfill de contas públicas: preview habilitado, aplicação desligada por padrão, ACE obrigatória;
- reconciliação e reprocessamento de dead-letter: administração desligada por padrão, ACE,
  confirmação forte e gate separado para aplicação;
- readiness, migrations e relatórios;
- auditoria histórica e linhas financeiras criadas durante staging.

Esses recursos não são runners e não foram removidos. Nenhum dado SQL foi apagado.

## Ordem de inicialização

`mz_starter/cfg/resources.cfg` passou a iniciar:

```text
mz_core -> mz_economy -> mz_inventory -> mz_bank -> mz_phone
```

## Validações

- `luac -p` aprovado nos manifests e arquivos Lua alterados;
- `node --check` aprovado nos arquivos JavaScript críticos do banco/telefone;
- nenhuma referência aos símbolos e convars removidos permaneceu no código executável;
- nenhum runner permaneceu sob `mz_bank`, `mz_core`, `mz_economy` ou `mz_phone`;
- `mz_bank/config.lua` usa literais de hash com crase próprios do Cfx; por isso o arquivo completo
  não é compatível com o parser Lua padrão, embora seja válido no runtime FiveM e não tenha sido
  alterado nesta limpeza.

## Limites

- convars digitadas anteriormente no console deixam de ter consumidor, mas linhas equivalentes em
  configurações externas ao workspace devem ser removidas manualmente se existirem;
- dados históricos de testes não foram apagados para preservar ledger e auditoria;
- a revisão estática isolada não aprova runtime; a confirmação posterior está registrada abaixo.

## Aprovação runtime

O usuário executou o caso único de `PHASE_6_PRODUCTION_SMOKE_CHECKLIST.md` e informou “certinho”.
Não foram anexados logs, capturas ou queries adicionais. A limpeza fica aprovada sem inventar
evidências além dessa confirmação textual.

```text
Limpeza de produção: [R] Aprovada
Smoke final: APROVADO
Falhas pendentes conhecidas: 0
```
