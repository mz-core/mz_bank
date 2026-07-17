# Fase 2 — Aprovação runtime do Lote P2-C

Data: 2026-07-17  
Ambiente: MySQL/FiveM staging  
Fonte dos resultados: usuário, após execução dos testes runtime

## 1. Resultado

```text
P2-C: [R] Aprovado em runtime
Fase 2: [~] Em implementação
P2-D e seguintes: NÃO IMPLEMENTADOS
```

| Métrica | Resultado |
|---|---:|
| Casos definidos | 15 |
| Executados | 15 |
| Aprovados | 15 |
| Falhas | 0 |
| Bloqueados | 0 |
| Não executados | 0 |

## 2. Evidências fornecidas

Foram fornecidas diretamente durante a execução:

- falha inicial do SQL CSPRNG e repetição aprovada com `node_crypto_random_bytes`;
- readiness do `mz_bank` com schema v3;
- criação da conta `0001 / 95510302-7`;
- unicidade com `total=1`;
- persistência da linha `id=10`, inclusive após reconnect e restarts;
- ausência de identificadores internos no DTO observado;
- ausência de alteração em wallet/bank/dirty e ausência de saldo em `mz_bank_accounts`.

O usuário confirmou posteriormente que os oito casos restantes também foram executados e tiveram
o resultado esperado. As saídas brutas individuais desses oito casos não foram anexadas; o
relatório registra somente a confirmação fornecida e não cria logs, valores ou evidências extras.

## 3. Invariantes confirmadas

- uma conta pessoal por `citizenid`;
- criação repetida e concorrente não duplica identidade;
- colisão usa retry limitado;
- falha SQL não deixa linha parcial;
- números têm oito dígitos, DV válido e geração CSPRNG;
- conta closed permanece reservada e não é substituída;
- DTO próprio não expõe `citizenid`, ID SQL, license, source ou metadata;
- `mz_bank_accounts` não contém saldo;
- wallet/bank/dirty continuam sob autoridade exclusiva do `mz_core`;
- ATM, agência, NUI, animação, slot, cartões e operações atuais não regrediram;
- transferência continua por server ID neste lote;
- feature desligada preserva as identidades e o fluxo anterior.

## 4. Limitações preservadas

- P2-D backfill não foi implementado;
- resolução privada e `resolutionToken` não foram implementados;
- transferência por conta pública e cutover da NUI não foram implementados;
- não existe transferência offline;
- não existe integração `phone`, conta empresarial, PIX ou QR Code;
- esta aprovação não aprova a Fase 2 completa.

## 5. Decisão final

```text
P2-C: [R] APROVADO EM RUNTIME
15 aprovados
0 falhas
0 bloqueados
Fase 2: [~] EM IMPLEMENTAÇÃO
```

Próximo lote recomendado: P2-D, somente mediante autorização própria.
