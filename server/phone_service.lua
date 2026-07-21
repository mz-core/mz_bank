MZBankPhoneService = {}

local Sessions = {}
local policy = type(Config.PhoneChannel) == 'table' and Config.PhoneChannel or {}
local TOKEN_ALPHABET = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
local CAPABILITIES = {
  overview = true,
  statement = true,
  cards = true,
  transfer = true,
  withdraw = false,
  deposit = false,
  issueCard = false,
  blockCard = true,
  replaceCard = false,
  cash = false
}

local function response(ok, errorCode, data, message)
  return {
    ok = ok == true,
    error = errorCode,
    message = message or (errorCode and (Config.Locale[errorCode] or Config.Locale.transaction_failed)) or nil,
    data = data
  }
end

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function normalizeDeviceId(value)
  if type(value) ~= 'string' then return nil end
  local deviceId = trim(value)
  local maxLength = math.max(8, math.floor(tonumber(policy.DeviceIdMaxLength) or 32))
  if #deviceId < 3 or #deviceId > maxLength then return nil end
  if deviceId:match('^[%d%+%-]+$') == nil then return nil end
  return deviceId
end

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
  return nil
end

local function copyCapabilities()
  local out = {}
  for name, allowed in pairs(CAPABILITIES) do out[name] = allowed == true end
  return out
end

local function normalizeStatement(payload)
  local rows = type(payload) == 'table' and payload.rows or {}
  local statement = {}
  for _, row in ipairs(rows or {}) do
    local amount = math.floor(tonumber(row.amount) or 0)
    if tostring(row.direction) == 'out' then amount = -math.abs(amount) end
    statement[#statement + 1] = {
      type = row.reason or row.category or row.direction,
      description = row.reason or row.category or 'Movimentacao bancaria',
      amount = amount,
      balanceAfter = row.balance_after,
      occurredAt = row.created_at
    }
  end
  return statement
end

local function clearSession(source, reason)
  local normalizedSource = tonumber(source)
  local session = normalizedSource and Sessions[normalizedSource] or nil
  if session then
    if type(MZBankAccountResolution) == 'table'
        and type(MZBankAccountResolution.CleanupSession) == 'function' then
      MZBankAccountResolution.CleanupSession(normalizedSource, session.token)
    end
    Sessions[normalizedSource] = nil
    MZBankBridge.Log('bank.phone_session.closed', normalizedSource, {
      channel = 'phone', reason = reason or 'cleanup'
    })
  end
end

local function validateSession(source, context)
  if policy.Enabled ~= true or MZBankService.IsReady() ~= true then
    return nil, 'bank_unavailable'
  end

  source = tonumber(source)
  context = type(context) == 'table' and context or {}
  if not source or source <= 0 then return nil, 'invalid_session' end

  local token = tostring(context.token or '')
  local deviceId = normalizeDeviceId(context.deviceId)
  local session = Sessions[source]
  if not session or token == '' or session.token ~= token or not deviceId
      or session.deviceId ~= deviceId then
    return nil, 'invalid_session'
  end
  if session.expiresAt <= os.time() then
    clearSession(source, 'expired')
    return nil, 'session_expired'
  end

  local identity = MZBankBridge.ResolvePlayer(source, false)
  if not identity or tostring(identity.citizenid or '') ~= tostring(session.citizenid or '') then
    clearSession(source, 'identity_changed')
    return nil, 'invalid_session'
  end

  session.expiresAt = os.time() + math.max(30, math.floor(tonumber(policy.SessionTimeoutSeconds) or 120))
  return session, nil, identity
end

local function ensurePublicAccount(identity)
  if MZBankAccountService.IsEnabled() ~= true then
    return nil, 'public_account_unavailable'
  end
  local ensured = MZBankAccountService.EnsurePersonalAccount({ citizenid = identity.citizenid })
  if type(ensured) ~= 'table' or ensured.ok ~= true or type(ensured.account) ~= 'table' then
    return nil, type(ensured) == 'table' and ensured.error or 'public_account_unavailable'
  end
  if MZBankAccountService.CanAccountPerform(ensured.account.status, 'read') ~= true then
    return nil, 'account_closed'
  end
  return ensured.account
end

function MZBankPhoneService.OpenSession(source, request)
  if policy.Enabled ~= true or MZBankService.IsReady() ~= true then
    return response(false, 'bank_unavailable')
  end
  source = tonumber(source)
  request = type(request) == 'table' and request or {}
  local deviceId = normalizeDeviceId(request.deviceId)
  if not source or source <= 0 or not deviceId then return response(false, 'invalid_session') end

  local identity = MZBankBridge.ResolvePlayer(source, true)
  if not identity then return response(false, 'player_not_loaded') end
  local token = createToken()
  if not token then return response(false, 'transaction_failed') end

  clearSession(source, 'replaced')
  Sessions[source] = {
    token = token,
    citizenid = identity.citizenid,
    deviceId = deviceId,
    channel = 'phone',
    authenticated = true,
    openedAt = os.time(),
    expiresAt = os.time() + math.max(30, math.floor(tonumber(policy.SessionTimeoutSeconds) or 120)),
    busy = false,
    operationRate = nil
  }
  MZBankBridge.Log('bank.phone_session.opened', source, { channel = 'phone' })
  return response(true, nil, {
    token = token,
    channel = 'phone',
    expiresIn = math.max(30, math.floor(tonumber(policy.SessionTimeoutSeconds) or 120)),
    capabilities = copyCapabilities()
  })
end

function MZBankPhoneService.CloseSession(source, context, reason)
  source = tonumber(source)
  context = type(context) == 'table' and context or {}
  local session = source and Sessions[source] or nil
  if session and tostring(context.token or '') == session.token
      and normalizeDeviceId(context.deviceId) == session.deviceId then
    clearSession(source, reason or 'phone_close')
  end
  return response(true)
end

function MZBankPhoneService.GetChannelCapabilities(source, context)
  local session, err = validateSession(source, context)
  if not session then return response(false, err) end
  return response(true, nil, { channel = 'phone', capabilities = copyCapabilities() })
end

function MZBankPhoneService.GetAccountOverview(source, context)
  local session, err, identity = validateSession(source, context)
  if not session then return response(false, err) end
  local account, accountErr = ensurePublicAccount(identity)
  if not account then return response(false, accountErr) end

  local balance, balanceErr = MZBankBridge.GetMoney(source, 'bank')
  if balance == nil then return response(false, balanceErr or 'bank_unavailable') end
  local statementOk, statementOrErr = MZBankBridge.GetStatement(source, Config.StatementLimit)
  return response(true, nil, {
    balance = balance,
    name = identity.displayName,
    account = account.formatted,
    publicAccount = account,
    statement = statementOk and normalizeStatement(statementOrErr) or {},
    statementError = statementOk and false or 'statement_unavailable',
    currencySymbol = Config.CurrencySymbol
  })
end

function MZBankPhoneService.Refresh(source, context)
  return MZBankPhoneService.GetAccountOverview(source, context)
end

function MZBankPhoneService.GetStatement(source, filters, context)
  local session, err = validateSession(source, context)
  if not session then return response(false, err) end
  local configuredLimit = math.max(1, math.floor(tonumber(policy.MaxStatementLimit) or 50))
  local limit = math.min(math.max(math.floor(tonumber(filters and filters.limit) or Config.StatementLimit), 1), configuredLimit)
  local ok, payload = MZBankBridge.GetStatement(source, limit)
  if not ok then return response(false, 'statement_unavailable', { statement = {} }) end
  return response(true, nil, { statement = normalizeStatement(payload) })
end

function MZBankPhoneService.GetPublicAccount(source, context)
  local session, err, identity = validateSession(source, context)
  if not session then return response(false, err) end
  local account, accountErr = ensurePublicAccount(identity)
  if not account then return response(false, accountErr) end
  return response(true, nil, { account = account })
end

function MZBankPhoneService.GetCards(source, context)
  local session, err, identity = validateSession(source, context)
  if not session then return response(false, err) end
  return response(true, nil, { cards = MZBankRepository.listCards(identity.citizenid) })
end

function MZBankPhoneService.BlockCard(source, cardUidValue, context)
  local session, err, identity = validateSession(source, context)
  if not session then return response(false, err) end
  if session.busy == true then return response(false, 'operation_busy') end
  if type(MZBankService.BlockCardForValidatedIdentity) ~= 'function' then
    return response(false, 'bank_unavailable')
  end

  session.busy = true
  local callOk, result = pcall(
    MZBankService.BlockCardForValidatedIdentity,
    source, cardUidValue, identity, 'phone'
  )
  session.busy = false
  if not callOk then
    print(('[mz_bank] phone card block failed source=%s error=%s'):format(
      tostring(source), tostring(result)
    ))
    return response(false, 'transaction_failed')
  end
  return result
end

local function buildResolutionActor(source, identity, session)
  return {
    source = source,
    citizenid = identity.citizenid,
    sessionToken = session.token,
    channel = 'phone'
  }
end

function MZBankPhoneService.ResolvePublicRecipient(source, route, context)
  local session, err, identity = validateSession(source, context)
  if not session then return response(false, err) end
  if type(MZBankAccountResolution) ~= 'table'
      or type(MZBankAccountResolution.Resolve) ~= 'function' then
    return response(false, 'resolution_unavailable')
  end
  local resolved = MZBankAccountResolution.Resolve(
    buildResolutionActor(source, identity, session), route
  )
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

function MZBankPhoneService.TransferByPublicAccount(source, resolutionToken, rawAmount, context)
  local session, err = validateSession(source, context)
  if not session then return response(false, err) end
  context = type(context) == 'table' and context or {}
  local idempotencyKey = tostring(context.idempotencyKey or '')
  local now = GetGameTimer()
  local rate = type(session.operationRate) == 'table' and session.operationRate or nil
  if rate and rate.idempotencyKey ~= idempotencyKey and now < tonumber(rate.nextAllowed or 0) then
    return response(false, 'rate_limited')
  end
  if session.busy == true then return response(false, 'operation_busy') end
  session.operationRate = {
    idempotencyKey = idempotencyKey,
    nextAllowed = now + math.max(0, tonumber(Config.RateLimit.operationMs) or 0)
  }
  session.busy = true
  local callOk, result = pcall(
    MZBankService.TransferByValidatedSession,
    source, resolutionToken, rawAmount, idempotencyKey, session
  )
  session.busy = false
  if not callOk then
    print(('[mz_bank] phone transfer failed source=%s error=%s'):format(
      tostring(source), tostring(result)
    ))
    return response(false, 'transaction_failed')
  end
  return result
end

function MZBankPhoneService.CleanupSource(source)
  clearSession(source, 'source_cleanup')
end

CreateThread(function()
  while true do
    Wait(5000)
    local stamp = os.time()
    for source, session in pairs(Sessions) do
      if session.expiresAt <= stamp then clearSession(source, 'expired') end
    end
  end
end)
