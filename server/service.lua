MZBankService = {}

local Sessions = {}
local RateLimits = {}
local PhoneBusy = {}
local ready = false
local COORDINATE_GRACE_MS = 3000
local INITIAL_POSITION_GRACE_MS = 2000

local function serverValidationDistance()
  return math.max(
    tonumber(Config.ServerValidationDistance) or 7.5,
    tonumber(Config.SessionDistance) or 3.0
  )
end

local CHANNEL_PERMISSIONS = {
  atm = { overview = true, statement = true, withdraw = true, deposit = true, transfer = true },
  branch = { overview = true, statement = true, withdraw = true, deposit = true, transfer = true, cards = true },
  phone = { overview = true, statement = true, transfer = true, cards = true }
}

local function messageFor(errorCode)
  return Config.Locale[errorCode] or Config.Locale.transaction_failed
end

local function response(ok, errorCode, data, message)
  return {
    ok = ok == true,
    error = errorCode,
    message = message or (errorCode and messageFor(errorCode)) or nil,
    data = data
  }
end

local function cloneCoords(coords)
  local coordsType = type(coords)
  if coordsType ~= 'table' and coordsType ~= 'vector3' and coordsType ~= 'vector4' then
    return nil
  end

  local x = tonumber(coords.x or coords[1])
  local y = tonumber(coords.y or coords[2])
  local z = tonumber(coords.z or coords[3])
  if not x or not y or not z then return nil end
  return { x = x, y = y, z = z }
end

local function distance(left, right)
  if not left or not right then return math.huge end
  local dx = (tonumber(left.x) or 0) - (tonumber(right.x) or 0)
  local dy = (tonumber(left.y) or 0) - (tonumber(right.y) or 0)
  local dz = (tonumber(left.z) or 0) - (tonumber(right.z) or 0)
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function getServerPlayerCoords(source)
  local ped = GetPlayerPed(source)
  if not ped or ped <= 0 then return nil end
  local coords = GetEntityCoords(ped)
  if not coords then return nil end
  return { x = coords.x, y = coords.y, z = coords.z }
end

local function rateLimited(source, key, cooldownMs)
  local now = GetGameTimer()
  RateLimits[source] = RateLimits[source] or {}
  local nextAllowed = tonumber(RateLimits[source][key]) or 0
  if now < nextAllowed then return true end
  RateLimits[source][key] = now + math.max(0, tonumber(cooldownMs) or 0)
  return false
end

local function createToken(source, citizenid)
  return ('mzb:%s:%s:%s:%08d'):format(source, citizenid, os.time(), math.random(0, 99999999))
end

local function requiresCard(channel)
  if Config.Card.Enabled ~= true then return false end
  if channel == 'atm' then return Config.Card.RequireAtATM == true end
  if channel == 'branch' then return Config.Card.RequireAtBranch == true end
  return false
end

local function resolvePhysicalContext(source, payload)
  payload = type(payload) == 'table' and payload or {}
  local channel = tostring(payload.channel or ''):lower()
  local requestedCoords = cloneCoords(payload.coords)
  local playerCoords = getServerPlayerCoords(source)
  if not requestedCoords or not playerCoords then return nil, 'too_far' end

  if channel == 'branch' then
    local matched
    for index, branch in ipairs(Config.Branches or {}) do
      local branchCoords = cloneCoords(branch.coords)
      local radius = tonumber(branch.radius) or Config.InteractDistance
      if distance(requestedCoords, branchCoords) <= 0.75
        and distance(playerCoords, branchCoords) <= math.max(radius + 0.5, serverValidationDistance()) then
        matched = {
          channel = channel,
          coords = branchCoords,
          branchIndex = index,
          verifiedPlayerCoords = playerCoords
        }
        break
      end
    end
    if not matched then return nil, 'too_far' end
    return matched
  end

  if channel == 'atm' then
    if distance(playerCoords, requestedCoords) > serverValidationDistance() then return nil, 'too_far' end
    return { channel = channel, coords = requestedCoords, verifiedPlayerCoords = playerCoords }
  end

  return nil, 'channel_forbidden'
end

local function validateSession(source, token, requireAuthentication)
  local session = Sessions[source]
  if not session or tostring(token or '') == '' or session.token ~= token then
    MZBankBridge.Log('bank.session.invalid', source, { error = 'invalid_session' })
    return nil, 'invalid_session'
  end
  if session.expiresAt <= os.time() then
    MZBankBridge.Log('bank.session.expired', source, { channel = session.channel })
    Sessions[source] = nil
    return nil, 'session_expired'
  end
  local identity = MZBankBridge.ResolvePlayer(source, false)
  local currentCitizenId = identity and tostring(identity.citizenid or '') or ''
  if currentCitizenId == '' or currentCitizenId ~= tostring(session.citizenid or '') then
    print(('[mz_bank] session identity mismatch source=%s has_player=%s current=%s expected=%s'):format(
      tostring(source),
      tostring(identity ~= nil),
      currentCitizenId ~= '' and ('***' .. currentCitizenId:sub(-4)) or 'missing',
      session.citizenid and ('***' .. tostring(session.citizenid):sub(-4)) or 'missing'
    ))
    Sessions[source] = nil
    return nil, 'player_not_loaded'
  end
  local sessionAgeMs = GetGameTimer() - (tonumber(session.openedAtMs) or 0)
  local playerCoords = sessionAgeMs >= INITIAL_POSITION_GRACE_MS and getServerPlayerCoords(source) or nil
  if sessionAgeMs < INITIAL_POSITION_GRACE_MS then
    -- A posicao ja foi validada ao criar a sessao. Evita uma leitura divergente
    -- do ped imediatamente no callback automatico que carrega a agencia.
  elseif playerCoords then
    local currentDistance = distance(playerCoords, session.coords)
    session.lastVerifiedCoords = playerCoords
    session.lastCoordCheckAt = GetGameTimer()
    local allowedDistance = serverValidationDistance()
    if currentDistance > allowedDistance then
      print(('[mz_bank] session distance rejected source=%s channel=%s distance=%.2f allowed=%.2f'):format(
        tostring(source),
        tostring(session.channel),
        currentDistance,
        allowedDistance
      ))
      Sessions[source] = nil
      MZBankBridge.Log('bank.session.too_far', source, {
        channel = session.channel,
        distance = currentDistance,
        allowed_distance = allowedDistance
      })
      return nil, 'too_far'
    end
  else
    local elapsed = GetGameTimer() - (tonumber(session.lastCoordCheckAt) or 0)
    if elapsed > COORDINATE_GRACE_MS then
      print(('[mz_bank] session coordinate unavailable source=%s channel=%s elapsed_ms=%s'):format(
        tostring(source),
        tostring(session.channel),
        tostring(elapsed)
      ))
      Sessions[source] = nil
      return nil, 'too_far'
    end
    if Config.Debug then
      print(('[mz_bank] coordinate check deferred source=%s channel=%s elapsed_ms=%s reason=server_ped_unavailable'):format(
        tostring(source),
        tostring(session.channel),
        tostring(elapsed)
      ))
    end
  end
  if requireAuthentication ~= false and session.authenticated ~= true then
    return nil, 'card_required'
  end
  session.expiresAt = os.time() + Config.SessionTimeoutSeconds
  return session
end

local function accountMask(citizenid)
  citizenid = tostring(citizenid or '')
  if #citizenid <= 7 then return citizenid end
  return citizenid:sub(1, 3) .. '***' .. citizenid:sub(-4)
end

local function normalizeStatement(payload)
  local rows = type(payload) == 'table' and payload.rows or {}
  local statement = {}
  for _, row in ipairs(rows or {}) do
    local amount = math.floor(tonumber(row.amount) or 0)
    if tostring(row.direction) == 'out' then amount = -math.abs(amount) end
    statement[#statement + 1] = {
      id = row.transaction_id or row.id,
      type = row.reason or row.category or row.direction,
      description = row.reason or row.category,
      amount = amount,
      balance_after = row.balance_after,
      created_at = row.created_at
    }
  end
  return statement
end

local function findInventoryCard(source, citizenid)
  local rows, inventoryErr = MZBankBridge.GetPlayerInventory(source)
  if not rows then return nil, inventoryErr or 'card_not_found' end

  local ownerMismatch = false
  local statusError
  for _, row in ipairs(rows) do
    if row.item == Config.Card.ItemName then
      local metadata = type(row.metadata) == 'table' and row.metadata or {}
      local owner = tostring(metadata.ownerCitizenId or metadata.owner or '')
      if owner ~= citizenid then
        ownerMismatch = true
      else
        local cardUid = tostring(metadata.cardUid or '')
        local credential = cardUid ~= '' and MZBankRepository.getCard(cardUid) or nil
        if not credential then
          statusError = 'card_invalid'
        elseif tostring(credential.citizenid) ~= citizenid then
          ownerMismatch = true
        elseif credential.status == 'active' then
          return { row = row, metadata = metadata, credential = credential }
        elseif credential.status == 'blocked' then
          statusError = 'card_blocked'
        else
          statusError = 'card_invalid'
        end
      end
    end
  end

  if ownerMismatch then return nil, 'card_owner_mismatch' end
  return nil, statusError or 'card_not_found'
end

local function cardUid()
  return ('MZCARD-%s-%08d'):format(os.time(), math.random(0, 99999999))
end

local function issueCard(source, replacement, identity)
  identity = identity or MZBankBridge.ResolvePlayer(source, false)
  if not identity then return response(false, 'player_not_loaded') end
  local citizenid = identity.citizenid

  local activeCount = MZBankRepository.countActiveCards(citizenid)
  if not replacement and activeCount >= Config.Card.MaxActiveCards then
    return response(false, 'card_invalid')
  end

  local fee = replacement and Config.Card.ReplacementFee or Config.Card.IssueFee
  fee = math.floor(tonumber(fee) or 0)
  local feePaid = false
  if fee > 0 then
    local paid, payErr = MZBankBridge.RemoveMoney(source, 'bank', fee, {
      category = 'bank_branch', reason = replacement and 'card_replacement_fee' or 'card_issue_fee',
      source_resource = 'mz_bank', source_type = 'branch'
    })
    if not paid then return response(false, payErr == 'not_enough_money' and 'not_enough_bank' or 'transaction_failed') end
    feePaid = true
  end


  local function refundFee(reason)
    if not feePaid then return end
    local refunded, refundErr = MZBankBridge.AddMoney(source, 'bank', fee, {
      category = 'bank_branch', reason = 'card_fee_rollback', source_resource = 'mz_bank',
      source_type = 'branch', data = { rollback_reason = reason }
    })
    if not refunded then
      print(('[mz_bank] card fee rollback failed source=%s error=%s'):format(source, tostring(refundErr)))
      MZBankBridge.Log('bank.card.fee_rollback_failed', source, { channel = 'branch', error = refundErr, fee = fee })
    end
  end

  local uid = cardUid()
  local last4 = ('%04d'):format(math.random(0, 9999))
  local issuedAt = os.date('!%Y-%m-%dT%H:%M:%SZ')
  local metadata = {
    ownerCitizenId = citizenid,
    holderName = identity.displayName,
    cardUid = uid,
    last4 = last4,
    issuedAt = issuedAt,
    schemaVersion = 1
  }

  local inserted = MZBankRepository.insertCard(uid, citizenid, last4, { schemaVersion = 1 })
  if not inserted then
    refundFee('credential_insert_failed')
    return response(false, 'database_error')
  end

  local added, addErr = MZBankBridge.AddBankCard(source, metadata)
  if not added then
    MZBankRepository.revokeCard(uid)
    refundFee('inventory_add_failed')
    return response(false, addErr == 'inventory_full' and 'inventory_full' or 'transaction_failed')
  end

  if replacement and Config.Card.InvalidatePreviousOnReplacement == true then
    MZBankRepository.revokeActiveCardsExcept(citizenid, uid)
  end

  MZBankBridge.Log(replacement and 'bank.card.replaced' or 'bank.card.issued', source, {
    channel = 'branch', card_last4 = last4, fee = fee
  })
  return response(true, nil, { cardUid = uid, last4 = last4 }, replacement and Config.Locale.card_replaced or Config.Locale.card_issued)
end

function MZBankService.SetReady(value)
  ready = value == true
end

function MZBankService.OpenSession(source, payload)
  if not ready then return response(false, 'bank_unavailable') end
  if rateLimited(source, 'open', Config.RateLimit.openMs) then
    MZBankBridge.Log('bank.rate_limited', source, { operation = 'open' })
    return response(false, 'rate_limited')
  end
  local identity, loadStateOrErr = MZBankBridge.ResolvePlayer(source, true)
  if not identity then
    print(('[mz_bank] player identity failed source=%s error=%s'):format(
      tostring(source),
      tostring(loadStateOrErr or 'player_not_loaded')
    ))

    local integrationErrors = {
      bank_unavailable = true,
      core_prepare_failed = true,
      core_not_ready = true,
      core_not_ready_timeout = true,
      database_error = true
    }
    return response(false, integrationErrors[loadStateOrErr] and 'bank_unavailable' or 'player_not_loaded')
  end

  local context, contextErr = resolvePhysicalContext(source, payload)
  if not context then
    MZBankBridge.Log('bank.session.denied', source, { channel = payload and payload.channel, error = contextErr })
    return response(false, contextErr)
  end

  local issueResult
  if context.channel == 'branch' and Config.Card.Enabled and Config.Card.AutoIssueOnFirstBranchVisit then
    if MZBankRepository.countActiveCards(identity.citizenid) == 0 then
      issueResult = issueCard(source, false, identity)
    end
  end

  local session = {
    token = createToken(source, identity.citizenid),
    citizenid = identity.citizenid,
    channel = context.channel,
    coords = context.coords,
    lastVerifiedCoords = context.verifiedPlayerCoords,
    lastCoordCheckAt = GetGameTimer(),
    openedAtMs = GetGameTimer(),
    branchIndex = context.branchIndex,
    authenticated = not requiresCard(context.channel),
    expiresAt = os.time() + Config.SessionTimeoutSeconds,
    busy = false
  }
  Sessions[source] = session
  MZBankBridge.Log('bank.session.opened', source, { channel = session.channel })

  return response(true, nil, {
    token = session.token,
    channel = session.channel,
    authenticated = session.authenticated,
    issueMessage = issueResult and issueResult.message or nil,
    issueOk = issueResult and issueResult.ok or nil,
    currencySymbol = Config.CurrencySymbol,
    bankName = Config.BankName
  })
end

function MZBankService.Authenticate(source, token)
  if rateLimited(source, 'data', Config.RateLimit.dataMs) then
    MZBankBridge.Log('bank.rate_limited', source, { operation = 'authenticate' })
    return response(false, 'rate_limited')
  end
  local session, sessionErr = validateSession(source, token, false)
  if not session then return response(false, sessionErr) end

  if requiresCard(session.channel) then
    local card, cardErr = findInventoryCard(source, session.citizenid)
    if not card then
      MZBankBridge.Log('bank.card.denied', source, { channel = session.channel, error = cardErr })
      return response(false, cardErr == 'card_not_found' and 'card_required' or cardErr)
    end
    session.cardUid = card.credential.card_uid
    if session.channel == 'atm' and Config.Card.RequirePinAtATM == true then
      MZBankBridge.Log('bank.pin.unavailable', source, { channel = session.channel })
      return response(false, 'pin_unavailable')
    end
  end

  session.authenticated = true
  return MZBankService.GetAccountOverview(source, { token = token, channel = session.channel })
end

function MZBankService.GetAccountOverview(source, context)
  context = type(context) == 'table' and context or {}
  local channel = tostring(context.channel or 'phone')
  if not CHANNEL_PERMISSIONS[channel] or not CHANNEL_PERMISSIONS[channel].overview then
    return response(false, 'channel_forbidden')
  end
  if channel ~= 'phone' then
    local session, sessionErr = validateSession(source, context.token, true)
    if not session then return response(false, sessionErr) end
  elseif not MZBankBridge.IsPlayerLoaded(source) then
    return response(false, 'player_not_loaded')
  end

  local identity = MZBankBridge.ResolvePlayer(source, false)
  if not identity then return response(false, 'player_not_loaded') end
  local bank, bankErr = MZBankBridge.GetMoney(source, 'bank')
  local wallet = MZBankBridge.GetMoney(source, 'wallet')
  if bank == nil then return response(false, bankErr or 'bank_unavailable') end

  local statementOk, statementOrErr = MZBankBridge.GetStatement(source, Config.StatementLimit)
  return response(true, nil, {
    balance = bank,
    cash = wallet or 0,
    name = identity.displayName,
    account = accountMask(identity.citizenid),
    statement = statementOk and normalizeStatement(statementOrErr) or {},
    statementError = statementOk and false or 'statement_unavailable',
    currencySymbol = Config.CurrencySymbol
  })
end

function MZBankService.Refresh(source, token, channel)
  if rateLimited(source, 'data', Config.RateLimit.dataMs) then
    MZBankBridge.Log('bank.rate_limited', source, { operation = 'overview', channel = channel })
    return response(false, 'rate_limited')
  end
  return MZBankService.GetAccountOverview(source, { token = token, channel = channel })
end

function MZBankService.GetStatement(source, filters, context)
  context = type(context) == 'table' and context or {}
  local channel = tostring(context.channel or 'phone')
  if not CHANNEL_PERMISSIONS[channel] or not CHANNEL_PERMISSIONS[channel].statement then
    return response(false, 'channel_forbidden')
  end
  if channel ~= 'phone' then
    local session, sessionErr = validateSession(source, context.token, true)
    if not session then return response(false, sessionErr) end
  end

  local limit = math.min(math.max(math.floor(tonumber(filters and filters.limit) or Config.StatementLimit), 1), 100)
  local ok, payload = MZBankBridge.GetStatement(source, limit)
  if not ok then return response(false, 'statement_unavailable', { statement = {} }) end
  return response(true, nil, { statement = normalizeStatement(payload) })
end

function MZBankService.ResolveRecipient(source, recipientType, recipientValue)
  recipientType = tostring(recipientType or '')
  recipientValue = tostring(recipientValue or '')
  local targetSource

  if recipientType == 'server_id' then
    targetSource = tonumber(recipientValue)
  elseif recipientType == 'citizenid' then
    targetSource = MZBankBridge.GetSourceByCitizenId(recipientValue)
  else
    return response(false, 'recipient_invalid')
  end

  local targetIdentity = targetSource and MZBankBridge.ResolvePlayer(targetSource, false) or nil
  if not targetIdentity then
    return response(false, 'recipient_offline')
  end
  if tonumber(targetSource) == tonumber(source) then return response(false, 'self_transfer') end

  return response(true, nil, {
    source = targetSource,
    citizenid = targetIdentity.citizenid,
    name = targetIdentity.displayName,
    resolvedFrom = recipientType
  })
end

local function transactionMetadata(session, reason, relatedCitizenId)
  local ref = ('mzbank-%s-%s-%06d'):format(os.time(), GetGameTimer(), math.random(0, 999999))
  return {
    category = session.channel == 'branch' and 'bank_branch' or (reason:find('transfer') and 'bank_transfer' or 'bank_atm'),
    reason = session.channel .. '_' .. reason,
    source_resource = 'mz_bank',
    source_type = session.channel,
    related_citizenid = relatedCitizenId,
    external_ref = ref,
    data = { channel = session.channel, location = session.coords }
  }
end

local function validateAmount(amount)
  amount = math.floor(tonumber(amount) or 0)
  if amount <= 0 then return nil, 'invalid_amount' end
  if Config.MaxTransaction > 0 and amount > Config.MaxTransaction then return nil, 'transaction_limit' end
  return amount
end

local function coreTransactionError(errorCode, insufficientCode)
  if errorCode == 'not_enough_money' then return insufficientCode end
  if errorCode == 'account_busy' then return 'operation_busy' end
  if errorCode == 'database_error' then return 'database_error' end
  return errorCode or 'transaction_failed'
end

local function runOperation(source, token, operation, handler)
  if rateLimited(source, 'operation', Config.RateLimit.operationMs) then
    MZBankBridge.Log('bank.rate_limited', source, { operation = operation })
    return response(false, 'rate_limited')
  end
  local session, sessionErr = validateSession(source, token, true)
  if not session then return response(false, sessionErr) end
  if not (CHANNEL_PERMISSIONS[session.channel] and CHANNEL_PERMISSIONS[session.channel][operation]) then
    return response(false, 'channel_forbidden')
  end
  if session.busy then
    MZBankBridge.Log('bank.operation.busy', source, { channel = session.channel, operation = operation })
    return response(false, 'operation_busy')
  end

  session.busy = true
  local ok, result = pcall(handler, session)
  session.busy = false
  if not ok then
    print(('[mz_bank] operation=%s source=%s failed: %s'):format(operation, source, tostring(result)))
    MZBankBridge.Log('bank.operation.failed', source, { channel = session.channel, operation = operation })
    return response(false, 'transaction_failed')
  end
  return result
end

function MZBankService.Withdraw(source, token, rawAmount)
  local amount, amountErr = validateAmount(rawAmount)
  if not amount then return response(false, amountErr) end
  return runOperation(source, token, 'withdraw', function(session)
    local result = MZBankBridge.TransferBetweenOwnAccounts(source, 'bank', 'wallet', amount, transactionMetadata(session, 'withdraw'))
    if result.ok ~= true then
      return response(false, coreTransactionError(result.error, 'not_enough_bank'))
    end
    MZBankBridge.Log('bank.withdraw', source, { channel = session.channel, amount = amount, transaction_ref = result.transactionRef })
    local overview = MZBankService.GetAccountOverview(source, { token = token, channel = session.channel })
    overview.message = Config.Locale.success
    return overview
  end)
end

function MZBankService.Deposit(source, token, rawAmount)
  local amount, amountErr = validateAmount(rawAmount)
  if not amount then return response(false, amountErr) end
  return runOperation(source, token, 'deposit', function(session)
    local result = MZBankBridge.TransferBetweenOwnAccounts(source, 'wallet', 'bank', amount, transactionMetadata(session, 'deposit'))
    if result.ok ~= true then
      return response(false, coreTransactionError(result.error, 'not_enough_wallet'))
    end
    MZBankBridge.Log('bank.deposit', source, { channel = session.channel, amount = amount, transaction_ref = result.transactionRef })
    local overview = MZBankService.GetAccountOverview(source, { token = token, channel = session.channel })
    overview.message = Config.Locale.success
    return overview
  end)
end

function MZBankService.Transfer(source, recipient, rawAmount, context)
  context = type(context) == 'table' and context or {}
  local amount, amountErr = validateAmount(rawAmount)
  if not amount then return response(false, amountErr) end

  local channel = tostring(context.channel or 'phone')
  if channel == 'phone' then
    if rateLimited(source, 'phone_operation', Config.RateLimit.operationMs) then
      MZBankBridge.Log('bank.rate_limited', source, { operation = 'phone_transfer', channel = 'phone' })
      return response(false, 'rate_limited')
    end
    if PhoneBusy[source] then return response(false, 'operation_busy') end
    PhoneBusy[source] = true

    local resolved = MZBankService.ResolveRecipient(source, recipient.type, recipient.value)
    if not resolved.ok then
      PhoneBusy[source] = nil
      return resolved
    end
    local fee = math.floor(amount * (Config.TransferFeePercent / 100))
    local metadata = {
      category = 'bank_transfer', reason = 'phone_transfer', source_resource = 'mz_bank', source_type = 'phone',
      related_citizenid = resolved.data.citizenid, fee = fee, data = { channel = 'phone' }
    }
    local result = MZBankBridge.TransferBankBetweenPlayers(source, resolved.data.source, amount, metadata)
    PhoneBusy[source] = nil
    if result.ok ~= true then return response(false, coreTransactionError(result.error, 'not_enough_bank')) end
    return response(true, nil, { transactionRef = result.transactionRef, fee = result.fee }, Config.Locale.success)
  end

  return runOperation(source, context.token, 'transfer', function(session)
    local resolved = MZBankService.ResolveRecipient(source, recipient.type, recipient.value)
    if not resolved.ok then return resolved end
    local fee = math.floor(amount * (Config.TransferFeePercent / 100))
    local metadata = transactionMetadata(session, 'transfer', resolved.data.citizenid)
    metadata.fee = fee
    metadata.recipient_reason = session.channel .. '_transfer_received'
    local result = MZBankBridge.TransferBankBetweenPlayers(source, resolved.data.source, amount, metadata)
    if result.ok ~= true then return response(false, coreTransactionError(result.error, 'not_enough_bank')) end

    MZBankBridge.Notify(resolved.data.source, ('Voce recebeu %s%s de %s.'):format(Config.CurrencySymbol, amount, MZBankBridge.GetDisplayName(source)), 'success')
    MZBankBridge.Log('bank.transfer', source, {
      channel = session.channel, amount = amount, fee = fee,
      related_citizenid = resolved.data.citizenid, transaction_ref = result.transactionRef
    })
    local overview = MZBankService.GetAccountOverview(source, { token = context.token, channel = session.channel })
    overview.message = Config.Locale.success
    return overview
  end)
end

function MZBankService.GetCards(source)
  local identity = MZBankBridge.ResolvePlayer(source, false)
  if not identity then return response(false, 'player_not_loaded') end
  return response(true, nil, { cards = MZBankRepository.listCards(identity.citizenid) })
end

function MZBankService.BlockCard(source, cardUidValue)
  local identity = MZBankBridge.ResolvePlayer(source, false)
  if not identity then return response(false, 'player_not_loaded') end
  if not MZBankRepository.blockCard(identity.citizenid, tostring(cardUidValue or '')) then return response(false, 'card_invalid') end
  MZBankBridge.Log('bank.card.blocked', source, { channel = 'branch' })
  return response(true, nil, nil, Config.Locale.card_blocked_success)
end

function MZBankService.RequestReplacementCard(source, context)
  context = type(context) == 'table' and context or {}
  if tostring(context.channel) ~= 'branch' then return response(false, 'channel_forbidden') end
  if not context.token then return response(false, 'invalid_session') end
  local session, err = validateSession(source, context.token, true)
  if not session then return response(false, err) end
  return issueCard(source, true)
end

function MZBankService.CloseSession(source, token, reason)
  local session = Sessions[source]
  if session and (not token or session.token == token) then
    Sessions[source] = nil
    MZBankBridge.Log('bank.session.closed', source, { channel = session.channel, reason = reason or 'client_close' })
  end
  return response(true)
end

function MZBankService.CleanupSource(source)
  Sessions[source] = nil
  RateLimits[source] = nil
  PhoneBusy[source] = nil
end

CreateThread(function()
  while true do
    Wait(5000)
    local now = os.time()
    for source, session in pairs(Sessions) do
      if session.expiresAt <= now then Sessions[source] = nil end
    end
  end
end)
