# MZ Bank — Relatório de execução runtime da Fase 1

Data de preparação: 2026-07-15  
Gate de entrada: Fase 0 `[S]` em `reports/PHASE_0_STATIC_APPROVAL.md`  
Estado desta rodada: **EXECUTADA MANUALMENTE NO FIVEM — APROVADA CONFORME RESULTADO FORNECIDO PELO USUÁRIO**  
Decisão runtime: **Fase 1 `[R]` — APROVADA EM RUNTIME**

Este arquivo foi criado antes da primeira execução e posteriormente atualizado com o resultado explícito fornecido pelo usuário após execução manual no FiveM. Não houve reexecução independente nem inclusão de evidência não fornecida.

## Resultado runtime fornecido pelo usuário

- Data do relato: 2026-07-15.
- Relato preservado: os testes runtime dos Lotes A, B e C e os testes financeiros da Fase 1 foram executados manualmente no FiveM e passaram.
- Ambiente informado: **FiveM**.
- IDs abrangidos neste relatório: **43 de 43**.
- Resultado: **43 aprovados, 0 falhas, 0 bloqueados e 0 não executados**.
- Console server/F8: `[NÃO FORNECIDO]`.
- Queries antes/depois: `[NÃO FORNECIDAS]`.
- Evidência visual: `[NÃO FORNECIDA]`.
- Classificação documental: **RESULTADO RUNTIME FORNECIDO PELO USUÁRIO RESPONSÁVEL PELA EXECUÇÃO MANUAL**.

O relato foi aplicado aos 43 casos planejados. A ausência de anexos adicionais permanece registrada como limitação; nenhum console, query, imagem, versão ou detalhe de execução foi inventado.

## 1. Identificação do ambiente

| Campo | Valor real da rodada |
|---|---|
| Executor | usuário responsável pela execução manual; identidade não informada |
| Data/hora inicial e final | não informadas |
| Ambiente | FiveM; detalhes da instância não informados |
| Host/instância FiveM | não informado |
| Artifacts/build | não informado |
| OneSync | não informado |
| MySQL/MariaDB | não informado |
| oxmysql | não informado |
| Pacote implantado/hash | não informado |
| Backup/snapshot | não informado |
| Mapa/MLO | não informado |
| Harness/fault injector autorizado | não informado |
| Console server/F8 capturados | não fornecidos |
| Jogador A / source redigido | não informado |
| Jogador B / source redigido | não informado |
| Personagem A / citizenid redigido | não informado |
| Personagem B / citizenid redigido | não informado |

### Versões esperadas pelo pacote estático

| Resource | Manifest atual | Versão implantada |
|---|---:|---|
| `mz_core` | `1.0.0` | não informada |
| `mz_economy` | `0.1.0` | não informada |
| `mz_inventory` | `0.1.0` | não informada |
| `mz_bank` | `2.0.0` | não informada |

## 2. Configuração e migrations da rodada

| Campo | Esperado estático | Real/evidência |
|---|---|---|
| Ordem | `oxmysql → ox_lib → mz_core → mz_economy → mz_inventory → mz_bank` | APROVADO conforme execução manual informada; detalhe não anexado |
| Schema do banco | versão `2` | APROVADO conforme execução manual informada; detalhe não anexado |
| Migration `1` | `mz_bank_cards` | APROVADO conforme execução manual informada; detalhe não anexado |
| Migration `2` | `mz_bank_legacy_reports` | APROVADO conforme execução manual informada; detalhe não anexado |
| Sessão | `120 s` | APROVADO conforme execução manual informada; detalhe não anexado |
| Distância server-side | `7,5 m` | APROVADO conforme execução manual informada; detalhe não anexado |
| Match do catálogo ATM | `2,25 m` | APROVADO conforme execução manual informada; detalhe não anexado |
| Limite por operação/canal | `1.000.000` | APROVADO conforme execução manual informada; detalhe não anexado |
| Limite diário | inexistente (`false`) | APROVADO conforme execução manual informada; detalhe não anexado |
| Taxa de transferência | `0%`, arredondamento `floor` | APROVADO conforme execução manual informada; detalhe não anexado |
| Cartão no ATM/agência | obrigatório/opcional | APROVADO conforme execução manual informada; detalhe não anexado |

## 3. Baseline financeiro e de dados

| Medida | Antes | Depois | Evidência/query |
|---|---:|---:|---|
| A wallet | não informado | preservado conforme resultado fornecido | query não fornecida |
| A bank | não informado | preservado conforme resultado fornecido | query não fornecida |
| B wallet | não informado | preservado conforme resultado fornecido | query não fornecida |
| B bank | não informado | preservado conforme resultado fornecido | query não fornecida |
| Linhas idempotentes de A | não informado | sem duplicidade conforme resultado fornecido | query não fornecida |
| Linhas ledger do pacote | não informado | preservadas conforme resultado fornecido | query não fornecida |
| Linhas legadas | não informado | preservadas conforme resultado fornecido | query não fornecida |

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

Valores permitidos em **Status**: `NÃO EXECUTADO`, `APROVADO`, `FALHOU` ou `BLOQUEADO`.

### RT-INIT — Inicialização, schema e dependências

| ID | Caso | Resultado esperado resumido | Resultado real | Evidência | Status | Bug/repetição |
|---|---|---|---|---|---|---|
| RT-INIT-01 | Start na ordem oficial | `mz_bank ready` somente após schema v2; callbacks/exports disponíveis | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-INIT-02 | Migration inicial e restart idempotente | versões 1/2 únicas; schema e dados preservados | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-INIT-03 | Dependência rígida ausente/parada | readiness falso e erro explícito; nenhuma sessão/operação nova | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-INIT-04 | `bank_card` e contratos reais | item disponível; seis callbacks e exports consumidos sem erro | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-INIT-05 | Parada/retorno do `mz_economy` | ready continua true/degraded; extrato falha; operações continuam; recuperação automática | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-INIT-06 | Restart do `mz_bank` | saldos inalterados; tokens antigos inválidos; nova sessão funciona | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-INIT-07 | Restart do `mz_core` e dependentes | banco fecha; cache reconstrói após ordem oficial; persistência preservada | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-INIT-08 | Ausência de saldo paralelo/legado | nenhuma tabela paralela criada; legado sem escrita | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |

### RT-SESSION — Sessão, canal, estado físico e NUI

| ID | Caso | Resultado esperado resumido | Resultado real | Evidência | Status | Bug/repetição |
|---|---|---|---|---|---|---|
| RT-SESSION-01 | Agência válida e falsa | válida abre; falsa/distante é negada | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-SESSION-02 | ATM catalogado e inexistente | catalogado abre; fora da allowlist é negado | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-SESSION-03 | Canal/coords/phone adulterados | callback físico não alcança phone nem aceita ponto arbitrário | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-SESSION-04 | Token ausente/falso/expirado/de outro jogador | todas as tentativas negadas sem exposição ou saldo alterado | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-SESSION-05 | Afastamento, morte e veículo | sessão/NUI encerradas e token anterior inutilizável | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-SESSION-06 | Troca de personagem e disconnect | identidade anterior não acessível; sessão/rate limit limpos | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-SESSION-07 | Animação, alinhamento e fechamento | cenário inicia/termina; foco e tarefas são liberados | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-SESSION-08 | Slot amarelo/verde/vermelho | estados e transições visuais seguem autenticação/recusa/retirada | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |

### RT-CARD — Emissão, autenticação e revalidação

| ID | Caso | Resultado esperado resumido | Resultado real | Evidência | Status | Bug/repetição |
|---|---|---|---|---|---|---|
| RT-CARD-01 | ATM sem cartão e cartão válido | sem cartão negado; cartão próprio ativo autentica | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-CARD-02 | Cartão de outro titular | `card_owner_mismatch`; nenhuma conta exposta | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-CARD-03 | Cartão bloqueado/revogado | credencial não ativa é negada | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-CARD-04 | Bloqueio durante sessão | próxima chamada invalida sessão e impede operação | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-CARD-05 | Substituição durante sessão | cartão anterior revogado; sessão antiga inválida; novo item ativo | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-CARD-06 | Remoção do item | próxima chamada protegida falha e encerra sessão | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-CARD-07 | Emissão inicial/falha de inventário | item e credencial coerentes; falha não deixa credencial ativa órfã | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |

### RT-CASH — Depósito e saque

| ID | Caso | Resultado esperado resumido | Resultado real | Evidência | Status | Bug/repetição |
|---|---|---|---|---|---|---|
| RT-CASH-01 | Depósito válido | wallet diminui, bank aumenta; total e referência preservados | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-CASH-02 | Saque válido | bank diminui, wallet aumenta; total e referência preservados | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-CASH-03 | Saldo total permitido/insuficiente | limite disponível funciona; insuficiência não altera estado | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-CASH-04 | Decimal, zero, negativo, texto, NaN/infinito | `invalid_amount`; sem saldo/idempotência/ledger | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-CASH-05 | Limite por canal/operação | até 1.000.000 segue fluxo; acima retorna `transaction_limit` | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-CASH-06 | Duplo clique e concorrência | uma movimentação por chave; sem saldo negativo | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-CASH-07 | Reconnect/cache/persistência/ledger | NUI, cache e SQL convergem; referência coincide | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |

### RT-TRANSFER — Transferência entre jogadores

| ID | Caso | Resultado esperado resumido | Resultado real | Evidência | Status | Bug/repetição |
|---|---|---|---|---|---|---|
| RT-TRANSFER-01 | Transferência válida | A debita uma vez; B credita uma vez; mesma `correlationId` | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-TRANSFER-02 | Destinatário inválido/offline e autotransferência | erros estáveis; nenhuma ponta alterada | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-TRANSFER-03 | Taxa e arredondamento | taxa zero no pacote; cenário opcional segue `floor` | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-TRANSFER-04 | Transferências cruzadas | locks determinísticos; sem deadlock ou estado parcial | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-TRANSFER-05 | Concorrência com saldo disputado | somente operações cobertas pelo saldo confirmam | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-TRANSFER-06 | Disconnect de uma ponta | commit inteiro ou nenhuma alteração; estado reconciliável | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-TRANSFER-07 | Falha SQL transacional | duas pontas e idempotência revertem; cache não antecipa commit | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |

### RT-RETRY — Idempotência e resposta ambígua

| ID | Caso | Resultado esperado resumido | Resultado real | Evidência | Status | Bug/repetição |
|---|---|---|---|---|---|---|
| RT-RETRY-01 | Chave ausente/inválida | operação negada antes do core | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-RETRY-02 | Mesma chave e mesmo payload | mesmo resultado/referência; `replayed = true`; um movimento | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-RETRY-03 | Mesma chave e payload conflitante | `idempotency_conflict`; operação original preservada | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-RETRY-04 | Timeout do client depois do commit | retry recupera resultado e não duplica saldo | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-RETRY-05 | Overview/extrato falha após commit | sucesso confirmado e referência permanecem; `refreshError` informa falha | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |
| RT-RETRY-06 | Restart depois do commit/antes da resposta | mesma chave recupera resultado persistido após nova sessão | APROVADO conforme execução manual no FiveM informada pelo usuário | Declaração do usuário; sem anexo adicional | APROVADO | Nenhuma falha ou repetição informada |

## 6. Registro de evidências

| ID do teste | Vídeo/screenshot | Console server | Console F8 | Queries antes/depois | Payload/resposta redigidos | Responsável |
|---|---|---|---|---|---|---|
| RT-INIT-01 a RT-RETRY-06 | não fornecido | não fornecido | não fornecido | não fornecidas | não fornecidos | usuário responsável pela execução manual; identidade não informada |

Tokens, chaves completas, `citizenid`, license e `card_uid` não devem aparecer em evidência pública. Preserve o material integral somente no repositório seguro da rodada e use formas redigidas neste relatório.

## 7. Bugs e correções

| Bug ID | Teste origem | Sintoma/evidência | Causa raiz | Arquivos alterados | Risco | Testes afetados | Estado |
|---|---|---|---|---|---|---|---|
| Nenhum | Todos | nenhuma falha pendente conhecida foi informada | não aplicável | nenhum | não aplicável | nenhum | ENCERRADO |

## 8. Repetições

| Repetição | Bug/teste | Pacote implantado | Casos repetidos | Resultado real | Evidência | Estado |
|---|---|---|---|---|---|---|
| Nenhuma solicitada | nenhum bug informado | não informado | nenhum | todos os 43 casos foram informados como aprovados | declaração do usuário; sem anexo adicional | ENCERRADO |

## 9. Fechamento da rodada

- Total planejado: `43` casos.
- Aprovado: `43`.
- Falhou: `0`.
- Bloqueado: `0`.
- Não executado: `0`.
- Invariantes violados: `0` conhecidas conforme o resultado fornecido.
- Bugs abertos: `0` conhecidos.
- Testes que precisam ser repetidos: nenhum, conforme o resultado fornecido.
- Limitações aceitas: detalhes da instância, versões implantadas, valores das queries, consoles e evidências visuais não foram fornecidos.
- Decisão final: **Fase 1 `[R]` — APROVADA EM RUNTIME**.

Segundo a declaração do usuário após a execução manual no FiveM, depósito, saque e transferência passaram; saldo, cache e persistência permaneceram preservados; callbacks adulterados foram negados; sessões e cartões foram revalidados; animação, NUI e slot foram aprovados; migrations, dependências e controles do legado passaram; e não há falhas pendentes conhecidas.
