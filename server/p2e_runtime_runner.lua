local RUNNER_CONVAR = 'mz_bank_p2e_runtime_runner'
local RUNNER_COMMAND = 'mz_bank_p2e_runtime_test'

-- Staging-only. With the default convar value this file returns before it can
-- register a command, event, callback, export or thread.
if GetConvarInt(RUNNER_CONVAR, 0) ~= 1 then return end

local TEST_BRANCH = '0001'
local TEST_SOURCE_BASE = 65100
local CONCURRENT_CALLS = 20
local CONCURRENT_TIMEOUT_MS = 30000

local running = false
local capturedAudits = {}
local financeCalls = 0

local originals = {}
local fixtures = {}
local online = {}

local function log(message)
  print(('[mz_bank][p2e-runner] %s'):format(tostring(message)))
end

local function safeDetail(value)
  local detail = tostring(value or '')
    :gsub('[\r\n\t]', ' ')
    :gsub('P2E_RT_[%w_%-]+', '<test-identity>')
    :gsub('p2e%-%x+', '<resolution-token>')
    :gsub('(%d%d%d%d)/(%d%d%d%d)(%d%d%d%d)%-(%d)', '%1/****%3-%4')
  if #detail > 240 then detail = detail:sub(1, 240) .. '...' end
  return detail
end

local function runCase(results, testId, handler)
  local callOk, passed, detail = pcall(handler)
  if not callOk then
    results.failed = results.failed + 1
    log(('FAIL %s detail=%s'):format(testId, safeDetail(passed)))
    return
  end
  if passed ~= true then
    results.failed = results.failed + 1
    log(('FAIL %s detail=%s'):format(testId, safeDetail(detail or 'assertion_failed')))
    return
  end
  results.passed = results.passed + 1
  log(('PASS %s detail=%s'):format(testId, safeDetail(detail or 'ok')))
end

local function actor(caseNumber, suffix, source)
  suffix = tostring(suffix or 'a')
  return {
    source = source or (TEST_SOURCE_BASE + caseNumber),
    citizenid = ('P2E_RT_A%02d_%s'):format(caseNumber, suffix),
    sessionToken = ('p2e-runtime-session-%02d-%s'):format(caseNumber, suffix),
    channel = 'atm'
  }
end

local function routeKey(branch, accountNumber, checkDigit)
  return table.concat({ branch, accountNumber, checkDigit }, '|')
end

local function makeFixture(id, citizenid, accountNumber, status, identity)
  local checkDigit, digitError = MZBankAccountIdentity.CalculateCheckDigit(
    TEST_BRANCH, accountNumber
  )
  if not checkDigit then error(digitError or 'fixture_digit_failed') end
  local row = {
    id = id,
    citizenid = citizenid,
    branch = TEST_BRANCH,
    account_number = accountNumber,
    check_digit = checkDigit,
    account_type = 'personal',
    status = status
  }
  fixtures[routeKey(TEST_BRANCH, accountNumber, checkDigit)] = row
  if identity then
    online[citizenid] = {
      source = identity.source,
      citizenid = citizenid,
      firstname = identity.firstname,
      lastname = identity.lastname,
      displayName = ('%s %s'):format(identity.firstname, identity.lastname)
    }
  end
  return row
end

local function installFixtures()
  fixtures = {}
  online = {}
  capturedAudits = {}
  financeCalls = 0

  originals.routeLookup = MZBankRepository.getPublicAccountByRoute
  originals.resolvePlayer = MZBankBridge.ResolvePlayerByCitizenId
  originals.log = MZBankBridge.Log
  originals.transferPlayers = MZBankBridge.TransferBankBetweenPlayers
  originals.transferOwn = MZBankBridge.TransferBetweenOwnAccounts

  local data = {
    active = makeFixture(920001, 'P2E_RT_TARGET_ACTIVE', '12345678', 'active', {
      source = 65201, firstname = 'Ana', lastname = 'Silva'
    }),
    blocked = makeFixture(920002, 'P2E_RT_TARGET_BLOCKED', '87654321', 'blocked', {
      source = 65202, firstname = 'Bruno', lastname = 'Costa'
    }),
    frozen = makeFixture(920003, 'P2E_RT_TARGET_FROZEN', '22222222', 'frozen', {
      source = 65203, firstname = 'Caio', lastname = 'Lima'
    }),
    closed = makeFixture(920004, 'P2E_RT_TARGET_CLOSED', '11111111', 'closed', {
      source = 65204, firstname = 'Dora', lastname = 'Souza'
    }),
    offline = makeFixture(920005, 'P2E_RT_TARGET_OFFLINE', '99999999', 'active', nil),
    self = makeFixture(920006, 'P2E_RT_SELF', '55555555', 'active', {
      source = 65206, firstname = 'Eva', lastname = 'Rocha'
    })
  }

  MZBankRepository.getPublicAccountByRoute = function(branch, accountNumber, checkDigit)
    local row = fixtures[routeKey(branch, accountNumber, checkDigit)]
    if not row then return nil end
    local copy = {}
    for key, value in pairs(row) do copy[key] = value end
    return copy
  end

  MZBankBridge.ResolvePlayerByCitizenId = function(citizenid)
    local identity = online[citizenid]
    if not identity then return nil, 'player_not_loaded' end
    local copy = {}
    for key, value in pairs(identity) do copy[key] = value end
    return copy
  end

  MZBankBridge.Log = function(action, source, payload)
    capturedAudits[#capturedAudits + 1] = {
      action = action,
      source = source,
      payload = payload
    }
    pcall(originals.log, action, source, payload)
  end

  MZBankBridge.TransferBankBetweenPlayers = function(...)
    financeCalls = financeCalls + 1
    return { ok = false, error = 'runtime_runner_finance_forbidden' }
  end
  MZBankBridge.TransferBetweenOwnAccounts = function(...)
    financeCalls = financeCalls + 1
    return { ok = false, error = 'runtime_runner_finance_forbidden' }
  end

  return data
end

local function restoreDependencies()
  if originals.routeLookup then
    MZBankRepository.getPublicAccountByRoute = originals.routeLookup
  end
  if originals.resolvePlayer then
    MZBankBridge.ResolvePlayerByCitizenId = originals.resolvePlayer
  end
  if originals.log then MZBankBridge.Log = originals.log end
  if originals.transferPlayers then
    MZBankBridge.TransferBankBetweenPlayers = originals.transferPlayers
  end
  if originals.transferOwn then
    MZBankBridge.TransferBetweenOwnAccounts = originals.transferOwn
  end
end

local function cleanupTestSources()
  for source = TEST_SOURCE_BASE, TEST_SOURCE_BASE + 200 do
    MZBankAccountResolution.CleanupSession(source)
  end
end

local function publicRoute(row)
  return {
    branch = row.branch,
    accountNumber = row.account_number,
    checkDigit = row.check_digit
  }
end

local function statusCase()
  local status = MZBankAccountResolution.GetStatus()
  if type(status) ~= 'table' or status.ready ~= true or status.enabled ~= true then
    return false, 'resolution_not_ready'
  end
  if tonumber(status.tokenTtlSeconds) ~= 60 then return false, 'ttl_not_60' end
  return true, 'ready=true enabled=true ttl=60 private=true'
end

local function activeDtoCase(data)
  local testActor = actor(2)
  local result = MZBankAccountResolution.Resolve(testActor, publicRoute(data.active))
  if type(result) ~= 'table' or result.ok ~= true or result.found ~= true then
    return false, result and result.error or 'result_missing'
  end
  if result.expiresIn ~= 60
      or type(result.resolutionToken) ~= 'string'
      or not result.resolutionToken:match('^p2e%-%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$') then
    return false, 'token_contract_invalid'
  end
  local recipient = result.recipient
  if type(recipient) ~= 'table' or recipient.displayName ~= 'Ana S.'
      or recipient.branch ~= TEST_BRANCH
      or recipient.accountMasked ~= ('****5678-%s'):format(data.active.check_digit)
      or recipient.accountTypeLabel ~= 'Conta pessoal' then
    return false, 'recipient_dto_invalid'
  end
  local encoded = json.encode(result)
  if encoded:find(data.active.citizenid, 1, true)
      or encoded:find(data.active.account_number, 1, true)
      or encoded:lower():find('status', 1, true) then
    return false, 'dto_contains_internal_data'
  end
  local resolved, tokenError = MZBankAccountResolution.ValidateResolutionToken(
    testActor, result.resolutionToken
  )
  if not resolved or tokenError or resolved.targetCitizenId ~= data.active.citizenid then
    return false, 'token_validation_failed'
  end
  return true, ('dto=masked name=partial token=opaque ttl=%s'):format(result.expiresIn)
end

local function blockedCase(data)
  local result = MZBankAccountResolution.Resolve(actor(3), publicRoute(data.blocked))
  if type(result) ~= 'table' or result.ok ~= true then
    return false, result and result.error or 'result_missing'
  end
  local encoded = json.encode(result)
  if encoded:lower():find('blocked', 1, true)
      or encoded:find(data.blocked.citizenid, 1, true) then
    return false, 'blocked_state_exposed'
  end
  return true, 'blocked=receivable state=private'
end

local function unavailableCase(data)
  local invalid = MZBankAccountResolution.Resolve(actor(4, 'invalid'), {
    branch = '1', accountNumber = 'abc', checkDigit = 'x'
  })
  if type(invalid) ~= 'table' or invalid.error ~= 'recipient_invalid'
      or invalid.found ~= false then return false, 'invalid_route_contract' end

  local missingNumber = '33333333'
  local missingDigit = MZBankAccountIdentity.CalculateCheckDigit(TEST_BRANCH, missingNumber)
  local vectors = {
    { name = 'missing', route = {
      branch = TEST_BRANCH, accountNumber = missingNumber, checkDigit = missingDigit
    } },
    { name = 'frozen', route = publicRoute(data.frozen) },
    { name = 'closed', route = publicRoute(data.closed) },
    { name = 'offline', route = publicRoute(data.offline) }
  }
  for index, vector in ipairs(vectors) do
    local result = MZBankAccountResolution.Resolve(actor(4, vector.name, TEST_SOURCE_BASE + 40 + index), vector.route)
    if type(result) ~= 'table' or result.ok == true
        or result.error ~= 'recipient_unavailable' or result.found ~= false
        or result.recipient ~= nil or result.resolutionToken ~= nil then
      return false, ('availability_shape_%s'):format(vector.name)
    end
  end
  return true, 'invalid=recipient_invalid unavailable_vectors=4 uniform=true'
end

local function selfCase(data)
  local testActor = actor(5)
  testActor.citizenid = data.self.citizenid
  local result = MZBankAccountResolution.Resolve(testActor, publicRoute(data.self))
  if type(result) ~= 'table' or result.error ~= 'self_transfer'
      or result.found ~= false or result.resolutionToken ~= nil then
    return false, 'self_transfer_contract'
  end
  return true, 'self_transfer=denied token=false'
end

local function tokenBindingCase(data)
  local testActor = actor(6)
  local result = MZBankAccountResolution.Resolve(testActor, publicRoute(data.active))
  if type(result) ~= 'table' or result.ok ~= true then return false, 'token_issue_failed' end
  local token = result.resolutionToken
  local valid = MZBankAccountResolution.ValidateResolutionToken(testActor, token)
  if not valid then return false, 'original_context_rejected' end

  local wrongActors = {
    { source = testActor.source + 1, citizenid = testActor.citizenid,
      sessionToken = testActor.sessionToken, channel = testActor.channel },
    { source = testActor.source, citizenid = 'P2E_RT_OTHER',
      sessionToken = testActor.sessionToken, channel = testActor.channel },
    { source = testActor.source, citizenid = testActor.citizenid,
      sessionToken = testActor.sessionToken .. '-other', channel = testActor.channel },
    { source = testActor.source, citizenid = testActor.citizenid,
      sessionToken = testActor.sessionToken, channel = 'branch' }
  }
  for _, wrongActor in ipairs(wrongActors) do
    local value, err = MZBankAccountResolution.ValidateResolutionToken(wrongActor, token)
    if value ~= nil or err ~= 'invalid_resolution_token' then
      return false, 'token_binding_bypass'
    end
  end
  local fake, fakeError = MZBankAccountResolution.ValidateResolutionToken(
    testActor, 'p2e-' .. string.rep('0', 32)
  )
  if fake ~= nil or fakeError ~= 'invalid_resolution_token' then return false, 'fake_token_accepted' end

  local cleanupResult = MZBankAccountResolution.Resolve(testActor, publicRoute(data.active))
  if type(cleanupResult) ~= 'table' or cleanupResult.ok ~= true then
    return false, 'cleanup_token_issue_failed'
  end
  MZBankAccountResolution.CleanupSession(testActor.source, testActor.sessionToken)
  local cleaned, cleanedError = MZBankAccountResolution.ValidateResolutionToken(
    testActor, cleanupResult.resolutionToken
  )
  if cleaned ~= nil or cleanedError ~= 'invalid_resolution_token' then
    return false, 'cleanup_did_not_invalidate'
  end

  local originalTime = os.time
  local clock = originalTime()
  os.time = function() return clock end
  local expiryOk, expiryDetail = pcall(function()
    local expiryActor = actor(6, 'expiry', TEST_SOURCE_BASE + 66)
    local issued = MZBankAccountResolution.Resolve(expiryActor, publicRoute(data.active))
    if type(issued) ~= 'table' or issued.ok ~= true then error('expiry_issue_failed') end
    clock = clock + 61
    local expired, expiredError = MZBankAccountResolution.ValidateResolutionToken(
      expiryActor, issued.resolutionToken
    )
    if expired ~= nil or expiredError ~= 'invalid_resolution_token' then
      error('expired_token_accepted')
    end
  end)
  os.time = originalTime
  if not expiryOk then return false, expiryDetail end
  return true, 'binding=source,citizenid,session,channel ttl=60 cleanup=true'
end

local function targetRevalidationCase(data)
  local testActor = actor(7)
  local first = MZBankAccountResolution.Resolve(testActor, publicRoute(data.active))
  if type(first) ~= 'table' or first.ok ~= true then return false, 'first_issue_failed' end
  data.active.status = 'frozen'
  local frozen, frozenError = MZBankAccountResolution.ValidateResolutionToken(
    testActor, first.resolutionToken
  )
  data.active.status = 'active'
  if frozen ~= nil or frozenError ~= 'recipient_unavailable' then
    return false, 'state_not_revalidated'
  end

  local second = MZBankAccountResolution.Resolve(testActor, publicRoute(data.active))
  if type(second) ~= 'table' or second.ok ~= true then return false, 'second_issue_failed' end
  local identity = online[data.active.citizenid]
  online[data.active.citizenid] = nil
  local offlineResult, offlineError = MZBankAccountResolution.ValidateResolutionToken(
    testActor, second.resolutionToken
  )
  online[data.active.citizenid] = identity
  if offlineResult ~= nil or offlineError ~= 'recipient_unavailable' then
    return false, 'online_state_not_revalidated'
  end
  return true, 'status_and_online_revalidated token_removed=true'
end

local function sessionLimitCase(data)
  local testActor = actor(8)
  for index = 1, 5 do
    local result = MZBankAccountResolution.Resolve(testActor, publicRoute(data.active))
    if type(result) ~= 'table' or result.ok ~= true then
      return false, ('attempt_%s_failed'):format(index)
    end
  end
  local sixth = MZBankAccountResolution.Resolve(testActor, publicRoute(data.active))
  if type(sixth) ~= 'table' or sixth.error ~= 'rate_limited' then
    return false, 'sixth_not_limited'
  end
  return true, 'attempts=5 admitted=5 sixth=rate_limited window=60'
end

local function actorLimitAndCooldownCase()
  local actorCitizenId = 'P2E_RT_A09_LIMIT'
  local invalidRoute = { branch = '1', accountNumber = 'bad', checkDigit = 'x' }
  for index = 1, 20 do
    local testActor = actor(9, ('limit-%02d'):format(index), TEST_SOURCE_BASE + 90)
    testActor.citizenid = actorCitizenId
    local result = MZBankAccountResolution.Resolve(testActor, invalidRoute)
    if type(result) ~= 'table' or result.error ~= 'recipient_invalid' then
      return false, ('actor_attempt_%s_unexpected'):format(index)
    end
  end
  local twentyFirstActor = actor(9, 'limit-21', TEST_SOURCE_BASE + 90)
  twentyFirstActor.citizenid = actorCitizenId
  local twentyFirst = MZBankAccountResolution.Resolve(twentyFirstActor, invalidRoute)
  if type(twentyFirst) ~= 'table' or twentyFirst.error ~= 'rate_limited' then
    return false, 'twenty_first_not_limited'
  end

  local cooldownActor = actor(9, 'cooldown', TEST_SOURCE_BASE + 99)
  for index = 1, 3 do
    local result = MZBankAccountResolution.Resolve(cooldownActor, invalidRoute)
    if type(result) ~= 'table' or result.error ~= 'recipient_invalid' then
      return false, ('cooldown_failure_%s_unexpected'):format(index)
    end
  end
  local cooldown = MZBankAccountResolution.Resolve(cooldownActor, invalidRoute)
  if type(cooldown) ~= 'table' or cooldown.error ~= 'rate_limited' then
    return false, 'cooldown_not_enforced'
  end
  return true, 'actor_attempts=20 twenty_first=limited cooldown_after=3'
end

local function concurrencyCase(data)
  local completed = 0
  local failures = 0
  local tokens = {}
  local source = TEST_SOURCE_BASE + 100
  local citizenid = 'P2E_RT_A10'

  for index = 1, CONCURRENT_CALLS do
    CreateThread(function()
      local testActor = actor(10, ('concurrent-%02d'):format(index), source)
      testActor.citizenid = citizenid
      local callOk, result = pcall(
        MZBankAccountResolution.Resolve, testActor, publicRoute(data.active)
      )
      if not callOk or type(result) ~= 'table' or result.ok ~= true
          or type(result.resolutionToken) ~= 'string'
          or tokens[result.resolutionToken] then
        failures = failures + 1
      else
        tokens[result.resolutionToken] = true
      end
      completed = completed + 1
    end)
  end

  local waited = 0
  while completed < CONCURRENT_CALLS and waited < CONCURRENT_TIMEOUT_MS do
    Wait(25)
    waited = waited + 25
  end
  if completed ~= CONCURRENT_CALLS then
    return false, ('timeout completed=%s expected=%s'):format(completed, CONCURRENT_CALLS)
  end
  if failures ~= 0 then return false, ('concurrent_failures=%s'):format(failures) end

  local excessActor = actor(10, 'excess', source)
  excessActor.citizenid = citizenid
  local excess = MZBankAccountResolution.Resolve(excessActor, publicRoute(data.active))
  if type(excess) ~= 'table' or excess.error ~= 'rate_limited' then
    return false, 'token_capacity_not_enforced'
  end
  local tokenCount = 0
  for _ in pairs(tokens) do tokenCount = tokenCount + 1 end
  if tokenCount ~= CONCURRENT_CALLS then return false, 'token_uniqueness_failed' end
  return true, ('concurrent=%s unique=%s excess=denied'):format(completed, tokenCount)
end

local function auditPrivacyCase(data)
  local required = {
    ['bank.public_account.resolve.accepted'] = false,
    ['bank.public_account.resolve.invalid'] = false,
    ['bank.public_account.resolve.unavailable'] = false,
    ['bank.public_account.resolve.rate_limited'] = false,
    ['bank.public_account.resolve.self_transfer'] = false,
    ['bank.public_account.resolve.token_rejected'] = false
  }
  for _, row in ipairs(capturedAudits) do
    if required[row.action] ~= nil then required[row.action] = true end
    local encoded = json.encode(row.payload or {})
    local lowered = encoded:lower()
    if lowered:find('citizenid', 1, true)
        or lowered:find('license', 1, true)
        or lowered:find('resolutiontoken', 1, true)
        or lowered:find('account_number', 1, true)
        or encoded:find(data.active.account_number, 1, true)
        or encoded:find('p2e-', 1, true)
        or encoded:find(data.active.citizenid, 1, true) then
      return false, 'audit_contains_sensitive_data'
    end
  end
  for action, observed in pairs(required) do
    if not observed then return false, ('audit_action_missing:%s'):format(action) end
  end
  return true, ('rows=%s actions=6 pii=false tokens=false'):format(#capturedAudits)
end

local function noFinanceCase()
  if financeCalls ~= 0 then return false, ('finance_calls=%s'):format(financeCalls) end
  return true, 'finance_calls=0 balance_writes=0 manual_physical_smoke=pending'
end

local function preflight()
  if type(MZBankAccountResolution) ~= 'table'
      or type(MZBankAccountResolution.Resolve) ~= 'function'
      or type(MZBankAccountResolution.ValidateResolutionToken) ~= 'function'
      or type(MZBankAccountResolution.CleanupSession) ~= 'function' then
    return false, 'resolution_service_unavailable'
  end
  if type(MZBankRepository) ~= 'table'
      or type(MZBankRepository.getPublicAccountByRoute) ~= 'function'
      or type(MZBankRepository.getSecureAccountRandomHex) ~= 'function' then
    return false, 'repository_unavailable'
  end
  if type(MZBankBridge) ~= 'table'
      or type(MZBankBridge.ResolvePlayerByCitizenId) ~= 'function'
      or type(MZBankBridge.Log) ~= 'function' then
    return false, 'bridge_unavailable'
  end
  local status = MZBankAccountResolution.GetStatus()
  if type(status) ~= 'table' or status.ready ~= true or status.enabled ~= true then
    return false, status and status.error or 'resolution_not_ready'
  end
  local randomHex = MZBankRepository.getSecureAccountRandomHex()
  if type(randomHex) ~= 'string' or not randomHex:match('^%x%x%x%x%x%x%x%x$') then
    return false, 'secure_random_unavailable'
  end
  return true
end

RegisterCommand(RUNNER_COMMAND, function(source, args)
  if source ~= 0 then return end
  if type(args) == 'table' and #args > 0 then
    log(('usage: %s'):format(RUNNER_COMMAND))
    return
  end
  if running then
    log('refused reason=already_running')
    return
  end
  local ready, readyError = preflight()
  if not ready then
    log(('FAIL P2E-RUNNER-PREFLIGHT detail=%s'):format(safeDetail(readyError)))
    return
  end

  running = true
  cleanupTestSources()
  local results = { passed = 0, failed = 0 }
  local suiteOk, suiteError = pcall(function()
    local data = installFixtures()
    log('START staging_only=true fixtures=memory writes=logs_only balances=false client_input=false')

    runCase(results, 'P2E-01', statusCase)
    runCase(results, 'P2E-02', function() return activeDtoCase(data) end)
    runCase(results, 'P2E-03', function() return blockedCase(data) end)
    runCase(results, 'P2E-04', function() return unavailableCase(data) end)
    runCase(results, 'P2E-05', function() return selfCase(data) end)
    runCase(results, 'P2E-06', function() return tokenBindingCase(data) end)
    runCase(results, 'P2E-07', function() return targetRevalidationCase(data) end)
    runCase(results, 'P2E-08', function() return sessionLimitCase(data) end)
    runCase(results, 'P2E-09', actorLimitAndCooldownCase)
    runCase(results, 'P2E-10', function() return concurrencyCase(data) end)
    runCase(results, 'P2E-11', function() return auditPrivacyCase(data) end)
    runCase(results, 'P2E-12-INTERNAL', noFinanceCase)
  end)

  restoreDependencies()
  cleanupTestSources()
  if not suiteOk then
    results.failed = results.failed + 1
    log(('FAIL P2E-RUNNER-SUITE detail=%s'):format(safeDetail(suiteError)))
  end

  log(('SUMMARY executed=%s passed=%s failed=%s'):format(
    results.passed + results.failed, results.passed, results.failed
  ))
  log('END dependencies=restored manual=P2E-12_physical_smoke disable_runner_and_restart=true')
  running = false
end, true)

log(('enabled staging_only=true command=%s source=console fixtures=memory writes=logs_only'):format(
  RUNNER_COMMAND
))
