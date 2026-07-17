local RUNNER_CONVAR = 'mz_bank_p2b_runtime_runner'
local RUNNER_COMMAND = 'mz_bank_p2b_runtime_test'

-- This file is loaded server-side, but remains inert unless staging explicitly
-- enables the convar before mz_bank starts. In the default state it registers
-- no command, event, callback, export or thread.
if GetConvarInt(RUNNER_CONVAR, 0) ~= 1 then return end

local TEST_OWNER_A = 'P2B_RT_OWNER_A'
local TEST_OWNER_B = 'P2B_RT_OWNER_B'
local TEST_OWNER_MISSING = 'P2B_RT_MISSING'
local TEST_BRANCH = '0001'
local TEST_ACCOUNT_A = '87654321'
local TEST_DIGIT_A = '0'
local TEST_ACCOUNT_B = '99999999'
local TEST_DIGIT_B = '9'
local TEST_ACCOUNT_TYPE = 'personal'
local CONCURRENT_CALLS_PER_LOOKUP = 20
local CONCURRENT_TIMEOUT_MS = 20000

local running = false

local function log(message)
  print(('[mz_bank][p2b-runner] %s'):format(tostring(message)))
end

local function safeDetail(value)
  local detail = tostring(value or '')
    :gsub('[\r\n\t]', ' ')
    :gsub(TEST_OWNER_A, '<test-owner-a>')
    :gsub(TEST_OWNER_B, '<test-owner-b>')
    :gsub(TEST_OWNER_MISSING, '<test-owner-missing>')
  if #detail > 240 then detail = detail:sub(1, 240) .. '...' end
  return detail
end

local function validateRow(row, expectedOwner, expectedAccount, expectedDigit, expectedStatus)
  if type(row) ~= 'table' then return false, 'row_missing' end
  if row.citizenid ~= expectedOwner then return false, 'owner_mismatch' end
  if row.branch ~= TEST_BRANCH then return false, 'branch_mismatch' end
  if row.account_number ~= expectedAccount then return false, 'account_mismatch' end
  if row.check_digit ~= expectedDigit then return false, 'digit_mismatch' end
  if row.account_type ~= TEST_ACCOUNT_TYPE then return false, 'account_type_mismatch' end
  if row.status ~= expectedStatus then return false, 'status_mismatch' end
  return true
end

local function callOwner(owner)
  return MZBankRepository.getPublicAccountByOwner(owner)
end

local function callRoute(accountNumber, checkDigit)
  return MZBankRepository.getPublicAccountByRoute(TEST_BRANCH, accountNumber, checkDigit)
end

local function runCase(results, testId, handler)
  local ok, passed, detail = pcall(handler)
  if not ok then
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

local function readinessCase()
  if type(Config.PublicAccount) ~= 'table' or Config.PublicAccount.Enabled ~= false then
    return false, 'public_account_feature_not_disabled'
  end
  local status = exports[GetCurrentResourceName()]:GetReadiness()
  if type(status) ~= 'table' then return false, 'readiness_missing' end
  if status.ready ~= true then return false, 'resource_not_ready' end
  local migration = status.migration
  if type(migration) ~= 'table' then return false, 'migration_status_missing' end
  if migration.ready ~= true then return false, 'migration_not_ready' end
  if tonumber(migration.currentVersion) ~= 3 then return false, 'current_version_mismatch' end
  if tonumber(migration.expectedVersion) ~= 3 then return false, 'expected_version_mismatch' end
  return true, 'ready=true schema_version=3 feature_enabled=false'
end

local function repeatedOwnerCase()
  local first, firstError = callOwner(TEST_OWNER_A)
  if firstError ~= nil then return false, 'first_lookup_error' end
  local valid, reason = validateRow(first, TEST_OWNER_A, TEST_ACCOUNT_A, TEST_DIGIT_A, 'active')
  if not valid then return false, reason end

  local second, secondError = callOwner(TEST_OWNER_A)
  if secondError ~= nil then return false, 'second_lookup_error' end
  valid, reason = validateRow(second, TEST_OWNER_A, TEST_ACCOUNT_A, TEST_DIGIT_A, 'active')
  if not valid then return false, reason end
  if first.id ~= second.id then return false, 'identity_changed_between_reads' end
  return true, 'reads=2 route=0001/****4321-0 status=active'
end

local function missingOwnerCase()
  local row, err = callOwner(TEST_OWNER_MISSING)
  if row ~= nil then return false, 'unexpected_row' end
  if err ~= nil then return false, 'unexpected_error' end
  return true, 'missing_owner=nil'
end

local function invalidOwnerCase()
  local vectors = {
    { value = '', expected = 'invalid_citizenid' },
    { value = ' P2B_RT_OWNER_A', expected = 'invalid_citizenid' },
    { value = string.rep('X', 33), expected = 'invalid_citizenid' },
    { value = false, expected = 'invalid_citizenid' }
  }
  for index, vector in ipairs(vectors) do
    local row, err = callOwner(vector.value)
    if row ~= nil or err ~= vector.expected then
      return false, ('invalid_owner_vector_%s'):format(index)
    end
  end
  return true, ('vectors=%s rejected'):format(#vectors)
end

local function routeCase()
  local rowA, errorA = callRoute(TEST_ACCOUNT_A, TEST_DIGIT_A)
  if errorA ~= nil then return false, 'route_a_error' end
  local valid, reason = validateRow(rowA, TEST_OWNER_A, TEST_ACCOUNT_A, TEST_DIGIT_A, 'active')
  if not valid then return false, reason end

  local rowB, errorB = callRoute(TEST_ACCOUNT_B, TEST_DIGIT_B)
  if errorB ~= nil then return false, 'route_b_error' end
  valid, reason = validateRow(rowB, TEST_OWNER_B, TEST_ACCOUNT_B, TEST_DIGIT_B, 'blocked')
  if not valid then return false, reason end
  return true, 'routes=2 masked=0001/****4321-0,0001/****9999-9'
end

local function invalidRouteCase()
  local vectors = {
    { branch = TEST_BRANCH, account = TEST_ACCOUNT_A, digit = '1', expected = 'invalid_check_digit' },
    { branch = '001', account = TEST_ACCOUNT_A, digit = TEST_DIGIT_A, expected = 'invalid_branch' },
    { branch = TEST_BRANCH, account = '1234567', digit = TEST_DIGIT_A, expected = 'invalid_account_number' },
    { branch = TEST_BRANCH, account = '00000000', digit = '0', expected = 'reserved_account_number' },
    { branch = TEST_BRANCH, account = TEST_ACCOUNT_A, digit = 'X', expected = 'invalid_check_digit' },
    { branch = false, account = TEST_ACCOUNT_A, digit = TEST_DIGIT_A, expected = 'invalid_branch' },
    { branch = TEST_BRANCH, account = false, digit = TEST_DIGIT_A, expected = 'invalid_account_number' },
    { branch = TEST_BRANCH, account = TEST_ACCOUNT_A, digit = false, expected = 'invalid_check_digit' }
  }
  for index, vector in ipairs(vectors) do
    local row, err = MZBankRepository.getPublicAccountByRoute(
      vector.branch, vector.account, vector.digit
    )
    if row ~= nil or err ~= vector.expected then
      return false, ('invalid_route_vector_%s expected_%s'):format(index, vector.expected)
    end
  end
  return true, ('vectors=%s rejected'):format(#vectors)
end

local function concurrentReadsCase()
  local expectedCalls = CONCURRENT_CALLS_PER_LOOKUP * 2
  local completed = 0
  local failures = 0

  local function finish(ok)
    if ok ~= true then failures = failures + 1 end
    completed = completed + 1
  end

  for _ = 1, CONCURRENT_CALLS_PER_LOOKUP do
    CreateThread(function()
      local ok, row, err = pcall(callOwner, TEST_OWNER_A)
      local valid = false
      if ok and err == nil then
        valid = validateRow(row, TEST_OWNER_A, TEST_ACCOUNT_A, TEST_DIGIT_A, 'active')
      end
      finish(valid == true)
    end)

    CreateThread(function()
      local ok, row, err = pcall(callRoute, TEST_ACCOUNT_A, TEST_DIGIT_A)
      local valid = false
      if ok and err == nil then
        valid = validateRow(row, TEST_OWNER_A, TEST_ACCOUNT_A, TEST_DIGIT_A, 'active')
      end
      finish(valid == true)
    end)
  end

  local waited = 0
  while completed < expectedCalls and waited < CONCURRENT_TIMEOUT_MS do
    Wait(25)
    waited = waited + 25
  end

  if completed ~= expectedCalls then
    return false, ('timeout completed=%s expected=%s'):format(completed, expectedCalls)
  end
  if failures ~= 0 then
    return false, ('calls=%s failures=%s'):format(completed, failures)
  end
  return true, ('calls=%s failures=0 writes=0_by_runner'):format(completed)
end

local function stateCase()
  local ownerA = callOwner(TEST_OWNER_A)
  local ownerB = callOwner(TEST_OWNER_B)
  local routeA = callRoute(TEST_ACCOUNT_A, TEST_DIGIT_A)
  local routeB = callRoute(TEST_ACCOUNT_B, TEST_DIGIT_B)
  if type(ownerA) ~= 'table' or ownerA.status ~= 'active' then return false, 'owner_a_status' end
  if type(routeA) ~= 'table' or routeA.status ~= 'active' then return false, 'route_a_status' end
  if type(ownerB) ~= 'table' or ownerB.status ~= 'blocked' then return false, 'owner_b_status' end
  if type(routeB) ~= 'table' or routeB.status ~= 'blocked' then return false, 'route_b_status' end
  return true, 'states=active,blocked preserved'
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
  if type(MZBankRepository) ~= 'table'
      or type(MZBankRepository.getPublicAccountByOwner) ~= 'function'
      or type(MZBankRepository.getPublicAccountByRoute) ~= 'function' then
    log('FAIL P2B-RUNNER-PREFLIGHT detail=repository_unavailable')
    return
  end

  running = true
  local results = { passed = 0, failed = 0 }
  log('START fixed_test_vectors=true writes=disabled client_input=false')

  runCase(results, 'P2B-INIT-01', readinessCase)
  runCase(results, 'P2B-REPO-01', repeatedOwnerCase)
  runCase(results, 'P2B-REPO-02', missingOwnerCase)
  runCase(results, 'P2B-REPO-03', invalidOwnerCase)
  runCase(results, 'P2B-REPO-04', routeCase)
  runCase(results, 'P2B-REPO-05', invalidRouteCase)
  runCase(results, 'P2B-REPO-06', concurrentReadsCase)
  runCase(results, 'P2B-STATE-01', stateCase)

  log(('SUMMARY executed=%s passed=%s failed=%s'):format(
    results.passed + results.failed, results.passed, results.failed
  ))
  log('END run SQL snapshots and manual cases; disable convar and restart mz_bank')
  running = false
end, true)

log(('enabled staging_only=true command=%s source=console fixed_vectors=true'):format(
  RUNNER_COMMAND
))
