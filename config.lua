Config = {}

Config.BankName = 'Banco Central'
Config.CurrencySymbol = 'R$'
Config.InteractDistance = 1.5
Config.SessionDistance = 3.0
Config.ServerValidationDistance = 7.5
Config.SessionTimeoutSeconds = 120
Config.InteractKey = 38
-- Limites inteiros por operacao e pelo canal efetivo da sessao. O teto de
-- 1.000.000 preserva o comportamento anterior e fica abaixo do BIGINT do core
-- e do maior inteiro representavel com seguranca pelo runtime Lua/JSON.
Config.TransactionLimits = {
  atm = {
    withdraw = 1000000,
    deposit = 1000000,
    transfer = 1000000
  },
  branch = {
    withdraw = 1000000,
    deposit = 1000000,
    transfer = 1000000
  }
}
-- Nao existe limite diario nesta fase; somente os limites por operacao acima.
Config.DailyTransactionLimit = false
Config.TransferFeePercent = 0
-- A taxa percentual de transferencia, quando maior que zero, e arredondada
-- para baixo ate o inteiro mais proximo e debitada adicionalmente do remetente.
Config.TransferFeeRounding = 'floor'
Config.StatementLimit = 15
Config.Debug = false
Config.DebugAce = 'group.mz_owner'

-- API server-to-server compartilhada. A allowlist autoriza somente o resource
-- chamador; cada operacao continua exigindo uma sessao/capability valida do
-- canal efetivo. O mz_phone fica preparado para a Fase 6, mas nao recebe
-- capacidade phone antecipadamente nesta fase.
Config.SharedAPI = {
  Version = 1,
  AllowedResources = {
    mz_bank = true,
    mz_phone = true
  },
  ResourceChannels = {
    mz_bank = { atm = true, branch = true },
    mz_phone = { phone = true }
  }
}

-- Identidade bancaria publica (Fase 2). A feature aprovada permanece ativa
-- sem depender de convar transitoria apos reboot. A convar e mantida apenas
-- para compatibilidade dos ambientes de staging anteriores.
-- P2-C cria a conta no overview fisico autenticado, P2-D fornece backfill,
-- P2-E/P2-F resolvem e transferem e P2-G conclui o cutover da NUI.
Config.PublicAccount = {
  Enabled = true,
  StagingEnableConvar = 'mz_bank_public_account_p2c',
  DefaultBranch = '0001',
  AccountNumberLength = 8,
  AccountType = 'personal',
  CheckDigitAlgorithm = 'mod11',
  SecureRandomBytes = 4,
  SecureRandomTimeoutMs = 1500,
  AllocationAttempts = 10,
  RandomDrawAttempts = 16,
  MetadataVersion = 1,
  AllowedStatuses = {
    active = true,
    blocked = true,
    frozen = true,
    closed = true
  },
  Resolution = {
    Enabled = true,
    TokenTtlSeconds = 60,
    SessionWindowSeconds = 60,
    SessionMaxAttempts = 5,
    ActorWindowSeconds = 3600,
    ActorMaxAttempts = 20,
    CooldownAfterFailures = 3,
    CooldownBaseSeconds = 2,
    CooldownMaxSeconds = 30,
    MaxActiveTokensPerSource = 20
  },
  Backfill = {
    Enabled = true,
    AllowApply = false,
    ApplyEnableConvar = 'mz_bank_p2d_backfill_apply',
    Ace = 'mz_bank.accounts.backfill',
    Command = 'mz_bank_accounts_backfill',
    DefaultBatchSize = 100,
    MaxBatchSize = 500,
    PreviewMaxAgeSeconds = 1800,
    MaxActivePreviews = 32,
    ConfirmationPhrase = 'APPLY_PUBLIC_ACCOUNT_BACKFILL'
  }
}

Config.Interaction = {
  UseMzInteract = true,
  FallbackMarkers = true,
  DrawDistance = 18.0,
  Marker = {
    enabled = true,
    type = 2,
    size = vector3(0.35, 0.35, 0.35),
    color = { r = 60, g = 130, b = 120, a = 200 },
    rotate = true
  },
  Text = {
    enabled = true,
    label = '[E] Usar atendimento bancario',
    offsetZ = 0.45
  },
  BranchBlip = {
    enabled = true,
    sprite = 108,
    color = 2,
    scale = 0.7,
    shortRange = true,
    label = 'Banco Central'
  }
}

Config.ATM = {
  models = {
    `prop_atm_01`,
    `prop_atm_02`,
    `prop_atm_03`,
    `prop_fleeca_atm`
  },
  -- Catalogo compartilhado, mas validado no servidor. Props de ATM do mapa
  -- normalmente nao sao networked, portanto a autorizacao nao depende de um
  -- entity handle informado pelo client. Mapeamentos customizados devem
  -- acrescentar aqui a coordenada real do novo ATM.
  -- Seed vanilla consultado em: https://docs.felis.gg/banking/config
  catalogMatchDistance = 2.25,
  catalog = {
    vector3(-303.33, -829.73, 32.42),
    vector3(-301.72, -830.01, 32.42),
    vector3(-258.90, -723.44, 33.48),
    vector3(-256.22, -716.04, 33.52),
    vector3(-254.33, -692.47, 33.61),
    vector3(24.48, -945.95, 29.36),
    vector3(5.30, -919.81, 29.56),
    vector3(146.02, -1035.21, 29.34),
    vector3(147.59, -1035.78, 29.34),
    vector3(-1205.73, -324.83, 37.86),
    vector3(-1205.00, -326.34, 37.84),
    vector3(-2959.00, 487.74, 15.46),
    vector3(-2956.85, 487.64, 15.46),
    vector3(1171.50, 2702.57, 38.18),
    vector3(1172.51, 2702.58, 38.17),
    vector3(-712.97, -818.94, 23.73),
    vector3(-710.07, -818.90, 23.73),
    vector3(-660.66, -854.07, 24.49),
    vector3(1138.22, -469.00, 66.73),
    vector3(-537.81, -854.51, 29.29),
    vector3(89.64, 2.46, 68.31),
    vector3(114.41, -776.40, 31.42),
    vector3(111.25, -775.24, 31.44),
    vector3(119.03, -883.73, 31.12),
    vector3(112.63, -819.42, 31.34),
    vector3(-28.03, -724.61, 44.23),
    vector3(-30.24, -723.69, 44.23),
    vector3(-203.89, -861.40, 30.27),
    vector3(296.49, -894.15, 29.23),
    vector3(295.75, -896.07, 29.22),
    vector3(155.85, 6642.89, 31.60),
    vector3(174.14, 6637.89, 31.57),
    vector3(-165.12, 232.69, 94.92),
    vector3(-165.13, 234.76, 94.92),
    vector3(1077.77, -776.54, 58.24),
    vector3(1166.91, -456.08, 66.81),
    vector3(-57.66, -92.64, 57.78),
    vector3(356.95, 173.53, 103.07),
    vector3(238.33, 215.98, 106.29),
    vector3(237.88, 216.92, 106.29),
    vector3(237.46, 217.84, 106.29),
    vector3(236.97, 218.77, 106.29),
    vector3(236.59, 219.70, 106.29),
    vector3(265.84, 213.95, 106.28),
    vector3(265.50, 212.93, 106.28),
    vector3(265.14, 212.03, 106.28),
    vector3(264.80, 211.03, 106.28),
    vector3(264.46, 210.08, 106.28),
    vector3(-821.70, -1081.96, 11.13),
    vector3(-611.90, -704.84, 31.24),
    vector3(-614.56, -704.84, 31.24),
    vector3(-618.24, -706.85, 30.05),
    vector3(-618.24, -708.86, 30.05),
    vector3(-1305.35, -706.44, 25.32),
    vector3(-1570.98, -547.33, 34.96),
    vector3(-1570.05, -546.65, 34.96),
    vector3(-846.74, -340.20, 38.68),
    vector3(-846.28, -341.27, 38.68),
    vector3(-867.67, -186.04, 37.84),
    vector3(-866.66, -187.76, 37.84),
    vector3(-1410.31, -98.79, 52.43),
    vector3(-721.08, -415.48, 34.98),
    vector3(129.23, -1291.13, 29.27),
    vector3(129.68, -1291.91, 29.27),
    vector3(130.12, -1292.68, 29.27),
    vector3(-2975.10, 380.14, 15.00),
    vector3(-3241.23, 997.50, 12.55),
    vector3(-3240.60, 1008.63, 12.83),
    vector3(380.80, 323.40, 103.57),
    vector3(33.20, -1348.26, 29.50),
    vector3(2558.50, 389.48, 108.62),
    vector3(-3040.72, 593.11, 7.91),
    vector3(1735.20, 6410.53, 35.04),
    vector3(1701.27, 6426.48, 32.76),
    vector3(1968.12, 3743.56, 32.34),
    vector3(540.32, 2671.14, 42.16),
    vector3(2683.13, 3286.59, 55.24),
    vector3(1153.67, -326.80, 69.21),
    vector3(-717.61, -915.65, 19.22),
    vector3(-57.00, -1752.12, 29.42),
    vector3(-1827.21, 784.87, 138.30),
    vector3(1702.96, 4933.60, 42.06),
    vector3(-3144.38, 1127.58, 20.86),
    vector3(-1091.45, 2708.58, 18.95),
    vector3(-386.88, 6046.10, 31.50),
    vector3(-95.55, 6457.10, 31.46),
    vector3(-97.32, 6455.41, 31.47),
    vector3(1822.72, 3683.07, 34.28),
    vector3(1686.85, 4815.83, 42.01),
    vector3(2564.51, 2584.76, 38.08),
    vector3(-526.62, -1222.97, 18.45),
    vector3(289.11, -1256.78, 29.44),
    vector3(288.84, -1282.33, 29.64),
    vector3(-1315.75, -834.68, 16.96),
    vector3(-1314.81, -835.96, 16.96),
    vector3(-2072.37, -317.21, 13.32),
    vector3(-1415.91, -211.99, 46.50),
    vector3(-1430.17, -211.06, 46.50),
    vector3(-1286.27, -213.44, 42.45),
    vector3(-1282.52, -210.92, 42.45),
    vector3(-1289.30, -226.84, 42.45),
    vector3(-596.09, -1161.28, 22.32),
    vector3(-594.60, -1161.30, 22.32),
    vector3(-1109.80, -1690.80, 4.38),
    vector3(527.35, -160.72, 57.09),
    vector3(285.55, 143.44, 104.17),
    vector3(-2295.46, 358.09, 174.60),
    vector3(-2294.69, 356.44, 174.60),
    vector3(-2293.92, 354.80, 174.60),
    vector3(2558.77, 350.96, 108.62),
    vector3(-133.05, 6366.54, 31.48),
    vector3(158.63, 234.20, 106.63)
  },
  requireCard = true,
  drawMarker = true,
  discoveryDistance = 35.0,
  discoveryIntervalMs = 1500,
  drawDistance = 12.0,
  pointOffsetZ = 1.0,
  blip = {
    enabled = false,
    sprite = 277,
    color = 2,
    scale = 0.55,
    shortRange = true,
    label = 'Caixa Eletronico'
  }
}

Config.Branches = {
  { coords = vector3(150.266, -1040.203, 29.374), radius = 2.0 },
  { coords = vector3(-1212.980, -330.841, 37.787), radius = 2.0 },
  { coords = vector3(-2962.582, 482.627, 15.703), radius = 2.0 },
  { coords = vector3(1175.062, 2706.639, 38.094), radius = 2.0 },
  { coords = vector3(247.00, 222.58, 105.29), radius = 2.0 }

  
}

Config.Card = {
  Enabled = true,
  ItemName = 'bank_card',
  RequireAtATM = true,
  RequireAtBranch = false,
  AutoIssueOnFirstBranchVisit = true,
  IssueFee = 0,
  ReplacementFee = 250,
  MaxActiveCards = 1,
  RequirePinAtATM = false,
  InvalidatePreviousOnReplacement = true
}

Config.RateLimit = {
  openMs = 1000,
  dataMs = 500,
  operationMs = 1500
}

Config.LegacyMigration = {
  AllowApply = false,
  Ace = 'group.mz_owner',
  Strategy = 'replace_if_official_zero',
  RequiredEnvironment = 'staging',
  PreviewMaxAgeSeconds = 1800,
  ConfirmationPhrase = 'APPLY_REPLACE_IF_OFFICIAL_ZERO'
}

Config.Locale = {
  success = 'Operacao realizada com sucesso.',
  player_not_loaded = 'Seu personagem ainda nao foi carregado.',
  bank_unavailable = 'O servico bancario esta indisponivel.',
  public_account_unavailable = 'Nao foi possivel carregar sua conta bancaria.',
  resolution_unavailable = 'A confirmacao do destinatario esta indisponivel.',
  invalid_resolution_token = 'A confirmacao do destinatario expirou ou nao e valida.',
  account_blocked = 'Sua conta bancaria esta bloqueada para transferencias.',
  account_frozen = 'Sua conta bancaria esta congelada para movimentacoes.',
  account_number_allocation_failed = 'Nao foi possivel gerar o numero da conta agora.',
  account_closed = 'Esta conta bancaria esta encerrada.',
  invalid_session = 'Sessao bancaria invalida.',
  session_expired = 'Sua sessao bancaria expirou.',
  too_far = 'Voce se afastou do ponto de atendimento.',
  invalid_ped = 'Nao foi possivel validar seu personagem.',
  player_dead = 'O atendimento nao esta disponivel enquanto voce estiver morto.',
  vehicle_forbidden = 'Saia do veiculo para usar o atendimento bancario.',
  atm_invalid = 'Este caixa eletronico nao esta autorizado.',
  card_required = 'Insira um cartao bancario valido.',
  card_not_found = 'Cartao bancario nao encontrado.',
  card_invalid = 'Este cartao nao e valido.',
  card_blocked = 'Este cartao esta bloqueado.',
  card_owner_mismatch = 'Este cartao pertence a outro titular.',
  pin_unavailable = 'A autenticacao por PIN ainda nao esta habilitada com seguranca.',
  invalid_amount = 'Valor invalido.',
  transaction_limit = 'O valor excede o limite por operacao.',
  idempotency_required = 'Nao foi possivel identificar esta operacao com seguranca.',
  invalid_idempotency_key = 'A identificacao desta operacao e invalida.',
  idempotency_conflict = 'Esta identificacao ja pertence a outra operacao.',
  not_enough_bank = 'Saldo bancario insuficiente.',
  not_enough_wallet = 'Dinheiro em especie insuficiente.',
  recipient_invalid = 'Destinatario invalido.',
  recipient_not_found = 'Destinatario nao encontrado.',
  recipient_offline = 'O destinatario precisa estar online.',
  recipient_unavailable = 'O destinatario esta indisponivel.',
  self_transfer = 'Voce nao pode transferir para si mesmo.',
  operation_busy = 'Aguarde a operacao atual terminar.',
  rate_limited = 'Aguarde um instante antes de tentar novamente.',
  inventory_full = 'Nao ha espaco ou peso disponivel no inventario.',
  statement_unavailable = 'O extrato esta temporariamente indisponivel.',
  database_error = 'Falha de persistencia bancaria.',
  transaction_failed = 'Nao foi possivel concluir a operacao.',
  channel_forbidden = 'Esta operacao nao e permitida neste canal.',
  api_forbidden = 'Este servico nao pode acessar a API bancaria.',
  api_version_required = 'A versao da API bancaria e obrigatoria.',
  api_version_unsupported = 'Esta versao da API bancaria nao e suportada.',
  operation_not_found = 'O resultado desta operacao nao foi encontrado.',
  invalid_operation = 'A operacao informada nao e valida.',
  card_issued = 'Seu primeiro cartao bancario foi emitido.',
  card_replaced = 'A segunda via do cartao foi emitida.',
  card_blocked_success = 'Cartao bloqueado com sucesso.'
}
