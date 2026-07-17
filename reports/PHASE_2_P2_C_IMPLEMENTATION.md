# Fase 2 — Implementação do Lote P2-C

Data: 2026-07-16  
Atualização de compatibilidade CSPRNG: 2026-07-17  
Estado: **P2-C `[S]` — VALIDADO ESTATICAMENTE**  
Runtime MySQL/FiveM: **CONCLUÍDO — 15/15 APROVADOS, 0 FALHAS**

## 1. Diagnóstico e escopo formal

O desenho define o P2-C exclusivamente como:

- geração segura do número e DV;
- criação idempotente da conta pessoal;
- integração ao overview físico autenticado;
- DTO próprio sem identificadores internos;
- testes de concorrência, restart e estados;
- nenhuma mudança no contrato de transferência.

P2-A e P2-B já aprovaram schema v3, DV, readiness e repository read-only em runtime. O P2-C
reutiliza essa fundação e não cria migration, tabela, saldo, ledger ou API de telefone.

## 2. Escopo implementado

### 2.1 Feature flag

`Config.PublicAccount.Enabled` permanece `false`. Para staging, o código server-side reconhece a
convar temporária:

```text
mz_bank_public_account_p2c
```

Sem configuração ou convar explícita, o fluxo atual não cria conta e continua mostrando
`Conta corrente`. A convar não foi adicionada a nenhum arquivo `.cfg`.

### 2.2 Fonte segura e rejeição uniforme

O repository prefere:

```sql
SELECT HEX(RANDOM_BYTES(4));
```

O MySQL documenta `RANDOM_BYTES()` como bytes gerados pelo RNG da biblioteca SSL. O MariaDB
documenta a função como adequada a uso criptográfico e disponível a partir da versão 10.10.0:

- <https://dev.mysql.com/doc/refman/8.0/en/encryption-functions.html>
- <https://mariadb.com/docs/server/reference/sql-functions/secondary-functions/encryption-hashing-and-compression-functions/random_bytes>

O staging real não oferece essa função. Para manter compatibilidade sem reduzir a segurança, foi
adicionado `server/account_rng.js`, exclusivamente server-side, usando `crypto.randomBytes(4)` do
Node incorporado ao FXServer. A documentação oficial classifica a saída como criptograficamente
forte, e o FiveM documenta o suporte a APIs Node em scripts server-side:

- <https://nodejs.org/api/crypto.html#cryptorandombytessize-callback>
- <https://docs.fivem.net/docs/scripting-manual/runtimes/javascript/>

O provider usa somente evento local `on`/`TriggerEvent`, não `onNet`/`RegisterNetEvent`: não existe
input do client, callback NUI ou export. A escolha do backend é memorizada após o primeiro probe.

Os 32 bits são mapeados uniformemente para `1..99.999.999` por rejection sampling. Valores fora
do maior múltiplo inteiro do espaço são descartados e um novo bloco seguro é solicitado. Não existe
fallback para `RAND()`, `math.random`, ID SQL, timestamp, citizenid ou license.

Se SQL e Node não fornecerem exatamente quatro bytes seguros, o startup fica fail-closed quando a
feature estiver ativa. Com a feature desligada, o banco físico continua disponível.

### 2.3 Criação idempotente

O contrato interno implementado é:

```lua
MZBankAccountService.EnsurePersonalAccount(internalIdentity)
```

Ele aceita somente uma tabela interna com `citizenid` já derivado do player server-side. O fluxo:

1. exige feature e runtime seguro prontos;
2. valida o identificador interno sem normalização permissiva;
3. relê `(citizenid, personal)` e devolve conta existente;
4. gera candidato e DV pelo módulo real;
5. tenta um `INSERT` dentro de `MySQL.transaction.await`;
6. em falha, relê o titular para recuperar corrida idempotente;
7. sem titular, consulta a rota exata e repete somente se houve colisão;
8. limita a dez candidatos;
9. retorna `account_number_allocation_failed` após esgotar o limite.

Não foi usado `INSERT IGNORE`. Mensagem SQL e nome de constraint não alcançam client/NUI.

### 2.4 Metadata

A linha nova recebe somente:

```json
{"version":1,"origin":"lazy_authenticated_overview"}
```

Não contém saldo, license, telefone, nome, PIN, token, cartão ou identidade duplicada.

### 2.5 DTO próprio

O DTO retornado ao próprio titular autenticado contém apenas:

```lua
{
  branch = '0001',
  accountNumber = '12345678',
  checkDigit = '7',
  formatted = '0001 / 12345678-7',
  accountType = 'personal',
  accountTypeLabel = 'Conta pessoal',
  status = 'active'
}
```

Proibidos e ausentes: `id`, `citizenid`, license, source, metadata, card UID, saldo e dados de
terceiros.

### 2.6 Overview autenticado

A criação ocorre somente depois de:

- readiness;
- sessão física server-side válida;
- canal com permissão de overview;
- autenticação/cartão conforme política atual;
- posição, ped, morte, veículo e personagem revalidados;
- identidade derivada do cache oficial do `mz_core`.

Quando ativa, a resposta preserva os campos atuais e acrescenta `publicAccount`. O campo legado
`account` recebe o texto formatado para que a NUI atual exiba a rota sem alteração visual extensa.
Com a feature desligada, o retorno antigo permanece igual.

### 2.7 Estados

Foi implementada a matriz interna `CanAccountPerform(status, capability)` para `active`, `blocked`,
`frozen` e `closed`. Neste lote ela é usada somente para leitura própria: `closed` não abre o
overview normal, mas `EnsurePersonalAccount` devolve a mesma rota e nunca cria substituta.

As permissões financeiras da matriz foram modeladas, mas não foram conectadas a depósito, saque ou
transferência porque o escopo formal manda preservar essas operações até os lotes consumidores.

## 3. Arquivos alterados

| Arquivo | Alteração |
|---|---|
| `config.lua` | feature/convar de staging, limites do gerador e mensagens públicas |
| `server/account_identity.lua` | validação da configuração P2-C |
| `server/repository.lua` | CSPRNG SQL e insert transacional da identidade |
| `server/account_rng.js` | fallback CSPRNG interno via `crypto.randomBytes(4)` |
| `server/account_service.lua` | geração, DTO, estados e criação idempotente |
| `server/service.lua` | integração no overview autenticado |
| `server/main.lua` | readiness do CSPRNG quando a feature está ativa |
| `fxmanifest.lua` | carrega o provider Node e o account service somente no servidor |
| `BANK_ROADMAP.md` | P2-C registrado como `[S]` |
| `reports/PHASE_2_P2_C_IMPLEMENTATION.md` | este relatório |
| `reports/PHASE_2_P2_C_RUNTIME_CHECKLIST.md` | roteiro runtime pendente |
| `mz_phone/docs/MZ_BANK_APP_PRODUCTION_AUDIT.md` | estado documental do gate, sem integração phone |

Não foram alterados `mz_core`, `mz_economy`, `mz_inventory`, migrations, schema, client Lua,
callbacks NUI, animação, slot ou arquivos `.cfg`.

## 4. Contratos reais utilizados

- `MZBankBridge.ResolvePlayer(source, false)` para identidade já autenticada;
- `MZBankAccountIdentity.CalculateCheckDigit` e `ValidateRoute`;
- `MZBankRepository.getPublicAccountByOwner` e `getPublicAccountByRoute`;
- `MySQL.scalar.await` e `MySQL.transaction.await` do `oxmysql` já usado pelo projeto;
- `crypto.randomBytes(4)` do runtime Node server-side do FXServer;
- evento local interno `mz_bank:internal:accountRandomBytes`, não registrado para rede;
- constraints reais `uq_mz_bank_accounts_owner_type` e `uq_mz_bank_accounts_route`;
- overview físico e sessão atuais do `MZBankService`;
- saldo continua lido exclusivamente por `MZBankBridge.GetMoney`/`mz_core`.

Nenhum export ou callback novo foi inventado.

## 5. Validações estáticas

### 5.1 Sintaxe

```text
luac -p account_identity.lua: PASS
luac -p repository.lua: PASS
luac -p account_service.lua: PASS
luac -p service.lua: PASS
luac -p main.lua: PASS
luac -p fxmanifest.lua: PASS
node --check html/script.js: PASS
node --check server/account_rng.js: PASS
```

### 5.2 Harness real dos módulos

```text
P2-C harness: PASS
writes=4
idempotent=true
route_retry=true
owner_race=true
closed_reserved=true
dto_safe=true
state_matrix=true
rejection_sampling=true
```

O harness carregou `account_identity.lua` e `account_service.lua` reais e simulou apenas o
repository/MySQL. Foram confirmados:

- rejeição de amostra fora do intervalo uniforme;
- criação e repetição sem segunda escrita;
- colisão de rota seguida de novo candidato;
- concorrente vencedor relido como sucesso idempotente;
- conta closed devolvida sem substituição;
- identidade interna inválida negada;
- DTO restrito à allowlist.
- matriz `active/blocked/frozen/closed` preservada no serviço interno.

Um segundo harness executou a configuração padrão desligada e confirmou:

```text
P2-C disabled fail-closed: PASS
rng_calls=0
writes=0
```

O harness de compatibilidade simulou a ausência de `RANDOM_BYTES()` e confirmou:

```text
secure fallback: PASS
source=node_crypto_random_bytes
sql_probe_calls=1
```

### 5.3 Buscas de segurança

- zero uso executável de `math.random` ou `RAND()` na geração pública;
- zero acesso a `mz_player_accounts` no domínio P2-C;
- zero coluna/campo de saldo no DTO;
- zero evento de rede, callback NUI ou export novo;
- transferência atual continua em `resolveServerIdRecipient` e não foi modificada;
- feature/convar P2-C não está persistida em `.cfg`.

## 6. Decisões e diferenças do desenho

1. O desenho não escolhia uma primitiva concreta. O banco prefere `RANDOM_BYTES(4)` e usa
   `crypto.randomBytes(4)` server-side quando o SQL real não oferece a função; ambos permanecem
   atrás de validação fail-closed e não há fallback fraco.
2. O staging comprovou incompatibilidade com `RANDOM_BYTES()`. O provider Node foi adicionado como
   correção mínima, sem exigir upgrade destrutivo do banco.
3. A feature permanece desligada por padrão e ganhou uma convar temporária para staging.
4. A matriz de estados foi criada, mas somente a capability `read` é aplicada neste lote para não
   alterar transferências antes do P2-F/cutover.
5. Nenhum export `GetOwnPublicAccount` foi criado: o DTO trafega pelo overview já autenticado, que é
   o consumidor formal do P2-C.

## 7. Riscos e testes runtime pendentes

- repetir o startup real e confirmar `random_source=node_crypto_random_bytes`;
- executar criação real com feature ativa;
- validar concorrência contra MySQL real;
- injetar colisão e falha SQL com runner controlado ainda não criado;
- confirmar que refresh, reconnect e restart devolvem a mesma rota;
- testar active/blocked/frozen/closed em staging;
- conferir DTO real na NUI e ausência de identificadores internos;
- comparar wallet/bank/dirty antes e depois;
- executar regressão integral de ATM, agência, cartões e operações atuais;
- desativar a convar após o teste até aprovação runtime.

## 8. Itens explicitamente não implementados

- P2-D backfill, preview, ACE, batches e relatórios;
- P2-E resolução de destinatário, rate limit e `resolutionToken`;
- P2-F transferência por conta pública;
- P2-G cutover da NUI e remoção do server ID;
- aplicação completa dos estados às operações financeiras;
- transferência offline;
- phone, conta empresarial, PIX, QR Code ou produto financeiro;
- saldo, cache financeiro, ledger ou outbox no `mz_bank`.

## 9. Estado final

```text
Fase 2: [~] Em implementação
P2-A: [R] Aprovado em runtime
P2-B: [R] Aprovado em runtime
P2-C: [R] Aprovado em runtime
P2-D e seguintes: NÃO IMPLEMENTADOS
Runtime P2-C: CONCLUÍDO — 15 APROVADOS, 0 FALHAS
Fase 2 completa: NÃO APROVADA
```

Próximo lote recomendado: P2-D, mediante autorização própria. Esta decisão não aprova a Fase 2
completa nem antecipa backfill, resolução pública ou transferência por conta.
