MZBankService = {}

local Sessions = {}
local RateLimits = {}
local ready = false
local COORDINATE_GRACE_MS = 3000
local OPEN_STATE_RETRY_MS = 250

local function serverValidationDistance()
  return math.max(
    tonumber(Config.ServerValidationDistance) or 7.5,
    tonumber(Config.SessionDistance) or 3.0
  )
end

local CHANNEL_PERMISSIONS = {
  atm = { overview = true, statement = true, withdraw = true, deposit = true, transfer = true },
  branch = { overview = true, statement = true, withdraw = true, deposit = true, transfer = true, cards = true }
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

local function getServerPlayerState(source)
  local pedOk, ped = pcall(GetPlayerPed, tostring(source))
  if not pedOk then return nil, 'invalid_ped', 'get_player_ped_failed' end
  if not ped or ped <= 0 then return nil, 'invalid_ped', 'ped_missing' end

  local coordsOk, coords = pcall(GetEntityCoords, ped)
  if not coordsOk then return nil, 'invalid_ped', 'get_entity_coords_failed' end
  if not coords or tonumber(coords.x) == nil or tonumber(coords.y) == nil or tonumber(coords.z) == nil then
    return nil, 'invalid_ped', 'coords_missing'
  end

  local healthOk, health = pcall(GetEntityHealth, ped)
  if not healthOk then return nil, 'invalid_ped', 'get_entity_health_failed' end
  health = tonumber(health)
  if not health then return nil, 'invalid_ped', 'health_missing' end
  if health <= 0 then return nil, 'player_dead', 'health_zero' end

  local vehicleOk, vehicle = pcall(GetVehiclePedIsIn, ped, false)
  if not vehicleOk then return nil, 'invalid_ped', 'get_vehicle_ped_is_in_failed' end
  vehicle = tonumber(vehicle)
  if vehicle == nil then return nil, 'invalid_ped', 'vehicle_state_missing' end
  if vehicle ~= 0 then return nil, 'vehicle_forbidden', 'player_in_vehicle' end

  return {
    ped = ped,
    coords = { x = coords.x, y = coords.y, z = coords.z }
  }
end

local function getOpeningPlayerState(source)
  local attempts = math.max(1, math.floor(COORDINATE_GRACE_MS / OPEN_STATE_RETRY_MS) + 1)
  local state, stateErr, stateDetail
  for attempt = 1, attempts do
    state, stateErr, stateDetail = getServerPlayerState(source)
    if state or stateErr ~= 'invalid_ped' then return state, stateErr, stateDetail end
    if attempt < attempts then Wait(OPEN_STATE_RETRY_MS) end
  end
  return nil, stateErr or 'invalid_ped', stateDetail or 'unknown'
end

local function resolveKnownAtm(requestedCoords)
  local tolerance = math.max(0.1, tonumber(Config.ATM.catalogMatchDistance) or 2.25)
  for index, entry in ipairs(Config.ATM.catalog or {}) do
    local knownCoords = cloneCoords(type(entry) == 'table' and entry.coords or entry)
    if knownCoords and distance(requestedCoords, knownCoords) <= tolerance then
      return {
        id = type(entry) == 'table' and entry.id or index,
        coords = knownCoords
      }
    end
  end
  return nil
end

local function rateLimited(source, key, cooldownMs)
  local now = GetGameTimer()
  RateLimits[source] = RateLimits[source] or {}
  local nextAllowed = tonumber(RateLimits[source][key]) or 0
  if now < nextAllowed then return true end
  RateLimits[source][key] = now + math.max(0, tonumber(cooldownMs) or 0)
  return false
end

local function operationRateLimited(source, idempotencyKey, cooldownMs)
  local now = GetGameTimer()
  RateLimits[source] = RateLimits[source] or {}
  local state = RateLimits[source].operation
  if type(state) == 'table' and state.idempotencyKey == idempotencyKey then
    return false
  end
  local nextAllowed = type(state) == 'table' and tonumber(state.nextAllowed) or 0
  if now < nextAllowed then return true end
  RateLimits[source].operation = {
    nextAllowed = now + math.max(0, tonumber(cooldownMs) or 0),
    idempotencyKey = idempotencyKey
  }
  return false
end

local TOKEN_ALPHABET = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

local function tokenExists(candidate)
  for _, session in pairs(Sessions) do
    if session.token == candidate then return true end
  end
  return false
end

local function createToken()
  for _ = 1, 10 do
    local buffer = {}
    for index = 1, 48 do
      local offset = math.random(1, #TOKEN_ALPHABET)
      buffer[index] = TOKEN_ALPHABET:sub(offset, offset)
    end
    local candidate = table.concat(buffer)
    if not tokenExists(candidate) then return candidate end
  end
  error('unable to allocate unique bank session token')
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
  if not requestedCoords then return nil, channel == 'atm' and 'atm_invalid' or 'too_far' end

  local playerState, stateErr, stateDetail = getOpeningPlayerState(source)
  if not playerState then return nil, stateErr, stateDetail end
  local playerCoords = playerState.coords

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
    local knownAtm = resolveKnownAtm(requestedCoords)
    if not knownAtm then return nil, 'atm_invalid' end
    if distance(playerCoords, knownAtm.coords) > serverValidationDistance() then return nil, 'too_far' end
    return {
      channel = channel,
      coords = knownAtm.coords,
      atmId = knownAtm.id,
      verifiedPlayerCoords = playerCoords
    }
  end

  return nil, 'channel_forbidden'
end

local findInventoryCard

local function validateSession(source, token, requireAuthentication)
  if not ready then return nil, 'bank_unavailable' end
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
  local playerState, stateErr, stateDetail = getServerPlayerState(source)
  if not playerState then
    local elapsed = GetGameTimer() - (tonumber(session.lastCoordCheckAt) or 0)
    if stateErr ~= 'invalid_ped' or elapsed > COORDINATE_GRACE_MS then
      Sessions[source] = nil
      MZBankBridge.Log('bank.session.physical_state_denied', source, {
        channel = session.channel,
        error = stateErr or 'invalid_ped',
        detail = stateDetail,
        elapsed_ms = elapsed
      })
      return nil, stateErr or 'invalid_ped'
    end
    if Config.Debug then
      print(('[mz_bank] physical state check deferred source=%s channel=%s elapsed_ms=%s'):format(
        tostring(source), tostring(session.channel), tostring(elapsed)
      ))
    end
  else
    local playerCoords = playerState.coords
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
  end
  if requireAuthentication ~= false and session.authenticated ~= true then
    return nil, 'card_required'
  end
  if requireAuthentication ~= false and requiresCard(session.channel) then
    local card, cardErr = findInventoryCard(source, session.citizenid, session.cardUid)
    if not card then
      Sessions[source] = nil
      MZBankBridge.Log('bank.card.session_invalidated', source, {
        channel = session.channel,
        card_uid = session.cardUid,
        error = cardErr or 'card_invalid'
      })
      return nil, cardErr or 'card_invalid'
    end
  end
  session.expiresAt = os.time() + Config.SessionTimeoutSeconds
  return session
end

local function normalizeStatement(payload)
  local rows = type(payload) == 'table' and payload.rows or {}
  local statement = {}
  for _, row in ipairs(rows or {}) do
    local amount = math.floor(tonumber(row.amount) or 0)
    if tostring(row.direction) == 'out' then amount = -math.abs(amount) end
    statement[#statement + 1] = {
      type = row.reason or row.category or row.direction,
      description = row.reason or row.category,
      amount = amount,
      balance_after = row.balance_after,
      created_at = row.created_at
    }
  end
  return statement
end

findInventoryCard = function(source, citizenid, expectedCardUid)
  local rows, inventoryErr = MZBankBridge.GetPlayerInventory(source)
  if not rows then return nil, inventoryErr or 'card_not_found' end

  expectedCardUid = tostring(expectedCardUid or '')
  local ownerMismatch = false
  local statusError
  for _, row in ipairs(rows) do
    if row.item == Config.Card.ItemName then
      local metadata = type(row.metadata) == 'table' and row.metadata or {}
      local cardUidValue = tostring(metadata.cardUid or '')
      local matchesExpected = expectedCardUid == '' or cardUidValue == expectedCardUid
      local owner = tostring(metadata.ownerCitizenId or metadata.owner or '')
      if matchesExpected and owner ~= citizenid then
        ownerMismatch = true
      elseif matchesExpected then
        local credential = cardUidValue ~= '' and MZBankRepository.getCard(cardUidValue) or nil
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

local function invalidateCardSessions(citizenid, cardUidValue, keepCardUid)
  citizenid = tostring(citizenid or '')
  cardUidValue = tostring(cardUidValue or '')
  keepCardUid = tostring(keepCardUid or '')

  for sessionSource, session in pairs(Sessions) do
    local sessionCardUid = tostring(session.cardUid or '')
    local sameOwner = tostring(session.citizenid or '') == citizenid
    local matchesBlocked = cardUidValue ~= '' and sessionCardUid == cardUidValue
    local replaced = keepCardUid ~= '' and sessionCardUid ~= '' and sessionCardUid ~= keepCardUid
    if sameOwner and (matchesBlocked or replaced) then
      Sessions[sessionSource] = nil
      MZBankBridge.Log('bank.card.session_invalidated', sessionSource, {
        channel = session.channel,
        card_uid = sessionCardUid,
        reason = matchesBlocked and 'card_blocked' or 'card_replaced'
      })
    end
  end
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
    invalidateCardSessions(citizenid, nil, uid)
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

  local context, contextErr, contextDetail = resolvePhysicalContext(source, payload)
  if not context then
    MZBankBridge.Log('bank.session.denied', source, {
      channel = payload and payload.channel,
      error = contextErr,
      detail = contextDetail
    })
    if contextErr == 'invalid_ped' then
      print(('[mz_bank] session denied source=%s error=invalid_ped detail=%s'):format(
        tostring(source), tostring(contextDetail or 'unknown')
      ))
    end
    return response(false, contextErr)
  end

  local issueResult
  if context.channel == 'branch' and Config.Card.Enabled and Config.Card.AutoIssueOnFirstBranchVisit then
    if MZBankRepository.countActiveCards(identity.citizenid) == 0 then
      issueResult = issueCard(source, false, identity)
    end
  end

  local session = {
    token = createToken(),
    citizenid = identity.citizenid,
    channel = context.channel,
    coords = context.coords,
    lastVerifiedCoords = context.verifiedPlayerCoords,
    lastCoordCheckAt = GetGameTimer(),
    openedAtMs = GetGameTimer(),
    branchIndex = context.branchIndex,
    atmId = context.atmId,
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
  return MZBankService.GetAccountOverview(source, { token = token })
end

function MZBankService.GetAccountOverview(source, context)
  context = type(context) == 'table' and context or {}
  local session, sessionErr = validateSession(source, context.token, true)
  if not session then return response(false, sessionErr) end
  if not CHANNEL_PERMISSIONS[session.channel] or not CHANNEL_PERMISSIONS[session.channel].overview then
    return response(false, 'channel_forbidden')
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
    account = 'Conta corrente',
    statement = statementOk and normalizeStatement(statementOrErr) or {},
    statementError = statementOk and false or 'statement_unavailable',
    currencySymbol = Config.CurrencySymbol
  })
end

function MZBankService.Refresh(source, token)
  if rateLimited(source, 'data', Config.RateLimit.dataMs) then
    MZBankBridge.Log('bank.rate_limited', source, { operation = 'overview' })
    return response(false, 'rate_limited')
  end
  return MZBankService.GetAccountOverview(source, { token = token })
end

function MZBankService.GetStatement(source, filters, context)
  context = type(context) == 'table' and context or {}
  local session, sessionErr = validateSession(source, context.token, true)
  if not session then return response(false, sessionErr) end
  if not CHANNEL_PERMISSIONS[session.channel] or not CHANNEL_PERMISSIONS[session.channel].statement then
    return response(false, 'channel_forbidden')
  end

  local limit = math.min(math.max(math.floor(tonumber(filters and filters.limit) or Config.StatementLimit), 1), 100)
  local ok, payload = MZBankBridge.GetStatement(source, limit)
  if not ok then return response(false, 'statement_unavailable', { statement = {} }) end
  return response(true, nil, { statement = normalizeStatement(payload) })
end

local function resolveServerIdRecipient(source, recipientValue, allowOfflineRecovery)
  recipientValue = tostring(recipientValue or '')
  local targetSource = tonumber(recipientValue)
  if not targetSource or targetSource <= 0 or targetSource ~= math.floor(targetSource) then
    return nil, 'recipient_invalid'
  end

  local targetIdentity = targetSource and MZBankBridge.ResolvePlayer(targetSource, false) or nil
  if not targetIdentity then
    if allowOfflineRecovery == true then return { source = targetSource } end
    return nil, 'recipient_offline'
  end
  if tonumber(targetSource) == tonumber(source) then return nil, 'self_transfer' end

  return {
    source = targetSource,
    citizenid = targetIdentity.citizenid,
    name = targetIdentity.displayName
  }
end

function MZBankService.ResolveRecipient(source, recipientValue, context)
  context = type(context) == 'table' and context or {}
  local session, sessionErr = validateSession(source, context.token, true)
  if not session then return response(false, sessionErr) end
  if not (CHANNEL_PERMISSIONS[session.channel] and CHANNEL_PERMISSIONS[session.channel].transfer) then
    return response(false, 'channel_forbidden')
  end

  local resolved, resolveErr = resolveServerIdRecipient(source, recipientValue)
  if not resolved then return response(false, resolveErr) end
  return response(true, nil, { name = resolved.name })
end

local function transactionMetadata(session, reason, relatedCitizenId, idempotencyKey)
  local ref = ('mzbank-%s-%s-%06d'):format(os.time(), GetGameTimer(), math.random(0, 999999))
  return {
    category = session.channel == 'branch' and 'bank_branch' or (reason:find('transfer') and 'bank_transfer' or 'bank_atm'),
    reason = session.channel .. '_' .. reason,
    source_resource = 'mz_bank',
    source_type = session.channel,
    related_citizenid = relatedCitizenId,
    external_ref = ref,
    idempotency_key = idempotencyKey,
    data = { channel = session.channel, location = session.coords }
  }
end

local MAX_SAFE_INTEGER = 9007199254740991

local function validateIdempotencyKey(value)
  if type(value) ~= 'string' or value == '' then return nil, 'idempotency_required' end
  if #value < 16 or #value > 64 or not value:match('^[%w_-]+$') then
    return nil, 'invalid_idempotency_key'
  end
  return value
end

local function operationLimit(channel, operation)
  local channelLimits = type(Config.TransactionLimits) == 'table' and Config.TransactionLimits[channel] or nil
  local limit = type(channelLimits) == 'table' and tonumber(channelLimits[operation]) or nil
  if not limit or limit <= 0 or limit ~= math.floor(limit) then return nil end
  return math.min(limit, MAX_SAFE_INTEGER)
end

local function validateAmount(amount, channel, operation)
  if type(amount) ~= 'number'
    or amount ~= amount
    or amount == math.huge
    or amount == -math.huge
    or amount <= 0
    or amount ~= math.floor(amount)
    or amount > MAX_SAFE_INTEGER then
    return nil, 'invalid_amount'
  end
  local limit = operationLimit(channel, operation)
  if not limit then return nil, 'bank_unavailable' end
  if amount > limit then return nil, 'transaction_limit' end
  return amount
end

local function calculateTransferFee(amount)
  local percent = tonumber(Config.TransferFeePercent)
  if not percent or percent ~= percent or percent == math.huge or percent == -math.huge or percent < 0 then
    return nil, 'bank_unavailable'
  end
  if tostring(Config.TransferFeeRounding or 'floor') ~= 'floor' then return nil, 'bank_unavailable' end
  local fee = math.floor(amount * (percent / 100))
  if fee < 0 or fee > MAX_SAFE_INTEGER or amount + fee > MAX_SAFE_INTEGER then
    return nil, 'transaction_limit'
  end
  return fee
end

local function coreTransactionError(errorCode, insufficientCode)
  if errorCode == 'not_enough_money' then return insufficientCode end
  if errorCode == 'account_busy' then return 'operation_busy' end
  if errorCode == 'database_error' then return 'database_error' end
  if errorCode == 'amount_overflow' then return 'transaction_limit' end
  return errorCode or 'transaction_failed'
end

local function runOperation(source, token, operation, idempotencyKey, handler)
  local session, sessionErr = validateSession(source, token, true)
  if not session then return response(false, sessionErr) end
  if not (CHANNEL_PERMISSIONS[session.channel] and CHANNEL_PERMISSIONS[session.channel][operation]) then
    return response(false, 'channel_forbidden')
  end
  if operationRateLimited(source, idempotencyKey, Config.RateLimit.operationMs) then
    MZBankBridge.Log('bank.rate_limited', source, { operation = operation })
    return response(false, 'rate_limited')
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

local function confirmedFinancialResponse(source, token, session, operation, amount, fee, result)
  local correlationId = tostring(result.transactionRef or result.correlationId or '')
  if correlationId == '' then return response(false, 'transaction_failed') end
  local data = {
    confirmed = true,
    operation = operation,
    channel = session.channel,
    amount = amount,
    fee = fee or 0,
    correlationId = correlationId,
    transactionRef = correlationId,
    replayed = result.replayed == true
  }

  if type(result.balances) == 'table' then
    if operation == 'transfer' then
      data.balance = tonumber(result.balances.sender)
    else
      data.balance = tonumber(result.balances.bank)
      data.cash = tonumber(result.balances.wallet)
    end
  end

  local overview = MZBankService.GetAccountOverview(source, { token = token })
  if overview.ok == true and type(overview.data) == 'table' then
    for key, value in pairs(overview.data) do data[key] = value end
  else
    data.refreshError = overview.error or 'bank_unavailable'
  end

  local out = response(true, nil, data, Config.Locale.success)
  out.confirmed = true
  out.correlationId = correlationId
  out.replayed = result.replayed == true
  return out
end

function MZBankService.Withdraw(source, token, rawAmount, rawIdempotencyKey)
  local idempotencyKey, idempotencyErr = validateIdempotencyKey(rawIdempotencyKey)
  if not idempotencyKey then return response(false, idempotencyErr) end
  return runOperation(source, token, 'withdraw', idempotencyKey, function(session)
    local amount, amountErr = validateAmount(rawAmount, session.channel, 'withdraw')
    if not amount then return response(false, amountErr) end
    local result = MZBankBridge.TransferBetweenOwnAccounts(
      source,
      'bank',
      'wallet',
      amount,
      transactionMetadata(session, 'withdraw', nil, idempotencyKey)
    )
    if result.ok ~= true then
      return response(false, coreTransactionError(result.error, 'not_enough_bank'))
    end
    MZBankBridge.Log(result.replayed and 'bank.withdraw.replayed' or 'bank.withdraw', source, {
      channel = session.channel, amount = amount, transaction_ref = result.transactionRef
    })
    return confirmedFinancialResponse(source, token, session, 'withdraw', amount, 0, result)
  end)
end

function MZBankService.Deposit(source, token, rawAmount, rawIdempotencyKey)
  local idempotencyKey, idempotencyErr = validateIdempotencyKey(rawIdempotencyKey)
  if not idempotencyKey then return response(false, idempotencyErr) end
  return runOperation(source, token, 'deposit', idempotencyKey, function(session)
    local amount, amountErr = validateAmount(rawAmount, session.channel, 'deposit')
    if not amount then return response(false, amountErr) end
    local result = MZBankBridge.TransferBetweenOwnAccounts(
      source,
      'wallet',
      'bank',
      amount,
      transactionMetadata(session, 'deposit', nil, idempotencyKey)
    )
    if result.ok ~= true then
      return response(false, coreTransactionError(result.error, 'not_enough_wallet'))
    end
    MZBankBridge.Log(result.replayed and 'bank.deposit.replayed' or 'bank.deposit', source, {
      channel = session.channel, amount = amount, transaction_ref = result.transactionRef
    })
    return confirmedFinancialResponse(source, token, session, 'deposit', amount, 0, result)
  end)
end

function MZBankService.Transfer(source, recipient, rawAmount, context)
  context = type(context) == 'table' and context or {}
  local idempotencyKey, idempotencyErr = validateIdempotencyKey(context.idempotencyKey)
  if not idempotencyKey then return response(false, idempotencyErr) end
  local recipientValue = type(recipient) == 'table'
    and (recipient.value or recipient.recipientValue or recipient.targetId)
    or recipient

  return runOperation(source, context.token, 'transfer', idempotencyKey, function(session)
    local amount, amountErr = validateAmount(rawAmount, session.channel, 'transfer')
    if not amount then return response(false, amountErr) end
    local resolved, resolveErr = resolveServerIdRecipient(source, recipientValue, true)
    if not resolved then return response(false, resolveErr) end
    local fee, feeErr = calculateTransferFee(amount)
    if fee == nil then return response(false, feeErr) end
    local metadata = transactionMetadata(session, 'transfer', resolved.citizenid, idempotencyKey)
    metadata.fee = fee
    metadata.recipient_reason = session.channel .. '_transfer_received'
    local result = MZBankBridge.TransferBankBetweenPlayers(source, resolved.source, amount, metadata)
    if result.ok ~= true then return response(false, coreTransactionError(result.error, 'not_enough_bank')) end

    if result.replayed ~= true and resolved.citizenid then
      MZBankBridge.Notify(resolved.source, ('Voce recebeu %s%s de %s.'):format(Config.CurrencySymbol, amount, MZBankBridge.GetDisplayName(source)), 'success')
    end
    MZBankBridge.Log(result.replayed and 'bank.transfer.replayed' or 'bank.transfer', source, {
      channel = session.channel, amount = amount, fee = fee,
      related_citizenid = result.targetCitizenId or resolved.citizenid, transaction_ref = result.transactionRef
    })
    return confirmedFinancialResponse(source, context.token, session, 'transfer', amount, fee, result)
  end)
end

local function validateBranchCardContext(source, context)
  context = type(context) == 'table' and context or {}
  local session, sessionErr = validateSession(source, context.token, true)
  if not session then return nil, sessionErr end
  if session.channel ~= 'branch'
    or not (CHANNEL_PERMISSIONS[session.channel] and CHANNEL_PERMISSIONS[session.channel].cards) then
    return nil, 'channel_forbidden'
  end
  return session
end

function MZBankService.GetCards(source, context)
  local _, sessionErr = validateBranchCardContext(source, context)
  if sessionErr then return response(false, sessionErr) end
  local identity = MZBankBridge.ResolvePlayer(source, false)
  if not identity then return response(false, 'player_not_loaded') end
  return response(true, nil, { cards = MZBankRepository.listCards(identity.citizenid) })
end

function MZBankService.BlockCard(source, cardUidValue, context)
  local _, sessionErr = validateBranchCardContext(source, context)
  if sessionErr then return response(false, sessionErr) end
  local identity = MZBankBridge.ResolvePlayer(source, false)
  if not identity then return response(false, 'player_not_loaded') end
  if not MZBankRepository.blockCard(identity.citizenid, tostring(cardUidValue or '')) then return response(false, 'card_invalid') end
  invalidateCardSessions(identity.citizenid, cardUidValue, nil)
  MZBankBridge.Log('bank.card.blocked', source, { channel = 'branch' })
  return response(true, nil, nil, Config.Locale.card_blocked_success)
end

function MZBankService.RequestReplacementCard(source, context)
  context = type(context) == 'table' and context or {}
  if not context.token then return response(false, 'invalid_session') end
  local session, err = validateSession(source, context.token, true)
  if not session then return response(false, err) end
  if session.channel ~= 'branch' then return response(false, 'channel_forbidden') end
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
