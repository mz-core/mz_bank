Config = {}

Config.BankName = 'Banco Central'
Config.CurrencySymbol = '$'
Config.InteractDistance = 1.5
Config.SessionDistance = 3.0
Config.ServerValidationDistance = 7.5
Config.SessionTimeoutSeconds = 120
Config.InteractKey = 38
Config.MaxTransaction = 1000000
Config.TransferFeePercent = 0
Config.StatementLimit = 15
Config.Debug = false
Config.DebugAce = 'group.mz_owner'

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
  { coords = vector3(1175.062, 2706.639, 38.094), radius = 2.0 }
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
  Strategy = 'replace_if_official_zero'
}

Config.Locale = {
  success = 'Operacao realizada com sucesso.',
  player_not_loaded = 'Seu personagem ainda nao foi carregado.',
  bank_unavailable = 'O servico bancario esta indisponivel.',
  invalid_session = 'Sessao bancaria invalida.',
  session_expired = 'Sua sessao bancaria expirou.',
  too_far = 'Voce se afastou do ponto de atendimento.',
  card_required = 'Insira um cartao bancario valido.',
  card_not_found = 'Cartao bancario nao encontrado.',
  card_invalid = 'Este cartao nao e valido.',
  card_blocked = 'Este cartao esta bloqueado.',
  card_owner_mismatch = 'Este cartao pertence a outro titular.',
  pin_unavailable = 'A autenticacao por PIN ainda nao esta habilitada com seguranca.',
  invalid_amount = 'Valor invalido.',
  transaction_limit = 'O valor excede o limite por operacao.',
  not_enough_bank = 'Saldo bancario insuficiente.',
  not_enough_wallet = 'Dinheiro em especie insuficiente.',
  recipient_invalid = 'Destinatario invalido.',
  recipient_not_found = 'Destinatario nao encontrado.',
  recipient_offline = 'O destinatario precisa estar online.',
  self_transfer = 'Voce nao pode transferir para si mesmo.',
  operation_busy = 'Aguarde a operacao atual terminar.',
  rate_limited = 'Aguarde um instante antes de tentar novamente.',
  inventory_full = 'Nao ha espaco ou peso disponivel no inventario.',
  statement_unavailable = 'O extrato esta temporariamente indisponivel.',
  database_error = 'Falha de persistencia bancaria.',
  transaction_failed = 'Nao foi possivel concluir a operacao.',
  channel_forbidden = 'Esta operacao nao e permitida neste canal.',
  card_issued = 'Seu primeiro cartao bancario foi emitido.',
  card_replaced = 'A segunda via do cartao foi emitida.',
  card_blocked_success = 'Cartao bloqueado com sucesso.'
}
