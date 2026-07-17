# Identidade bancária pública do mz_bank

## Fonte de verdade

`mz_bank_accounts` armazena somente identidade e estado da conta. Não armazena nem deriva saldo.
Wallet e bank pertencem exclusivamente ao `mz_core` e à persistência `mz_player_accounts`.

## Conta pessoal

- uma conta `personal` vitalícia por `citizenid`;
- agência padrão `0001`;
- número aleatório CSPRNG com oito dígitos, exceto `00000000`;
- dígito verificador módulo 11;
- unicidade por titular/tipo e por agência/número;
- colisão termina em constraint e retry;
- conta `closed` e sua rota nunca são removidas ou reutilizadas.

`citizenid` é uma chave interna server-side e nunca é identidade bancária pública.

## Estados no canal mz_bank

| Estado | Leitura | Depósito/recebimento | Saque/transferência |
|---|---:|---:|---:|
| `active` | sim | sim | sim |
| `blocked` | sim | sim | não |
| `frozen` | sim | não | não |
| `closed` | não no fluxo normal | não | não |

Esses estados limitam o canal do banco. Não alteram saldo diretamente e não representam hold global
para outros domínios que usem o core.

## Criação e backfill

A criação ocorre preguiçosamente no primeiro overview físico autenticado. Repetições e concorrência
devolvem a mesma conta. O backfill administrativo exige ACE, preview, confirmação forte, lotes e
auditoria; apply permanece desligado por padrão e nunca lê ou escreve saldo.

## Resolução e transferência

A NUI envia somente agência, conta e DV. O servidor faz lookup exato, aplica limites e devolve nome
parcial, rota mascarada e `resolutionToken` curto vinculado ao ator, sessão e canal. No commit, origem,
alvo, status, presença online e token são revalidados.

A transferência usa exclusivamente `mz_core:TransferBankBetweenPlayers`, preservando locks,
atomicidade, cache, persistência, idempotência e `correlationId`. Não existe crédito offline por SQL.

## Privacidade

Não existe listagem pública. DTOs client-facing não contêm `citizenid`, license, source, ID SQL,
metadata interna ou segredos de cartão. Rotas inválidas/indisponíveis recebem respostas mínimas e são
protegidas por rate limit, cooldown e auditoria mascarada.

## Limites atuais

- somente ATM e agência;
- destino deve estar online;
- phone, PIX, QR Code e contas empresariais não fazem parte desta fase;
- feature pública ativa por padrão; runners e apply de backfill permanecem desligados por padrão.

