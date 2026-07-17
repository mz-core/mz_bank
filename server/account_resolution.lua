MZBankAccountResolution = {}

local publicPolicy = type(Config.PublicAccount) == 'table' and Config.PublicAccount or {}
local policy = type(publicPolicy.Resolution) == 'table' and publicPolicy.Resolution or {}
local TOKEN_PREFIX = 'p2e-'
local sessionLimits = {}
local actorLimits = {}
local resolutions = {}

local function trim(value)
  if type(value) ~= 'string' then return nil end
  local normalized = value:gsub('^%s+', ''):gsub('%s+$', '')
  if normalized == '' or normalized ~= value then return nil end
  return normalized
end

local function validatePolicy()
  if type(policy.Enabled) ~= 'boolean' then return false, 'invalid_resolution_enabled' end
  if tonumber(policy.TokenTtlSeconds) ~= 60 then return false, 'invalid_resolution_token_ttl' end
  if tonumber(policy.SessionWindowSeconds) ~= 60
      or tonumber(policy.SessionMaxAttempts) ~= 5 then
    return false, 'invalid_resolution_session_limit'
  end
  if tonumber(policy.ActorWindowSeconds) ~= 3600
      or tonumber(policy.ActorMaxAttempts) ~= 20 then
    return false, 'invalid_resolution_actor_limit'
  end
  if tonumber(policy.CooldownAfterFailures) ~= 3
      or tonumber(policy.CooldownBaseSeconds) ~= 2
      or tonumber(policy.CooldownMaxSeconds) ~= 30 then
    return false, 'invalid_resolution_cooldown'
  end
  if tonumber(policy.MaxActiveTokensPerSource) ~= 20 then
    return false, 'invalid_resolution_token_limit'
  end
  return true
end

local policyOk, policyError = validatePolicy()

local function enabled()
  return policyOk == true and policy.Enabled == true
    and type(MZBankAccountService) == 'table'
    and MZBankAccountService.IsEnabled() == true
end

local function runtimeReady()
  if not enabled() then return false end
  local status = MZBankAccountService.GetRuntimeStatus()
  return type(status) == 'table' and status.ready == true
end

local function copyActor(value)
  if type(value) ~= 'table' then return nil, 'invalid_resolution_actor' end
  local source = tonumber(value.source)
  local citizenid = trim(value.citizenid)
  local sessionToken = trim(value.sessionToken)
  local channel = trim(value.channel)
  if not source or source <= 0 or source ~= math.floor(source)
      or not citizenid or #citizenid > 32
      or not sessionToken or #sessionToken > 128
      or (channel ~= 'atm' and channel ~= 'branch') then
    return nil, 'invalid_resolution_actor'
  end
  return {
    source = source,
    citizenid = citizenid,
    sessionToken = sessionToken,
    channel = channel
  }
end

local function audit(action, actor, reason, routeMasked)
  if type(actor) ~= 'table' then return end
  MZBankBridge.Log(action, actor.source, {
    channel = actor.channel,
    outcome = reason,
    route = routeMasked
  })
end

local function prune(values, threshold)
  local kept = {}
  for _, timestamp in ipairs(values or {}) do
    if tonumber(timestamp) and timestamp > threshold then kept[#kept + 1] = timestamp end
  end
  return kept
end

local function cleanupExpired(now)
  now = tonumber(now) or os.time()
  for token, resolution in pairs(resolutions) do
    if tonumber(resolution.expiresAt) <= now then resolutions[token] = nil end
  end
  for key, state in pairs(sessionLimits) do
    state.attempts = prune(state.attempts, now - tonumber(policy.SessionWindowSeconds))
    if #state.attempts == 0 and tonumber(state.cooldownUntil or 0) <= now then
      sessionLimits[key] = nil
    end
  end
  for citizenid, state in pairs(actorLimits) do
    state.attempts = prune(state.attempts, now - tonumber(policy.ActorWindowSeconds))
    if #state.attempts == 0 then actorLimits[citizenid] = nil end
  end
end

local function sessionLimitKey(actor)
  return table.concat({ actor.citizenid, actor.sessionToken, actor.channel }, '|')
end

local function admitAttempt(actor, now)
  cleanupExpired(now)
  local key = sessionLimitKey(actor)
  local sessionState = sessionLimits[key] or {
    source = actor.source,
    attempts = {},
    failures = 0,
    cooldownUntil = 0
  }
  sessionLimits[key] = sessionState
  local actorState = actorLimits[actor.citizenid] or { attempts = {} }
  actorLimits[actor.citizenid] = actorState

  if now < tonumber(sessionState.cooldownUntil or 0) then return false, 'cooldown' end
  if #sessionState.attempts >= tonumber(policy.SessionMaxAttempts) then
    return false, 'session_window'
  end
  if #actorState.attempts >= tonumber(policy.ActorMaxAttempts) then
    return false, 'actor_window'
  end
  sessionState.attempts[#sessionState.attempts + 1] = now
  actorState.attempts[#actorState.attempts + 1] = now
  return true, nil, sessionState
end

local function recordFailure(state, now)
  if type(state) ~= 'table' then return end
  state.failures = (tonumber(state.failures) or 0) + 1
  local threshold = tonumber(policy.CooldownAfterFailures)
  if state.failures < threshold then return end
  local exponent = math.min(state.failures - threshold, 8)
  local cooldown = math.min(
    tonumber(policy.CooldownBaseSeconds) * (2 ^ exponent),
    tonumber(policy.CooldownMaxSeconds)
  )
  state.cooldownUntil = now + cooldown
end

local function recordSuccess(state)
  if type(state) ~= 'table' then return end
  state.failures = 0
  state.cooldownUntil = 0
end

local function routeMasked(accountNumber, checkDigit)
  return ('****%s-%s'):format(accountNumber:sub(-4), checkDigit)
end

local function partialDisplayName(identity)
  local first = trim(identity and identity.firstname) or ''
  local last = trim(identity and identity.lastname) or ''
  if first == '' then return 'Cliente' end
  if last == '' then return first end
  return ('%s %s.'):format(first, last:sub(1, 1):upper())
end

local function activeTokenCount(source, now)
  local count = 0
  for _, resolution in pairs(resolutions) do
    if resolution.source == source and resolution.expiresAt > now then count = count + 1 end
  end
  return count
end

local function allocateToken()
  for _ = 1, 4 do
    local fragments = {}
    for index = 1, 4 do
      local callOk, fragment = pcall(MZBankRepository.getSecureAccountRandomHex)
      if not callOk or type(fragment) ~= 'string' or not fragment:match('^%x%x%x%x%x%x%x%x$') then
        return nil, 'secure_random_unavailable'
      end
      fragments[index] = fragment:lower()
    end
    local candidate = TOKEN_PREFIX .. table.concat(fragments)
    if not resolutions[candidate] then return candidate end
  end
  return nil, 'resolution_token_allocation_failed'
end

local function unavailable(actor, state, now, reason, masked)
  recordFailure(state, now)
  audit('bank.public_account.resolve.unavailable', actor, reason, masked)
  return { ok = false, error = 'recipient_unavailable', found = false }
end

function MZBankAccountResolution.GetStatus()
  return {
    enabled = enabled(),
    ready = runtimeReady(),
    error = not policyOk and policyError
      or (policy.Enabled ~= true and 'resolution_disabled'
        or (not runtimeReady() and 'public_account_unavailable' or nil)),
    tokenTtlSeconds = tonumber(policy.TokenTtlSeconds) or 0
  }
end

function MZBankAccountResolution.Resolve(actorValue, route)
  if not policyOk then return { ok = false, error = policyError } end
  if not runtimeReady() then return { ok = false, error = 'resolution_unavailable' } end
  local actor, actorError = copyActor(actorValue)
  if not actor then return { ok = false, error = actorError } end
  local now = os.time()
  local admitted, limitReason, state = admitAttempt(actor, now)
  if not admitted then
    audit('bank.public_account.resolve.rate_limited', actor, limitReason)
    return { ok = false, error = 'rate_limited', found = false }
  end

  route = type(route) == 'table' and route or {}
  local branch = route.branch
  local accountNumber = route.accountNumber
  local checkDigit = route.checkDigit
  local validRoute = MZBankAccountIdentity.ValidateRoute(branch, accountNumber, checkDigit)
  if validRoute ~= true then
    recordFailure(state, now)
    audit('bank.public_account.resolve.invalid', actor, 'invalid_route')
    return { ok = false, error = 'recipient_invalid', found = false }
  end
  local masked = routeMasked(accountNumber, checkDigit)

  local lookupOk, account, lookupError = pcall(
    MZBankRepository.getPublicAccountByRoute, branch, accountNumber, checkDigit
  )
  if not lookupOk or lookupError or type(account) ~= 'table' then
    return unavailable(actor, state, now, 'not_available', masked)
  end
  if MZBankAccountIdentity.IsValidStatus(tostring(account.status or '')) ~= true
      or MZBankAccountService.CanAccountPerform(account.status, 'receive') ~= true then
    return unavailable(actor, state, now, 'not_available', masked)
  end
  if tostring(account.citizenid or '') == actor.citizenid then
    recordFailure(state, now)
    audit('bank.public_account.resolve.self_transfer', actor, 'self_transfer', masked)
    return { ok = false, error = 'self_transfer', found = false }
  end

  local target = MZBankBridge.ResolvePlayerByCitizenId(account.citizenid)
  if not target then return unavailable(actor, state, now, 'not_available', masked) end
  if activeTokenCount(actor.source, now) >= tonumber(policy.MaxActiveTokensPerSource) then
    recordFailure(state, now)
    audit('bank.public_account.resolve.rate_limited', actor, 'token_capacity')
    return { ok = false, error = 'rate_limited', found = false }
  end
  local token, tokenError = allocateToken()
  if not token then
    audit('bank.public_account.resolve.unavailable', actor, tokenError)
    return { ok = false, error = 'resolution_unavailable', found = false }
  end

  local expiresAt = now + tonumber(policy.TokenTtlSeconds)
  resolutions[token] = {
    source = actor.source,
    actorCitizenId = actor.citizenid,
    sessionToken = actor.sessionToken,
    channel = actor.channel,
    accountId = account.id,
    targetCitizenId = account.citizenid,
    branch = branch,
    accountNumber = accountNumber,
    checkDigit = checkDigit,
    createdAt = now,
    expiresAt = expiresAt
  }
  recordSuccess(state)
  audit('bank.public_account.resolve.accepted', actor, 'accepted', masked)
  return {
    ok = true,
    found = true,
    resolutionToken = token,
    recipient = {
      displayName = partialDisplayName(target),
      branch = branch,
      accountMasked = masked,
      accountTypeLabel = 'Conta pessoal'
    },
    expiresIn = tonumber(policy.TokenTtlSeconds)
  }
end

function MZBankAccountResolution.ValidateResolutionToken(actorValue, tokenValue)
  if not policyOk then return nil, policyError end
  if not runtimeReady() then return nil, 'resolution_unavailable' end
  local actor, actorError = copyActor(actorValue)
  if not actor then return nil, actorError end
  local token = trim(tokenValue)
  if not token or not token:match('^p2e%-%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$') then
    audit('bank.public_account.resolve.token_rejected', actor, 'invalid_token')
    return nil, 'invalid_resolution_token'
  end
  cleanupExpired(os.time())
  local resolution = resolutions[token]
  if not resolution then
    audit('bank.public_account.resolve.token_rejected', actor, 'missing_or_expired')
    return nil, 'invalid_resolution_token'
  end
  if resolution.source ~= actor.source
      or resolution.actorCitizenId ~= actor.citizenid
      or resolution.sessionToken ~= actor.sessionToken
      or resolution.channel ~= actor.channel then
    audit('bank.public_account.resolve.token_rejected', actor, 'actor_mismatch')
    return nil, 'invalid_resolution_token'
  end

  local lookupOk, account = pcall(
    MZBankRepository.getPublicAccountByRoute,
    resolution.branch, resolution.accountNumber, resolution.checkDigit
  )
  if not lookupOk or type(account) ~= 'table'
      or tostring(account.id or '') ~= tostring(resolution.accountId or '')
      or tostring(account.citizenid or '') ~= tostring(resolution.targetCitizenId or '')
      or MZBankAccountService.CanAccountPerform(account.status, 'receive') ~= true then
    resolutions[token] = nil
    audit('bank.public_account.resolve.token_rejected', actor, 'target_unavailable')
    return nil, 'recipient_unavailable'
  end
  local target = MZBankBridge.ResolvePlayerByCitizenId(resolution.targetCitizenId)
  if not target then
    resolutions[token] = nil
    audit('bank.public_account.resolve.token_rejected', actor, 'target_unavailable')
    return nil, 'recipient_unavailable'
  end
  return {
    token = token,
    accountId = resolution.accountId,
    targetCitizenId = resolution.targetCitizenId,
    targetSource = target.source,
    branch = resolution.branch,
    accountNumber = resolution.accountNumber,
    checkDigit = resolution.checkDigit,
    expiresAt = resolution.expiresAt
  }
end

function MZBankAccountResolution.InvalidateResolutionToken(actorValue, tokenValue)
  local actor = copyActor(actorValue)
  if not actor then return false end
  local token = trim(tokenValue)
  local resolution = token and resolutions[token] or nil
  if not resolution or resolution.source ~= actor.source
      or resolution.actorCitizenId ~= actor.citizenid
      or resolution.sessionToken ~= actor.sessionToken
      or resolution.channel ~= actor.channel then
    return false
  end
  resolutions[token] = nil
  return true
end

function MZBankAccountResolution.CleanupSession(source, sessionToken)
  source = tonumber(source)
  for token, resolution in pairs(resolutions) do
    if resolution.source == source
        and (sessionToken == nil or resolution.sessionToken == sessionToken) then
      resolutions[token] = nil
    end
  end
  for key, state in pairs(sessionLimits) do
    if state.source == source then sessionLimits[key] = nil end
  end
end
