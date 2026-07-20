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

local function clearSession(source)
  local session = Sessions[source]
  if session and type(MZBankAccountResolution) == 'table'
      and type(MZBankAccountResolution.CleanupSession) == 'function' then
    MZBankAccountResolution.CleanupSession(source, session.token)
  end
  Sessions[source] = nil
end

local function validateSession(source, token, requireAuthentication)
  if not ready then return nil, 'bank_unavailable' end
  local session = Sessions[source]
  if not session or tostring(token or '') == '' or session.token ~= token then
    MZBankBridge.Log('bank.session.invalid', source, { error = 'invalid_session' })
    return nil, 'invalid_session'
  end
  if session.expiresAt <= os.time() then
    MZBankBridge.Log('bank.session.expired', source, { channel = session.channel })
    clearSession(source)
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
    clearSession(source)
    return nil, 'player_not_loaded'
  end
  local playerState, stateErr, stateDetail = getServerPlayerState(source)
  if not playerState then
    local elapsed = GetGameTimer() - (tonumber(session.lastCoordCheckAt) or 0)
    if stateErr ~= 'invalid_ped' or elapsed > COORDINATE_GRACE_MS then
      clearSession(source)
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
      clearSession(source)
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
      clearSession(source)
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
  local feeExternalRef = ('mzbank-card-fee-%d-%d-%06d'):format(
    os.time(), tonumber(source) or 0, math.random(0, 999999)
  )
  local feePaid = false
  if fee > 0 then
    local paid, payErr = MZBankBridge.RemoveMoney(source, 'bank', fee, {
      category = 'bank_branch', reason = replacement and 'card_replacement_fee' or 'card_issue_fee',
      source_resource = 'mz_bank', source_type = 'branch', external_ref = feeExternalRef
    })
    if not paid then return response(false, payErr == 'not_enough_money' and 'not_enough_bank' or 'transaction_failed') end
    feePaid = true
  end


  local function refundFee(reason)
    if not feePaid then return end
    local refunded, refundErr = MZBankBridge.AddMoney(source, 'bank', fee, {
      category = 'bank_branch', reason = 'card_fee_rollback', source_resource = 'mz_bank',
      source_type = 'branch', external_ref = feeExternalRef,
      data = { rollback_reason = reason }
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

  local publicAccount
  if MZBankAccountService.IsEnabled() then
    local ensured = MZBankAccountService.EnsurePersonalAccount({
      citizenid = identity.citizenid
    })
    if type(ensured) ~= 'table' or ensured.ok ~= true or type(ensured.account) ~= 'table' then
      local accountError = type(ensured) == 'table' and ensured.error or 'public_account_unavailable'
      MZBankBridge.Log('bank.public_account.ensure_failed', source, {
        channel = session.channel,
        error = accountError
      })
      if accountError == 'account_number_allocation_failed' then
        return response(false, accountError)
      end
      return response(false, 'public_account_unavailable')
    end
    publicAccount = ensured.account
    if not MZBankAccountService.CanAccountPerform(publicAccount.status, 'read') then
      return response(false, 'account_closed')
    end
    if ensured.created == true then
      MZBankBridge.Log('bank.public_account.created', source, {
        channel = session.channel,
        account_type = publicAccount.accountType,
        status = publicAccount.status
      })
    end
  end

  local bank, bankErr = MZBankBridge.GetMoney(source, 'bank')
  local wallet = MZBankBridge.GetMoney(source, 'wallet')
  if bank == nil then return response(false, bankErr or 'bank_unavailable') end

  local statementOk, statementOrErr = MZBankBridge.GetStatement(source, Config.StatementLimit)
  return response(true, nil, {
    balance = bank,
    cash = wallet or 0,
    name = identity.displayName,
    account = publicAccount and publicAccount.formatted or 'Conta corrente',
    publicAccount = publicAccount,
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

function MZBankService.GetPublicAccount(source, context)
  context = type(context) == 'table' and context or {}
  local session, sessionErr = validateSession(source, context.token, true)
  if not session then return response(false, sessionErr) end
  if not (CHANNEL_PERMISSIONS[session.channel] and CHANNEL_PERMISSIONS[session.channel].overview) then
    return response(false, 'channel_forbidden')
  end

  local identity = MZBankBridge.ResolvePlayer(source, false)
  if not identity then return response(false, 'player_not_loaded') end
  if MZBankAccountService.IsEnabled() ~= true then
    return response(false, 'public_account_unavailable')
  end

  local ensured = MZBankAccountService.EnsurePersonalAccount({ citizenid = identity.citizenid })
  if type(ensured) ~= 'table' or ensured.ok ~= true or type(ensured.account) ~= 'table' then
    return response(false, type(ensured) == 'table' and ensured.error or 'public_account_unavailable')
  end
  if MZBankAccountService.CanAccountPerform(ensured.account.status, 'read') ~= true then
    return response(false, 'account_closed')
  end
  return response(true, nil, { account = ensured.account })
end

function MZBankService.GetChannelCapabilities(source, context)
  context = type(context) == 'table' and context or {}
  local session, sessionErr = validateSession(source, context.token, true)
  if not session then return response(false, sessionErr) end

  local configured = CHANNEL_PERMISSIONS[session.channel]
  if type(configured) ~= 'table' then return response(false, 'channel_forbidden') end
  local capabilities = {}
  for name, allowed in pairs(configured) do capabilities[name] = allowed == true end
  capabilities.cash = capabilities.withdraw == true or capabilities.deposit == true
  return response(true, nil, {
    channel = session.channel,
    capabilities = capabilities
  })
end

local function buildPublicResolutionActor(source, identity, session)
  if type(identity) ~= 'table' or type(session) ~= 'table' then return nil end
  return {
    source = source,
    citizenid = identity.citizenid,
    sessionToken = session.token,
    channel = session.channel
  }
end

-- P2-G: a NUI fisica usa este contrato sem receber citizenid ou IDs internos.
function MZBankService.ResolvePublicRecipient(source, route, context)
  context = type(context) == 'table' and context or {}
  local session, sessionErr = validateSession(source, context.token, true)
  if not session then return response(false, sessionErr) end
  if not (CHANNEL_PERMISSIONS[session.channel] and CHANNEL_PERMISSIONS[session.channel].transfer) then
    return response(false, 'channel_forbidden')
  end
  local identity = MZBankBridge.ResolvePlayer(source, false)
  if not identity then return response(false, 'player_not_loaded') end
  if type(MZBankAccountResolution) ~= 'table'
      or type(MZBankAccountResolution.Resolve) ~= 'function' then
    return response(false, 'resolution_unavailable')
  end
  local actor = buildPublicResolutionActor(source, identity, session)
  if not actor then return response(false, 'resolution_unavailable') end
  local resolved = MZBankAccountResolution.Resolve(actor, route)
  if type(resolved) ~= 'table' or resolved.ok ~= true then
    return response(false, type(resolved) == 'table' and resolved.error or 'resolution_unavailable')
  end
  return response(true, nil, {
    found = true,
    resolutionToken = resolved.resolutionToken,
    recipient = resolved.recipient,
    expiresIn = resolved.expiresIn
  })
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

local function publicOriginError(account)
  if type(account) ~= 'table' then return 'public_account_unavailable' end
  local status = tostring(account.status or '')
  if status == 'blocked' then return 'account_blocked' end
  if status == 'frozen' then return 'account_frozen' end
  if status == 'closed' then return 'account_closed' end
  return 'public_account_unavailable'
end

local function validatePublicOriginCapability(source, capability)
  if MZBankAccountService.IsEnabled() ~= true then return true end
  local identity = MZBankBridge.ResolvePlayer(source, false)
  if not identity then return false, 'player_not_loaded' end

  local callOk, ensured = pcall(MZBankAccountService.EnsurePersonalAccount, {
    citizenid = identity.citizenid
  })
  if not callOk or type(ensured) ~= 'table' or ensured.ok ~= true
      or type(ensured.account) ~= 'table' then
    return false, 'public_account_unavailable'
  end
  if MZBankAccountService.CanAccountPerform(ensured.account.status, capability) ~= true then
    return false, publicOriginError(ensured.account)
  end
  return true
end

function MZBankService.Withdraw(source, token, rawAmount, rawIdempotencyKey)
  local idempotencyKey, idempotencyErr = validateIdempotencyKey(rawIdempotencyKey)
  if not idempotencyKey then return response(false, idempotencyErr) end
  return runOperation(source, token, 'withdraw', idempotencyKey, function(session)
    local amount, amountErr = validateAmount(rawAmount, session.channel, 'withdraw')
    if not amount then return response(false, amountErr) end
    local allowed, accountError = validatePublicOriginCapability(source, 'withdraw')
    if not allowed then return response(false, accountError) end
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
    local allowed, accountError = validatePublicOriginCapability(source, 'deposit')
    if not allowed then return response(false, accountError) end
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

local function isAmbiguousPublicTransferError(errorCode)
  return errorCode == 'bank_unavailable'
    or errorCode == 'database_error'
    or errorCode == 'account_busy'
    or errorCode == 'operation_busy'
end

local function consumePublicResolution(actor, resolutionToken)
  if MZBankAccountResolution.InvalidateResolutionToken(actor, resolutionToken) == true then
    return true
  end
  -- Fail closed: se o token esperado nao puder ser removido individualmente,
  -- elimina todos os intents da mesma sessao sem encerrar a sessao bancaria.
  MZBankAccountResolution.CleanupSession(actor.source, actor.sessionToken)
  return false
end

local function executePublicAccountTransfer(
  source, resolutionToken, rawAmount, idempotencyKey, session
)
    local amount, amountErr = validateAmount(rawAmount, session.channel, 'transfer')
    if not amount then return response(false, amountErr) end

    if type(MZBankAccountResolution) ~= 'table'
        or type(MZBankAccountResolution.ValidateResolutionToken) ~= 'function'
        or type(MZBankAccountResolution.InvalidateResolutionToken) ~= 'function'
        or type(MZBankAccountResolution.CleanupSession) ~= 'function'
        or type(MZBankRepository) ~= 'table'
        or type(MZBankRepository.getPublicAccountByOwner) ~= 'function'
        or type(MZBankAccountService) ~= 'table'
        or type(MZBankAccountService.CanAccountPerform) ~= 'function' then
      return response(false, 'resolution_unavailable')
    end

    local identity = MZBankBridge.ResolvePlayer(source, false)
    if not identity then return response(false, 'player_not_loaded') end
    local actor = buildPublicResolutionActor(source, identity, session)
    if not actor then return response(false, 'resolution_unavailable') end

    local originLookupOk, originAccount, originLookupError = pcall(
      MZBankRepository.getPublicAccountByOwner, identity.citizenid
    )
    if not originLookupOk or originLookupError
        or type(originAccount) ~= 'table'
        or tostring(originAccount.citizenid or '') ~= tostring(identity.citizenid)
        or tostring(originAccount.account_type or '') ~= 'personal'
        or MZBankAccountService.CanAccountPerform(originAccount.status, 'transfer') ~= true then
      consumePublicResolution(actor, resolutionToken)
      return response(false, publicOriginError(originAccount))
    end

    local resolved, resolutionError = MZBankAccountResolution.ValidateResolutionToken(
      actor, resolutionToken
    )
    if not resolved then return response(false, resolutionError or 'invalid_resolution_token') end
    if tostring(resolved.targetCitizenId or '') == tostring(identity.citizenid) then
      consumePublicResolution(actor, resolutionToken)
      return response(false, 'self_transfer')
    end

    local fee, feeErr = calculateTransferFee(amount)
    if fee == nil then
      consumePublicResolution(actor, resolutionToken)
      return response(false, feeErr)
    end
    local metadata = transactionMetadata(
      session, 'public_account_transfer', resolved.targetCitizenId, idempotencyKey
    )
    metadata.fee = fee
    metadata.recipient_reason = session.channel .. '_transfer_received'
    metadata.data.public_account_resolution = true

    -- O citizenid foi resolvido e revalidado exclusivamente no servidor. O
    -- core continua responsavel por locks, persistencia atomica e idempotencia.
    local result = MZBankBridge.TransferBankBetweenPlayers(
      source, resolved.targetCitizenId, amount, metadata
    )
    if type(result) ~= 'table' or result.ok ~= true then
      local rawError = type(result) == 'table' and result.error or 'transaction_failed'
      if not isAmbiguousPublicTransferError(rawError) then
        consumePublicResolution(actor, resolutionToken)
      end
      if rawError == 'recipient_offline' then rawError = 'recipient_unavailable' end
      return response(false, coreTransactionError(rawError, 'not_enough_bank'))
    end

    consumePublicResolution(actor, resolutionToken)
    local targetSource = tonumber(result.targetSource or resolved.targetSource)
    if result.replayed ~= true and targetSource and targetSource > 0 then
      MZBankBridge.Notify(targetSource, ('Voce recebeu %s%s de %s.'):format(
        Config.CurrencySymbol, amount, MZBankBridge.GetDisplayName(source)
      ), 'success')
    end
    MZBankBridge.Log(
      result.replayed and 'bank.public_account.transfer.replayed'
        or 'bank.public_account.transfer',
      source,
      {
        channel = session.channel,
        amount = amount,
        fee = fee,
        transaction_ref = result.transactionRef
      }
    )
    return confirmedFinancialResponse(
      source, session.token, session, 'transfer', amount, fee, result
    )
end

-- P2-G: contrato financeiro consumido pelo callback fisico apos confirmacao.
function MZBankService.TransferByPublicAccount(source, resolutionToken, rawAmount, context)
  context = type(context) == 'table' and context or {}
  local idempotencyKey, idempotencyErr = validateIdempotencyKey(context.idempotencyKey)
  if not idempotencyKey then return response(false, idempotencyErr) end

  return runOperation(source, context.token, 'transfer', idempotencyKey, function(session)
    return executePublicAccountTransfer(
      source, resolutionToken, rawAmount, idempotencyKey, session
    )
  end)
end

-- Superficie estritamente interna para o runner temporario. Com a convar
-- desligada as funcoes nem sequer existem. Nao ha export/evento/callback.
if GetConvarInt('mz_bank_p2f_runtime_runner', 0) == 1 then
  function MZBankService.GetP2FRuntimeSession(source)
    source = tonumber(source)
    local existing = source and Sessions[source] or nil
    if not existing then return nil, 'invalid_session' end
    local session, sessionError = validateSession(source, existing.token, true)
    if not session then return nil, sessionError end
    return {
      token = session.token,
      citizenid = session.citizenid,
      channel = session.channel,
      coords = cloneCoords(session.coords),
      authenticated = session.authenticated == true
    }
  end

  function MZBankService.ExecuteP2FRuntimeFixture(
    source, resolutionToken, rawAmount, rawIdempotencyKey, session
  )
    local idempotencyKey, idempotencyError = validateIdempotencyKey(rawIdempotencyKey)
    if not idempotencyKey then return response(false, idempotencyError) end
    if type(session) ~= 'table' or session.authenticated ~= true
        or (session.channel ~= 'atm' and session.channel ~= 'branch')
        or type(session.token) ~= 'string' or session.token == '' then
      return response(false, 'invalid_session')
    end
    return executePublicAccountTransfer(
      source, resolutionToken, rawAmount, idempotencyKey, session
    )
  end
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

function MZBankService.IssueCard(source, context)
  local _, sessionErr = validateBranchCardContext(source, context)
  if sessionErr then return response(false, sessionErr) end
  return issueCard(source, false)
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
    clearSession(source)
    MZBankBridge.Log('bank.session.closed', source, { channel = session.channel, reason = reason or 'client_close' })
  end
  return response(true)
end

function MZBankService.CleanupSource(source)
  if type(MZBankAccountResolution) == 'table'
      and type(MZBankAccountResolution.CleanupSession) == 'function' then
    MZBankAccountResolution.CleanupSession(source)
  end
  Sessions[source] = nil
  RateLimits[source] = nil
end

CreateThread(function()
  while true do
    Wait(5000)
    local now = os.time()
    for source, session in pairs(Sessions) do
      if session.expiresAt <= now then
        clearSession(source)
      end
    end
  end
end)
