# Fase 2 — Checklist runtime do Lote P2-G

Data de criação: 2026-07-17  
Ambiente esperado: FiveM staging com dois personagens online  
Estado geral: **APROVADO**

```text
P2-G: [R] Aprovado em runtime
P2-G runtime: APROVADO
Fase 2: [~] Em implementação
```

Resultado registrado em 2026-07-17 a partir da confirmação fornecida pelo usuário após execução
manual integral no FiveM. Não foram fornecidos anexos adicionais de console, SQL ou captura.

## 1. Preparação

- manter os runners P2-B/P2-D/P2-E/P2-F desligados;
- manter apply de backfill desligado;
- habilitar a identidade pública P2-C;
- usar dois personagens online, cada um com conta pública ativa e saldo conhecido;
- registrar branch/conta/DV dos dois personagens sem registrar `citizenid` na evidência visual;
- capturar saldo/cache/persistência e ledger antes da transferência real.

Comandos recomendados:

```text
set mz_bank_p2b_runtime_runner 0
set mz_bank_p2d_runtime_runner 0
set mz_bank_p2e_runtime_runner 0
set mz_bank_p2f_runtime_runner 0
set mz_bank_p2f_runtime_allow_transfer 0
set mz_bank_p2d_backfill_apply 0
set mz_bank_public_account_p2c 1
restart mz_bank
```

Estados permitidos: `NÃO EXECUTADO`, `APROVADO`, `FALHOU`, `BLOQUEADO`, `NÃO APLICÁVEL`.

Em cada caso registrar: resultado real, console, evidência visual/SQL pertinente, executor, data e
observações. Não aprovar por inferência.

## 2. Casos

### P2G-INIT-01 — inicialização e fluxo físico

- **Pré-condições:** configuração acima aplicada.
- **Passos:** reiniciar `mz_bank`; abrir ATM e agência.
- **Esperado:** ready schema 3; identidade pública ready; nenhuma mensagem de indisponibilidade.
- **Resultado real:** aprovado manualmente no FiveM conforme resultado fornecido pelo usuário.
- **Evidência:** console e captura de abertura.
- **Status:** `APROVADO`

### P2G-UI-01 — campos e teclado

- **Passos:** abrir Transferência; alternar soft keys Agência/Conta/Dígito/Valor; digitar, apagar e limpar.
- **Esperado:** não existe server ID; agência inicia `0001`; limites visuais 4/8/1; valor permanece inteiro; layout legível.
- **Resultado real:** aprovado manualmente no FiveM conforme resultado fornecido pelo usuário.
- **Evidência:** captura da tela.
- **Status:** `APROVADO`

### P2G-RESOLVE-01 — destinatário válido

- **Passos:** informar rota exata do personagem B e valor pequeno; selecionar Continuar.
- **Esperado:** confirmação mostra nome parcial e conta mascarada; nenhum identificador interno aparece.
- **Resultado real:** aprovado manualmente no FiveM conforme resultado fornecido pelo usuário.
- **Evidência:** tela de confirmação e console sem PII.
- **Status:** `APROVADO`

### P2G-RESOLVE-02 — rota inválida e antienumeração

- **Passos:** testar formatos incompletos, DV incorreto e rota inexistente.
- **Esperado:** formatos locais são negados; rotas não disponíveis retornam resposta uniforme; zero saldo alterado.
- **Resultado real:** aprovado manualmente no FiveM conforme resultado fornecido pelo usuário.
- **Evidência:** mensagens e snapshots.
- **Status:** `APROVADO`

### P2G-PRIV-01 — payload adulterado

- **Passos:** adulterar requests NUI adicionando `source`, `citizenid`, `targetId`, `recipientValue`, `channel`, `accountType` e IDs internos.
- **Esperado:** campos extras não alcançam os DTOs server-side; sessão/token definem ator e canal; nenhum identificador interno volta à NUI.
- **Resultado real:** aprovado manualmente no FiveM conforme resultado fornecido pelo usuário.
- **Evidência:** inspeção controlada/logs.
- **Status:** `APROVADO`

### P2G-CONFIRM-01 — corrigir e cancelar

- **Passos:** resolver B; usar Corrigir; mudar um campo; resolver novamente; cancelar e voltar ao menu.
- **Esperado:** preview anterior não é reutilizado; nenhuma transferência ocorre; sessão e NUI permanecem estáveis.
- **Resultado real:** aprovado manualmente no FiveM conforme resultado fornecido pelo usuário.
- **Evidência:** saldo/ledger inalterados.
- **Status:** `APROVADO`

### P2G-CONFIRM-02 — token expirado/falso/outro jogador

- **Passos:** aguardar TTL; confirmar; repetir com token falso e token obtido pelo outro jogador.
- **Esperado:** todos negados sem movimentação; usuário retorna à correção quando aplicável.
- **Resultado real:** aprovado manualmente no FiveM conforme resultado fornecido pelo usuário.
- **Evidência:** console, resposta e saldos.
- **Status:** `APROVADO`

### P2G-TRANSFER-01 — transferência confirmada

- **Passos:** resolver B; conferir dados; confirmar uma transferência pequena.
- **Esperado:** remetente debita exatamente valor+taxa; B credita valor; core confirma; NUI exibe comprovante.
- **Resultado real:** aprovado manualmente no FiveM conforme resultado fornecido pelo usuário.
- **Evidência:** saldos/cache/persistência/ledger e `correlationId`.
- **Status:** `APROVADO`

### P2G-TRANSFER-02 — duplo clique e replay

- **Passos:** confirmar rapidamente duas vezes; repetir após simular perda de resposta quando possível.
- **Esperado:** somente uma movimentação; replay recupera a mesma referência; conflito de payload não movimenta.
- **Resultado real:** aprovado manualmente no FiveM conforme resultado fornecido pelo usuário.
- **Evidência:** ledger, idempotência, saldos e referência.
- **Status:** `APROVADO`

### P2G-TRANSFER-03 — saldo insuficiente e valores inválidos

- **Passos:** testar zero, negativo/decimal/texto por adulteração e valor maior que saldo/limite.
- **Esperado:** todos negados antes de qualquer commit; token segue a política P2-F; saldos intactos.
- **Resultado real:** aprovado manualmente no FiveM conforme resultado fornecido pelo usuário.
- **Evidência:** respostas e snapshots.
- **Status:** `APROVADO`

### P2G-TARGET-01 — self, offline e estados

- **Passos:** testar própria conta, B offline e contas B `blocked`, `frozen` e `closed` em staging.
- **Esperado:** resposta mínima/uniforme; nenhuma transferência ou vazamento; restaurar estado ao fim.
- **Resultado real:** aprovado manualmente no FiveM conforme resultado fornecido pelo usuário.
- **Evidência:** SQL de estado, respostas e saldos.
- **Status:** `APROVADO`

### P2G-RECEIPT-01 — comprovante seguro

- **Passos:** concluir operação; conferir comprovante e extrato.
- **Esperado:** valor, nome parcial, rota mascarada e referência oficial corretos; sem citizenid/source/ID SQL; extrato registra saída no padrão `-R$`.
- **Resultado real:** aprovado manualmente no FiveM conforme resultado fornecido pelo usuário.
- **Evidência:** captura e ledger.
- **Status:** `APROVADO`

### P2G-REG-01 — ATM, animação e slot

- **Passos:** abrir ATM, inserir cartão, transferir/cancelar, afastar/morrer/entrar em veículo e fechar.
- **Esperado:** alinhamento e animação preservados; slot amarelo/verde/vermelho correto; sessão encerra e NUI fecha.
- **Resultado real:** aprovado manualmente no FiveM conforme resultado fornecido pelo usuário.
- **Evidência:** vídeo/capturas e console.
- **Status:** `APROVADO`

### P2G-REG-02 — agência e operações anteriores

- **Passos:** abrir agência; consultar saldo/extrato; executar depósito e saque pequenos; transferir por conta pública.
- **Esperado:** todas as operações funcionam nos serviços oficiais; NUI e fechamento sem regressão.
- **Resultado real:** aprovado manualmente no FiveM conforme resultado fornecido pelo usuário.
- **Evidência:** saldos, ledger e console.
- **Status:** `APROVADO`

### P2G-RESTART-01 — limpeza e restart

- **Passos:** deixar preview aberto; disconnect/reconnect; restart `mz_bank`; tentar reutilizar token; abrir novamente.
- **Esperado:** intents antigas são limpas; token não reutiliza; resource ready; saldos e identidade permanecem intactos.
- **Resultado real:** aprovado manualmente no FiveM conforme resultado fornecido pelo usuário.
- **Evidência:** console, SQL e saldos.
- **Status:** `APROVADO`

## 3. Invariantes

1. NUI nunca envia/recebe citizenid, source, license ou ID SQL.
2. Server ID não é conta nem alternativa de transferência.
3. O token fica vinculado ao ator, sessão e canal e é revalidado no commit.
4. Somente o `mz_core` altera wallet/bank e persiste `mz_player_accounts`.
5. `mz_bank_accounts` não contém saldo.
6. Duplo clique/replay não duplica movimentação.
7. Destino permanece online nesta fase.
8. ATM/agência, animação, alinhamento, slot, saque, depósito e extrato não regridem.
9. Phone, P2-H, PIX, QR Code e transferência offline não são antecipados.

## 4. Consolidado

| Métrica | Resultado |
|---|---:|
| Casos definidos | 15 |
| Executados | 15 |
| Aprovados | 15 |
| Falhas | 0 |
| Bloqueados | 0 |
| Não executados | 0 |

```text
P2-G runtime: APROVADO
P2-G: [R] Aprovado em runtime
Fase 2: [~] Em implementação
```

Os gates do P2-G foram registrados como aprovados a partir do resultado fornecido pelo usuário. O
próximo passo permitido é somente o P2-H; a Fase 2 ainda não está aprovada integralmente.
