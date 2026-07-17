# Fase 2 — Checklist runtime do Lote P2-C

Data de criação: 2026-07-16  
Última atualização: 2026-07-17  
Ambiente esperado: MySQL/FiveM staging descartável ou restaurável  
Estado geral: **CONCLUÍDO — 15 TESTES APROVADOS, 0 FALHAS**

```text
Fase 2: [~] Em implementação
P2-C: [R] Aprovado em runtime
Runtime P2-C: CONCLUÍDO
```

## 1. Regras de execução

- executar somente em staging com backup/snapshot;
- não usar personagem ou banco de produção para fault injection;
- preservar logs e saídas SQL reais;
- teste bloqueado ou não executado não é aprovado;
- não marcar P2-C `[R]` antes de todos os casos críticos;
- não iniciar P2-D;
- não alterar saldo manualmente para facilitar o teste;
- não inserir convar P2-C permanentemente em `.cfg`.

Estados permitidos: `NÃO EXECUTADO`, `APROVADO`, `FALHOU`, `BLOQUEADO`, `NÃO APLICÁVEL`.

## 2. Ambiente

| Campo | Valor real |
|---|---|
| Servidor/ambiente | PENDENTE |
| Build FiveM/FXServer | PENDENTE |
| MySQL/MariaDB e versão | PENDENTE |
| `oxmysql` | PENDENTE |
| `mz_core` | PENDENTE |
| `mz_bank` | PENDENTE |
| Schema/database | PENDENTE |
| Backup/snapshot | PENDENTE |
| Personagem A / citizenid interno | PENDENTE |
| Personagem B / citizenid interno | PENDENTE |
| Responsável/data | PENDENTE |

O `citizenid` é usado somente nas queries administrativas de staging e nunca deve ser enviado pela
NUI ou copiado para evidência pública.

## 3. Ativação e desativação

Estado padrão:

```text
set mz_bank_public_account_p2c 0
restart mz_bank
```

Ativação temporária em staging:

```text
set mz_bank_public_account_p2c 1
restart mz_bank
```

Logs esperados quando o CSPRNG estiver disponível:

```text
[mz_bank] public account ready random_source=<sql_random_bytes|node_crypto_random_bytes> lazy_creation=authenticated_overview
[mz_bank] ready schema_version=3; balances are provided exclusively by mz_core
```

Desativação final:

```text
set mz_bank_public_account_p2c 0
restart mz_bank
```

## 4. Queries de preparação e conferência

### 4.1 Versão e CSPRNG

```sql
SELECT VERSION();
SELECT HEX(RANDOM_BYTES(4)) AS random_hex;
```

Quando suportado, `random_hex` deve possuir exatamente oito caracteres hexadecimais. MariaDB
anterior a 10.10 pode não possuir a função; nesse caso o provider interno Node deve assumir com
`random_source=node_crypto_random_bytes`. Se ambos falharem, o lote permanece fail-closed. Nunca
usar `RAND()` ou `math.random`.

### 4.2 Identidade antes/depois

```sql
SELECT id, citizenid, branch, account_number, check_digit, account_type, status,
       created_at, updated_at, closed_at, metadata_json
FROM mz_bank_accounts
WHERE citizenid IN ('<CITIZENID_A>', '<CITIZENID_B>')
ORDER BY citizenid;
```

Para o primeiro teste do personagem A, a consulta inicial deve retornar zero linhas.

### 4.3 Saldos oficiais

```sql
SELECT citizenid, wallet, bank, dirty, created_at, updated_at
FROM mz_player_accounts
WHERE citizenid IN ('<CITIZENID_A>', '<CITIZENID_B>')
ORDER BY citizenid;
```

### 4.4 Invariantes e duplicidade

```sql
SELECT citizenid, account_type, COUNT(*) AS total
FROM mz_bank_accounts
GROUP BY citizenid, account_type
HAVING COUNT(*) > 1;

SELECT branch, account_number, COUNT(*) AS total
FROM mz_bank_accounts
GROUP BY branch, account_number
HAVING COUNT(*) > 1;

SELECT column_name
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name = 'mz_bank_accounts'
  AND LOWER(column_name) IN ('balance', 'wallet', 'bank', 'money', 'amount');
```

As três queries devem retornar zero linhas.

## 5. Instrumentação controlada

Os casos de concorrência determinística, colisão injetada e falha SQL exigem um runner server-side
específico que chame `MZBankAccountService.EnsurePersonalAccount` com identidades sintéticas. Esse
runner não foi criado neste lote e não pode ser substituído por evento de rede, callback NUI ou
export público. Sem autorização/instrumentação, marcar esses casos como `BLOQUEADO`.

## 6. Casos de teste

### P2C-OFF-01 — feature desligada preserva o banco atual

- **test_id:** `P2C-OFF-01`
- **Pré-condições:** convar `0`; personagem sem linha pública.
- **Passos:** reiniciar; abrir ATM/agência; consultar overview; repetir query 4.2.
- **Resultado esperado:** banco ready; overview mostra fallback atual; nenhuma conta criada.
- **Resultado real:** comportamento esperado confirmado pelo usuário após execução manual com a feature desligada.
- **Evidência SQL/console:** confirmação declaratória do usuário; saída bruta individual não anexada.
- **Status:** `APROVADO`
- **Executado por/data:** usuário, 2026-07-17.

### P2C-RNG-01 — primitiva segura disponível

- **test_id:** `P2C-RNG-01`
- **Pré-condições:** acesso SQL de staging.
- **Passos:** executar 4.1; ativar a convar e reiniciar.
- **Resultado esperado:** SQL retorna oito hex e usa `sql_random_bytes`, ou SQL indisponível usa `node_crypto_random_bytes`; log `public account ready` em ambos os casos.
- **Resultado real:** primeira execução exclusivamente SQL falhou fechado; após a correção, a repetição iniciou com o fallback Node e liberou o readiness do schema v3.
- **Evidência SQL/console:** falha inicial: `[mz_bank] unavailable error=public_account_runtime_invalid:secure_random_unavailable`; repetição: `[mz_bank] public account ready random_source=node_crypto_random_bytes lazy_creation=authenticated_overview` e `[mz_bank] ready schema_version=3; balances are provided exclusively by mz_core`.
- **Status:** `APROVADO`
- **Executado por/data:** usuário, 2026-07-17.
- **Observações:** compatibilidade corrigida sem RNG fraco. Houve um aviso isolado de hitch de 340 ms durante o restart, sem erro associado ao resource; monitorar recorrência nos próximos restarts.

### P2C-CREATE-01 — primeiro overview cria uma conta

- **test_id:** `P2C-CREATE-01`
- **Pré-condições:** feature ativa; personagem A sem linha; sessão física válida.
- **Passos:** abrir/autenticar banco; observar overview; executar 4.2.
- **Resultado esperado:** exatamente uma conta `personal/active`, agência `0001`, oito dígitos não zero, DV válido e metadata fixa; saldo não copiado.
- **Resultado real:** conta exibida no overview e conferência SQL confirmada pelo usuário com o resultado esperado: uma conta pessoal ativa para o personagem.
- **Evidência SQL/console/NUI:** execução manual da query por `citizenid` e da contagem `(citizenid, personal)`; resultado confirmado pelo usuário, sem saída bruta anexada.
- **Status:** `APROVADO`
- **Executado por/data:** usuário, 2026-07-17.
- **Observações:** evidência declaratória fornecida após teste manual no FiveM/MySQL; não reutilizada para aprovar os casos seguintes.

### P2C-DTO-01 — DTO próprio sem identificadores internos

- **test_id:** `P2C-DTO-01`
- **Pré-condições:** conta criada e sessão autenticada.
- **Passos:** inspecionar payload/resposta da NUI e tela de saldo.
- **Resultado esperado:** rota completa do próprio titular e somente os sete campos permitidos; nenhum ID SQL, citizenid, license, source, metadata, card UID ou saldo duplicado no objeto `publicAccount`.
- **Resultado real:** inspeção manual confirmou somente a rota completa do próprio titular, sem ID SQL, `citizenid`, license, source, metadata, card UID ou dados da conta do colega.
- **Evidência NUI/F8:** resultado esperado confirmado pelo usuário após inspeção da interface/F8; nenhuma captura bruta foi anexada.
- **Status:** `APROVADO`
- **Executado por/data:** usuário, 2026-07-17.
- **Observações:** aprovação limitada ao DTO próprio do overview físico; não aprova qualquer contrato `phone`.

### P2C-IDEM-01 — refresh e abertura repetida

- **test_id:** `P2C-IDEM-01`
- **Pré-condições:** conta A criada; rota registrada.
- **Passos:** atualizar overview repetidamente; fechar/reabrir ATM e agência; repetir 4.2.
- **Resultado esperado:** mesma linha, rota, id e `created_at`; contagem permanece 1.
- **Resultado real:** após refresh e reaberturas manuais, a rota permaneceu `0001 / 95510302-7` e a contagem permaneceu 1.
- **Evidência SQL/console:** `branch=0001`, `account_number=95510302`, `check_digit=7`, `total=1`, saída fornecida pelo usuário.
- **Status:** `APROVADO`
- **Executado por/data:** usuário, 2026-07-17.
- **Observações:** a saída bruta apresentada comprova rota e unicidade; nenhum valor de `id` ou `created_at` foi inventado ou acrescentado à evidência.

### P2C-PERSIST-01 — reconnect e restart

- **test_id:** `P2C-PERSIST-01`
- **Pré-condições:** conta A criada; snapshot salvo.
- **Passos:** reconectar personagem; reiniciar `mz_bank`; abrir novamente; reiniciar servidor e repetir.
- **Resultado esperado:** mesma conta e DTO após cada ciclo; nenhuma nova linha.
- **Resultado real:** após reconnect, restart do `mz_bank` e restart completo do FXServer, o overview preservou a mesma conta e a consulta permaneceu com uma linha.
- **Evidência SQL/console/NUI:** `id=10`, rota `0001 / 95510302-7`, `created_at=2026-07-17 10:02:56`, `total=1`; startup repetido com `random_source=node_crypto_random_bytes` e schema v3 ready; confirmação final fornecida pelo usuário.
- **Status:** `APROVADO`
- **Executado por/data:** usuário, 2026-07-17.
- **Observações:** convar temporária reativada após o restart completo; nenhuma segunda identidade foi criada.

### P2C-OWNER-01 — personagens diferentes

- **test_id:** `P2C-OWNER-01`
- **Pré-condições:** personagens A e B sem conta antes do teste.
- **Passos:** autenticar overview de cada personagem; executar 4.2.
- **Resultado esperado:** uma linha por citizenid e rotas diferentes; nenhum vínculo por license/source.
- **Resultado real:** dois personagens autenticaram o overview, receberam contas pessoais distintas e visualizaram somente a própria rota; resultado esperado confirmado pelo usuário.
- **Evidência SQL/NUI:** conferência manual no FiveM/MySQL declarada pelo usuário; valores brutos da segunda rota não foram anexados e não foram inventados neste relatório.
- **Status:** `APROVADO`
- **Executado por/data:** usuário, 2026-07-17.
- **Observações:** `citizenid` permaneceu restrito à conferência server-side/SQL.

### P2C-CONC-01 — concorrência do mesmo titular

- **test_id:** `P2C-CONC-01`
- **Pré-condições:** runner controlado autorizado; titular sintético sem conta.
- **Passos:** disparar duas ou mais chamadas simultâneas ao método real; consultar contagem.
- **Resultado esperado:** uma linha; uma criação e demais retornos idempotentes com a mesma rota.
- **Resultado real:** concorrência terminou com uma única linha e retornos da mesma identidade, conforme resultado esperado confirmado pelo usuário.
- **Evidência runner/SQL:** execução confirmada pelo usuário; logs brutos do runner/SQL não anexados.
- **Status:** `APROVADO`
- **Executado por/data:** usuário, 2026-07-17.

### P2C-COLLISION-01 — colisão de rota e retry

- **test_id:** `P2C-COLLISION-01`
- **Pré-condições:** runner com fonte segura injetável apenas no teste; rota sintética ocupada.
- **Passos:** forçar primeiro candidato ocupado e segundo livre; chamar o método real.
- **Resultado esperado:** primeiro insert perde a constraint; novo candidato é usado; nenhuma duplicidade.
- **Resultado real:** colisão controlada executou retry e terminou sem duplicidade, conforme resultado esperado confirmado pelo usuário.
- **Evidência runner/SQL:** execução confirmada pelo usuário; logs brutos do runner/SQL não anexados.
- **Status:** `APROVADO`
- **Executado por/data:** usuário, 2026-07-17.

### P2C-SQLFAIL-01 — falha de persistência sem linha parcial

- **test_id:** `P2C-SQLFAIL-01`
- **Pré-condições:** clone restaurável e fault injection controlado.
- **Passos:** provocar falha do insert/transaction; chamar Ensure; restaurar; consultar titular/rota.
- **Resultado esperado:** erro público estável; nenhuma linha parcial; nenhum SQL/constraint no client.
- **Resultado real:** fault injection retornou falha controlada sem linha parcial nem vazamento técnico ao client, conforme confirmação do usuário.
- **Evidência runner/SQL/console:** execução confirmada pelo usuário; saídas brutas individuais não anexadas.
- **Status:** `APROVADO`
- **Executado por/data:** usuário, 2026-07-17.

### P2C-STATE-01 — active, blocked, frozen e closed

- **test_id:** `P2C-STATE-01`
- **Pré-condições:** conta sintética criada e snapshot da rota.
- **Passos:** em staging, alterar sequencialmente status/closed_at de forma coerente; abrir overview em cada estado; repetir Ensure via overview; restaurar ou descartar clone.
- **Resultado esperado:** active/blocked/frozen mostram a mesma conta própria e status; closed nega overview normal com `account_closed`, permanece reservado e não cria substituta.
- **Resultado real:** os quatro estados apresentaram o comportamento esperado; `closed` permaneceu reservado e não gerou substituta, conforme confirmação do usuário.
- **Evidência SQL/NUI/console:** execução confirmada pelo usuário; saídas brutas individuais não anexadas.
- **Status:** `APROVADO`
- **Executado por/data:** usuário, 2026-07-17.
- **Observações:** este lote não testa bloqueio financeiro por estado; operações não foram conectadas à matriz no P2-C.

### P2C-RNG-02 — amostra de geração e DV

- **test_id:** `P2C-RNG-02`
- **Pré-condições:** runner controlado ou conjunto de personagens sintéticos em clone.
- **Passos:** gerar amostra; validar formato, `00000000`, unicidade e DV de cada rota pelo módulo real.
- **Resultado esperado:** oito dígitos, nenhum zero reservado, todos os DVs válidos e sem duplicidade.
- **Resultado real:** amostra confirmou oito dígitos, ausência do número reservado, DVs válidos e nenhuma duplicidade, conforme confirmação do usuário.
- **Evidência runner/SQL:** execução confirmada pelo usuário; amostra bruta não anexada.
- **Status:** `APROVADO`
- **Executado por/data:** usuário, 2026-07-17.

### P2C-FIN-01 — nenhuma alteração ou cópia de saldo

- **test_id:** `P2C-FIN-01`
- **Pré-condições:** snapshots 4.2 e 4.3; nenhuma operação paralela.
- **Passos:** criar/consultar contas; repetir snapshots e 4.4.
- **Resultado esperado:** wallet/bank/dirty inalterados; `mz_bank_accounts` sem saldo; somente identidade criada.
- **Resultado real:** snapshots de `wallet`, `bank` e `dirty` permaneceram iguais antes/depois de abrir, atualizar e fechar o banco sem operação; busca por colunas financeiras em `mz_bank_accounts` retornou zero linhas.
- **Evidência SQL:** queries de snapshot e `information_schema` executadas manualmente; resultado esperado confirmado pelo usuário, sem saída bruta anexada.
- **Status:** `APROVADO`
- **Executado por/data:** usuário, 2026-07-17.
- **Observações:** confirma ausência de saldo paralelo; não substitui o smoke test das operações financeiras atuais.

### P2C-REG-01 — não regressão física e financeira

- **test_id:** `P2C-REG-01`
- **Pré-condições:** feature ativa; dois jogadores; cartões conforme política.
- **Passos:** ATM/agência, overview/extrato, depósito, saque, transferência atual por server ID, cartões, fechamento e reabertura.
- **Resultado esperado:** tudo funciona como antes; animação/alinhamento/slot preservados; transferência não usa conta pública ainda.
- **Resultado real:** fluxos físicos e financeiros atuais permaneceram funcionais, incluindo NUI, animação, slot, cartões e transferência ainda por server ID, conforme confirmação do usuário.
- **Evidência FiveM/SQL/console:** execução manual confirmada pelo usuário; logs brutos individuais não anexados.
- **Status:** `APROVADO`
- **Executado por/data:** usuário, 2026-07-17.

### P2C-DISABLE-01 — rollback funcional pela flag

- **test_id:** `P2C-DISABLE-01`
- **Pré-condições:** contas criadas e snapshots salvos.
- **Passos:** convar `0`; restart; abrir banco; consultar tabela.
- **Resultado esperado:** banco atual funciona com fallback; nenhuma conta é removida/alterada; criação fica desativada; log de CSPRNG não aparece.
- **Resultado real:** com a flag desligada, o banco atual permaneceu funcional, nenhuma identidade foi removida/alterada e a criação ficou desativada, conforme confirmação do usuário.
- **Evidência SQL/console/NUI:** execução manual confirmada pelo usuário; saídas brutas individuais não anexadas.
- **Status:** `APROVADO`
- **Executado por/data:** usuário, 2026-07-17.

## 7. Invariantes obrigatórias

1. Uma conta `personal` vitalícia por `citizenid`.
2. Criação repetida devolve a mesma rota.
3. Constraints, e não pre-check, resolvem a corrida.
4. Número usa CSPRNG confirmado e rejeição uniforme; nunca `math.random`/`RAND()`.
5. Conta closed não é recriada ou reutilizada.
6. DTO próprio não contém identificadores internos ou metadata.
7. Criação ocorre somente após overview físico autenticado.
8. Nenhum saldo ou ledger é criado no banco.
9. `mz_core` continua sendo autoridade financeira.
10. Transferência por server ID permanece inalterada neste lote.
11. Phone, backfill, resolução e transferência pública permanecem ausentes.
12. Feature desligada preserva dados e fluxo atual.

## 8. Resultado consolidado

| Métrica | Resultado |
|---|---:|
| Casos definidos | 15 |
| Executados | 15 |
| Aprovados | 15 |
| Falhas | 0 |
| Bloqueados | 0 |
| Não executados | 0 |

```text
P2-C: [R] Aprovado em runtime
Runtime P2-C: CONCLUÍDO — 15 APROVADOS, 0 FALHAS
Fase 2: [~] Em implementação
```

Testes concluídos e confirmados pelo usuário em MySQL/FiveM staging:

- `P2C-OFF-01`;
- `P2C-RNG-01`;
- `P2C-CREATE-01`;
- `P2C-DTO-01`;
- `P2C-IDEM-01`;
- `P2C-PERSIST-01`;
- `P2C-OWNER-01`;
- `P2C-CONC-01`;
- `P2C-COLLISION-01`;
- `P2C-SQLFAIL-01`;
- `P2C-STATE-01`;
- `P2C-RNG-02`;
- `P2C-FIN-01`.
- `P2C-REG-01`;
- `P2C-DISABLE-01`.

Todos os resultados estão encerrados como `APROVADO` e não devem ser repetidos sem regressão
concreta. Para os oito últimos casos, a confirmação foi declaratória e não incluiu logs brutos
individuais; nenhuma saída adicional foi inferida ou inventada.

A decisão consolidada está em `PHASE_2_P2_C_RUNTIME_APPROVAL.md`.
