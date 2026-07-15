# MZ Bank — Relatório de execução runtime da Fase 1

Data de preparação: 2026-07-15  
Gate de entrada: Fase 0 `[S]` em `reports/PHASE_0_STATIC_APPROVAL.md`  
Estado desta rodada: **NÃO EXECUTADA — PENDENTE DE STAGING**  
Decisão runtime: **NÃO ATRIBUÍDA**

Este arquivo foi criado antes da primeira execução. Nenhum caso abaixo foi executado ou aprovado durante sua preparação. `PASSOU`, `FALHOU` ou `BLOQUEADO` só podem ser preenchidos com evidência real; aprovação final pertence a uma etapa posterior do roadmap.

## Relato geral recebido para triagem

- Data do relato: 2026-07-15.
- Relato preservado: **“está tudo ok”**.
- Ambiente informado: `[NÃO INFORMADO]`.
- IDs efetivamente executados: `[NÃO INFORMADOS]`.
- Passos/resultados por caso: `[NÃO INFORMADOS]`.
- Console server/F8: `[NÃO FORNECIDO]`.
- Queries antes/depois: `[NÃO FORNECIDAS]`.
- Evidência visual: `[NÃO FORNECIDA]`.
- Classificação documental: **RELATO GERAL INSUFICIENTE PARA APROVAR CASOS INDIVIDUAIS**.

O relato não foi descartado nem convertido em evidência inexistente. Como não permite saber quais dos 43 casos foram executados — especialmente fault injection, concorrência, falha SQL, timeout após commit e reconciliação de cache/persistência — todas as linhas permanecem `NÃO EXECUTADO` até o registro individual correspondente.

## 1. Identificação do ambiente

| Campo | Valor real da rodada |
|---|---|
| Executor | `[PENDENTE]` |
| Data/hora inicial e final | `[PENDENTE]` |
| Ambiente | `[PENDENTE — deve ser staging isolado]` |
| Host/instância FiveM | `[PENDENTE]` |
| Artifacts/build | `[PENDENTE]` |
| OneSync | `[PENDENTE]` |
| MySQL/MariaDB | `[PENDENTE]` |
| oxmysql | `[PENDENTE]` |
| Pacote implantado/hash | `[PENDENTE]` |
| Backup/snapshot | `[PENDENTE]` |
| Mapa/MLO | `[PENDENTE]` |
| Harness/fault injector autorizado | `[PENDENTE — nome, versão e hash]` |
| Console server/F8 capturados | `[PENDENTE]` |
| Jogador A / source redigido | `[PENDENTE]` |
| Jogador B / source redigido | `[PENDENTE]` |
| Personagem A / citizenid redigido | `[PENDENTE]` |
| Personagem B / citizenid redigido | `[PENDENTE]` |

### Versões esperadas pelo pacote estático

| Resource | Manifest atual | Versão implantada |
|---|---:|---|
| `mz_core` | `1.0.0` | `[PENDENTE]` |
| `mz_economy` | `0.1.0` | `[PENDENTE]` |
| `mz_inventory` | `0.1.0` | `[PENDENTE]` |
| `mz_bank` | `2.0.0` | `[PENDENTE]` |

## 2. Configuração e migrations da rodada

| Campo | Esperado estático | Real/evidência |
|---|---|---|
| Ordem | `oxmysql → ox_lib → mz_core → mz_economy → mz_inventory → mz_bank` | `[PENDENTE]` |
| Schema do banco | versão `2` | `[PENDENTE]` |
| Migration `1` | `mz_bank_cards` | `[PENDENTE]` |
| Migration `2` | `mz_bank_legacy_reports` | `[PENDENTE]` |
| Sessão | `120 s` | `[PENDENTE]` |
| Distância server-side | `7,5 m` | `[PENDENTE]` |
| Match do catálogo ATM | `2,25 m` | `[PENDENTE]` |
| Limite por operação/canal | `1.000.000` | `[PENDENTE]` |
| Limite diário | inexistente (`false`) | `[PENDENTE]` |
| Taxa de transferência | `0%`, arredondamento `floor` | `[PENDENTE]` |
| Cartão no ATM/agência | obrigatório/opcional | `[PENDENTE]` |

## 3. Baseline financeiro e de dados

| Medida | Antes | Depois | Evidência/query |
|---|---:|---:|---|
| A wallet | `[PENDENTE]` | `[PENDENTE]` | `Q-ACC-01` |
| A bank | `[PENDENTE]` | `[PENDENTE]` | `Q-ACC-01` |
| B wallet | `[PENDENTE]` | `[PENDENTE]` | `Q-ACC-01` |
| B bank | `[PENDENTE]` | `[PENDENTE]` | `Q-ACC-01` |
| Linhas idempotentes de A | `[PENDENTE]` | `[PENDENTE]` | `Q-IDEM-01` |
| Linhas ledger do pacote | `[PENDENTE]` | `[PENDENTE]` | `Q-LEDGER-01` |
| Linhas legadas | `[PENDENTE]` | `[PENDENTE]` | `Q-LEGACY-01` |

## 4. Invariantes obrigatórios

- `INV-01`: `player.money.wallet`, `player.money.bank` e `mz_player_accounts` representam o mesmo estado após commit/reconnect.
- `INV-02`: saque e depósito sem taxa preservam `wallet + bank` do titular.
- `INV-03`: transferência com taxa zero preserva `bank_A + bank_B`; com taxa, a diferença é exatamente a taxa registrada.
- `INV-04`: falha antes do commit não altera cache, persistência, idempotência ou ledger.
- `INV-05`: mesma identidade de ator + resource + chave + payload produz uma movimentação e uma `correlationId`.
- `INV-06`: mesma chave com payload diferente retorna conflito e não movimenta saldo.
- `INV-07`: resposta confirmada mantém `ok`, `confirmed` e `correlationId` mesmo se overview/extrato falhar depois.
- `INV-08`: canal, identidade, posição e cartão são derivados/revalidados pelo servidor; payload adulterado não amplia acesso.
- `INV-09`: bloquear, revogar, substituir ou remover o item invalida novas operações protegidas pela política.
- `INV-10`: migration repetida não perde dados nem duplica versão/schema.
- `INV-11`: `mz_bank` não cria saldo paralelo nem escreve nas tabelas legadas durante o fluxo normal.
- `INV-12`: parada do `mz_economy` degrada somente ledger/extrato; operações oficiais continuam no `mz_core`.

## 5. Matriz de execução

Valores permitidos em **Status**: `NÃO EXECUTADO`, `PASSOU`, `FALHOU` ou `BLOQUEADO`.

### RT-INIT — Inicialização, schema e dependências

| ID | Caso | Resultado esperado resumido | Resultado real | Evidência | Status | Bug/repetição |
|---|---|---|---|---|---|---|
| RT-INIT-01 | Start na ordem oficial | `mz_bank ready` somente após schema v2; callbacks/exports disponíveis | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-INIT-02 | Migration inicial e restart idempotente | versões 1/2 únicas; schema e dados preservados | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-INIT-03 | Dependência rígida ausente/parada | readiness falso e erro explícito; nenhuma sessão/operação nova | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-INIT-04 | `bank_card` e contratos reais | item disponível; seis callbacks e exports consumidos sem erro | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-INIT-05 | Parada/retorno do `mz_economy` | ready continua true/degraded; extrato falha; operações continuam; recuperação automática | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-INIT-06 | Restart do `mz_bank` | saldos inalterados; tokens antigos inválidos; nova sessão funciona | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-INIT-07 | Restart do `mz_core` e dependentes | banco fecha; cache reconstrói após ordem oficial; persistência preservada | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-INIT-08 | Ausência de saldo paralelo/legado | nenhuma tabela paralela criada; legado sem escrita | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |

### RT-SESSION — Sessão, canal, estado físico e NUI

| ID | Caso | Resultado esperado resumido | Resultado real | Evidência | Status | Bug/repetição |
|---|---|---|---|---|---|---|
| RT-SESSION-01 | Agência válida e falsa | válida abre; falsa/distante é negada | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-SESSION-02 | ATM catalogado e inexistente | catalogado abre; fora da allowlist é negado | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-SESSION-03 | Canal/coords/phone adulterados | callback físico não alcança phone nem aceita ponto arbitrário | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-SESSION-04 | Token ausente/falso/expirado/de outro jogador | todas as tentativas negadas sem exposição ou saldo alterado | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-SESSION-05 | Afastamento, morte e veículo | sessão/NUI encerradas e token anterior inutilizável | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-SESSION-06 | Troca de personagem e disconnect | identidade anterior não acessível; sessão/rate limit limpos | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-SESSION-07 | Animação, alinhamento e fechamento | cenário inicia/termina; foco e tarefas são liberados | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-SESSION-08 | Slot amarelo/verde/vermelho | estados e transições visuais seguem autenticação/recusa/retirada | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |

### RT-CARD — Emissão, autenticação e revalidação

| ID | Caso | Resultado esperado resumido | Resultado real | Evidência | Status | Bug/repetição |
|---|---|---|---|---|---|---|
| RT-CARD-01 | ATM sem cartão e cartão válido | sem cartão negado; cartão próprio ativo autentica | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-CARD-02 | Cartão de outro titular | `card_owner_mismatch`; nenhuma conta exposta | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-CARD-03 | Cartão bloqueado/revogado | credencial não ativa é negada | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-CARD-04 | Bloqueio durante sessão | próxima chamada invalida sessão e impede operação | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-CARD-05 | Substituição durante sessão | cartão anterior revogado; sessão antiga inválida; novo item ativo | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-CARD-06 | Remoção do item | próxima chamada protegida falha e encerra sessão | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-CARD-07 | Emissão inicial/falha de inventário | item e credencial coerentes; falha não deixa credencial ativa órfã | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |

### RT-CASH — Depósito e saque

| ID | Caso | Resultado esperado resumido | Resultado real | Evidência | Status | Bug/repetição |
|---|---|---|---|---|---|---|
| RT-CASH-01 | Depósito válido | wallet diminui, bank aumenta; total e referência preservados | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-CASH-02 | Saque válido | bank diminui, wallet aumenta; total e referência preservados | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-CASH-03 | Saldo total permitido/insuficiente | limite disponível funciona; insuficiência não altera estado | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-CASH-04 | Decimal, zero, negativo, texto, NaN/infinito | `invalid_amount`; sem saldo/idempotência/ledger | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-CASH-05 | Limite por canal/operação | até 1.000.000 segue fluxo; acima retorna `transaction_limit` | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-CASH-06 | Duplo clique e concorrência | uma movimentação por chave; sem saldo negativo | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-CASH-07 | Reconnect/cache/persistência/ledger | NUI, cache e SQL convergem; referência coincide | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |

### RT-TRANSFER — Transferência entre jogadores

| ID | Caso | Resultado esperado resumido | Resultado real | Evidência | Status | Bug/repetição |
|---|---|---|---|---|---|---|
| RT-TRANSFER-01 | Transferência válida | A debita uma vez; B credita uma vez; mesma `correlationId` | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-TRANSFER-02 | Destinatário inválido/offline e autotransferência | erros estáveis; nenhuma ponta alterada | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-TRANSFER-03 | Taxa e arredondamento | taxa zero no pacote; cenário opcional segue `floor` | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-TRANSFER-04 | Transferências cruzadas | locks determinísticos; sem deadlock ou estado parcial | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-TRANSFER-05 | Concorrência com saldo disputado | somente operações cobertas pelo saldo confirmam | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-TRANSFER-06 | Disconnect de uma ponta | commit inteiro ou nenhuma alteração; estado reconciliável | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-TRANSFER-07 | Falha SQL transacional | duas pontas e idempotência revertem; cache não antecipa commit | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |

### RT-RETRY — Idempotência e resposta ambígua

| ID | Caso | Resultado esperado resumido | Resultado real | Evidência | Status | Bug/repetição |
|---|---|---|---|---|---|---|
| RT-RETRY-01 | Chave ausente/inválida | operação negada antes do core | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-RETRY-02 | Mesma chave e mesmo payload | mesmo resultado/referência; `replayed = true`; um movimento | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-RETRY-03 | Mesma chave e payload conflitante | `idempotency_conflict`; operação original preservada | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-RETRY-04 | Timeout do client depois do commit | retry recupera resultado e não duplica saldo | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-RETRY-05 | Overview/extrato falha após commit | sucesso confirmado e referência permanecem; `refreshError` informa falha | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |
| RT-RETRY-06 | Restart depois do commit/antes da resposta | mesma chave recupera resultado persistido após nova sessão | `[PENDENTE]` | `[PENDENTE]` | NÃO EXECUTADO | `[PENDENTE]` |

## 6. Registro de evidências

| ID do teste | Vídeo/screenshot | Console server | Console F8 | Queries antes/depois | Payload/resposta redigidos | Responsável |
|---|---|---|---|---|---|---|
| `[PENDENTE]` | `[PENDENTE]` | `[PENDENTE]` | `[PENDENTE]` | `[PENDENTE]` | `[PENDENTE]` | `[PENDENTE]` |

Tokens, chaves completas, `citizenid`, license e `card_uid` não devem aparecer em evidência pública. Preserve o material integral somente no repositório seguro da rodada e use formas redigidas neste relatório.

## 7. Bugs e correções

| Bug ID | Teste origem | Sintoma/evidência | Causa raiz | Arquivos alterados | Risco | Testes afetados | Estado |
|---|---|---|---|---|---|---|---|
| `[PENDENTE]` | `[PENDENTE]` | `[PENDENTE]` | `[PENDENTE]` | `[PENDENTE]` | `[PENDENTE]` | `[PENDENTE]` | `[PENDENTE]` |

## 8. Repetições

| Repetição | Bug/teste | Pacote implantado | Casos repetidos | Resultado real | Evidência | Estado |
|---|---|---|---|---|---|---|
| `[PENDENTE]` | `[PENDENTE]` | `[PENDENTE]` | `[PENDENTE]` | `[PENDENTE]` | `[PENDENTE]` | `[PENDENTE]` |

## 9. Fechamento da rodada

- Total planejado: `43` casos.
- Passou: `[PENDENTE]`.
- Falhou: `[PENDENTE]`.
- Bloqueado: `[PENDENTE]`.
- Não executado: `43` na preparação.
- Invariantes violados: `[PENDENTE]`.
- Bugs abertos: `[PENDENTE]`.
- Testes que precisam ser repetidos: `[PENDENTE]`.
- Limitações aceitas: `[PENDENTE]`.
- Decisão final: `[PENDENTE — não preencher sem evidência completa e etapa de decisão autorizada]`.
