# Fase 2 — Revisão estática final do Lote P2-H

Data: 2026-07-17  
Decisão estática: **APROVADA COM CORREÇÕES**

```text
Fase 2: [S] Validada estaticamente
P2-A a P2-G: [R] Aprovados em runtime
P2-H: [S] Revisão estática concluída
P2-H runtime delta: NÃO EXECUTADO
```

## 1. Escopo

Revisão independente do código real atual, desenho, roadmap, migrations e aprovações P2-A a P2-G.
Não foram implementados phone, transferência offline, PIX, QR Code, conta empresarial, saldo ou
ledger paralelo.

## 2. Evidência runtime consolidada

| Conjunto | Aprovados registrados | Falhas | Bloqueados | Observação |
|---|---:|---:|---:|---|
| Fase 1 | 43 | 0 | 0 | regressão física/financeira integral registrada |
| P2-A | 27 | 0 | 0 | 1 caso não aplicável |
| P2-B | 13 | 0 | 0 | repository read-only e regressão |
| P2-C | 15 | 0 | 0 | criação, concorrência e DTO próprio |
| P2-D | 8 | 0 | 0 | backfill staging e auditoria |
| P2-E | 12 | 0 | 0 | resolução, privacidade e limites |
| P2-F | 16 | 0 | 0 | transferência pública e idempotência |
| P2-G | 15 | 0 | 0 | NUI, confirmação, receipt e regressão |
| **Total registrado** | **149** | **0** | **0** | resultados fornecidos pelo usuário |

Não foram inventados logs ou anexos ausentes. As limitações descritas nos relatórios individuais
permanecem válidas, incluindo a ausência de timeout SQL destrutivo real no P2-F.

## 3. Defeitos encontrados e corrigidos

### P2H-FIX-01 — ativação dependente de convar transitória

- **Causa:** `Config.PublicAccount.Enabled = false` fazia um reboot completo depender da convar de
  staging, não persistida na configuração real do servidor.
- **Impacto:** overview/transferência pública poderiam ficar indisponíveis após reboot.
- **Correção mínima:** feature aprovada ativada por padrão; convar antiga mantida apenas por
  compatibilidade de staging.
- **Arquivo:** `config.lua`.
- **Runtime afetado:** `P2H-INIT-01`.

### P2H-FIX-02 — estados não aplicados a saque e depósito

- **Causa:** a matriz `STATE_CAPABILITIES` era aplicada ao overview, resolução e transferência, mas
  `Withdraw`/`Deposit` chamavam o core sem consultar a capacidade da conta pública.
- **Impacto:** uma conta `blocked` poderia sacar; uma `frozen` poderia sacar/depositar, contrariando o
  desenho.
- **Correção mínima:** `validatePublicOriginCapability` deriva o titular no servidor, garante a conta
  idempotentemente e verifica `withdraw`/`deposit` antes de qualquer chamada financeira.
- **Arquivo:** `server/service.lua`.
- **Runtime afetado:** `P2H-STATE-01`.

### P2H-DOC-01 — README descrevia server ID

- **Correção:** documentação atualizada para agência/conta/DV, DTO mascarado e estados.
- **Arquivo:** `README.md`.

## 4. Gates do desenho

| Gate | Resultado estático | Evidência atual |
|---|---|---|
| `mz_bank_accounts` sem saldo | APROVADO | migration 003 não contém balance/wallet/bank/money/amount |
| NUI sem identificadores internos | APROVADO | zero ocorrências de citizenid/license/source alvo/IDs SQL em client/html |
| server ID removido como conta | APROVADO | fluxo executável usa rota e `resolutionToken`; contrato legado removido |
| criação concorrente sem duplicidade | APROVADO | constraints owner/type e route, releitura por titular e retry de colisão |
| rota encerrada não reutilizada | APROVADO | linha `closed` permanece e unicidade reserva branch/account para sempre |
| resolução resistente a enumeração | APROVADO | lookup exato, DV, resposta uniforme, rate limit, cooldown e auditoria mascarada |
| transferência usa core oficial | APROVADO | única chamada financeira por `MZBankBridge.TransferBankBetweenPlayers` |
| nenhum crédito offline por SQL | APROVADO | alvo precisa estar online e não existe DML de saldo no fluxo público |
| phone não chama core | APROVADO/NÃO APLICÁVEL | canal phone não foi implementado nesta fase |
| rollback v3 sem perda | APROVADO | feature pode ser desligada sem remover tabela; pacote deve permanecer compatível com v3 |
| NUI/animação/slot/sessão/cartão | APROVADO ESTATICAMENTE | arquivos físicos preservados; runtime anterior aprovado |
| estados no servidor | CORRIGIDO | overview, depósito, saque, resolução e transferência usam capacidades server-side |

## 5. Validações executadas

- JavaScript: `html/script.js` e `server/account_rng.js` aprovados por `node --check`;
- Lua portátil: 11 arquivos aprovados por parse; `config.lua` usa hashes com backticks próprios do
  FiveM e não é aceito integralmente pelo interpretador Lua 5.1 genérico;
- contrato DOM: todos os IDs referenciados existem e não há IDs duplicados;
- migration 003: zero DDL destrutivo, zero saldo e zero alteração de `mz_player_accounts`;
- fluxo executável: zero `recipientValue`, `targetId`, `ResolveRecipient` ou transferência por server ID;
- runners P2-B/P2-D/P2-E/P2-F: todos retornam antes de registrar superfície quando a convar padrão é 0;
- ordem real: `oxmysql`, `ox_lib`, `mz_core`, `mz_economy`, `mz_inventory`, `mz_bank` preservada em
  `mz_starter/cfg/resources.cfg`;
- contratos `GetPlayerByCitizenId` e `TransferBankBetweenPlayers` confirmados na implementação real do
  `mz_core`.

A escrita direta em `mz_player_accounts` encontrada em `server/legacy.lua` pertence exclusivamente ao
fluxo legado protegido por preview, confirmação forte, ACE, ambiente e flags desligadas por padrão;
ela não integra o fluxo normal ou a identidade pública.

## 6. Invariantes após as correções

- `active`: leitura, depósito, saque, transferência e recebimento;
- `blocked`: leitura, depósito e recebimento; saque/transferência negados;
- `frozen`: somente leitura;
- `closed`: fora do fluxo normal, rota preservada e nenhuma movimentação pelo `mz_bank`;
- saldos continuam exclusivamente no `mz_core`/`mz_player_accounts`;
- backfill não lê nem escreve saldo;
- resolução e NUI não expõem `citizenid`;
- transferência continua online, atômica e idempotente pelo core.

## 7. Runtime pendente

As duas correções finais alteram somente habilitação padrão e gates de saque/depósito. Para evitar
repetição desnecessária dos 149 testes já registrados, devem ser executados os três casos delta de
`PHASE_2_P2_H_RUNTIME_CHECKLIST.md`.

Até essa confirmação:

```text
Fase 2: [S] Validada estaticamente
Fase 2: NÃO MARCADA [R]
P2-H runtime: PENDENTE
```

