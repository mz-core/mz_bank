local RUNNER_CONVAR = 'mz_bank_p2d_runtime_runner'
local RUNNER_COMMAND = 'mz_bank_p2d_runtime_test'

-- Staging-only. In the default state this file returns before registering a
-- command, event, callback, export or thread.
if GetConvarInt(RUNNER_CONVAR, 0) ~= 1 then return end

local TEST_ACTOR = 'p2d-runtime-runner'
local TEST_OWNER_CLOSED = 'P2D_RT_CLOSED'
local TEST_OWNER_COLLISION = 'P2D_RT_COLLISION'
local TEST_OWNER_FAILURE = 'P2D_RT_FAILURE'
local CONFIRMATION = 'APPLY_PUBLIC_ACCOUNT_BACKFILL'
local CONCURRENT_PREVIEWS = 8
local CONCURRENT_TIMEOUT_MS = 20000

local running = false
local syntheticRunRef = nil

local function log(message)
  print(('[mz_bank][p2d-runner] %s'):format(tostring(message)))
end

local function safeDetail(value)
  local detail = tostring(value or '')
    :gsub('[\r\n\t]', ' ')
    :gsub(TEST_OWNER_CLOSED, '<test-closed>')
    :gsub(TEST_OWNER_COLLISION, '<test-collision>')
    :gsub(TEST_OWNER_FAILURE, '<test-failure>')
  if #detail > 240 then detail = detail:sub(1, 240) .. '...' end
  return detail
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

local function expectError(result, expected)
  return type(result) == 'table' and result.ok ~= true and result.error == expected
end

local function preflight()
  if type(MZBankAccountBackfill) ~= 'table'
      or type(MZBankAccountBackfill.Preview) ~= 'function'
      or type(MZBankAccountBackfill.Apply) ~= 'function' then
    return false, 'backfill_unavailable'
  end
  if type(MZBankRepository) ~= 'table'
      or type(MZBankRepository.listPublicAccountBackfillRows) ~= 'function' then
    return false, 'repository_unavailable'
  end
  if type(MZBankAccountService) ~= 'table'
      or type(MZBankAccountService.EnsurePersonalAccount) ~= 'function' then
    return false, 'account_service_unavailable'
  end
  local status = MZBankAccountBackfill.GetStatus()
  if type(status) ~= 'table' or status.ready ~= true then return false, 'backfill_not_ready' end
  if status.applyEnabled ~= true then return false, 'backfill_apply_not_enabled' end
  local runtime = MZBankAccountService.GetRuntimeStatus()
  if MZBankAccountService.IsEnabled() ~= true
      or type(runtime) ~= 'table' or runtime.ready ~= true then
    return false, 'public_account_not_ready'
  end
  return true
end

local function argumentsAndAuthorizationCase()
  local aceOk, aceAllowed = pcall(
    IsPrincipalAceAllowed, 'group.mz_owner', 'mz_bank.accounts.backfill'
  )
  local normalizedAce = tostring(aceAllowed):lower()
  if not aceOk or not (aceAllowed == true or aceAllowed == 1
      or normalizedAce == '1' or normalizedAce == 'true') then
    return false, 'owner_ace_missing'
  end

  local previewVectors = {
    { MZBankAccountBackfill.Preview(0, 0, TEST_ACTOR), 'invalid_batch_size' },
    { MZBankAccountBackfill.Preview(501, 0, TEST_ACTOR), 'invalid_batch_size' },
    { MZBankAccountBackfill.Preview('text', 0, TEST_ACTOR), 'invalid_batch_size' },
    { MZBankAccountBackfill.Preview(1, -1, TEST_ACTOR), 'invalid_after_player_id' },
    { MZBankAccountBackfill.Preview(1, 'text', TEST_ACTOR), 'invalid_after_player_id' }
  }
  for index, vector in ipairs(previewVectors) do
    if not expectError(vector[1], vector[2]) then
      return false, ('preview_vector_%s_expected_%s'):format(index, vector[2])
    end
  end

  local preview = MZBankAccountBackfill.Preview(1, 0, TEST_ACTOR)
  if type(preview) ~= 'table' or preview.ok ~= true then return false, 'valid_preview_failed' end
  if not expectError(MZBankAccountBackfill.Apply(
    preview.runRef, 1, 0, 'WRONG_CONFIRMATION', TEST_ACTOR
  ), 'invalid_confirmation') then return false, 'confirmation_not_rejected' end
  if not expectError(MZBankAccountBackfill.Apply(
    'invalid-ref', 1, 0, CONFIRMATION, TEST_ACTOR
  ), 'invalid_run_ref') then return false, 'run_ref_not_rejected' end
  if not expectError(MZBankAccountBackfill.Apply(
    preview.runRef, 2, 0, CONFIRMATION, TEST_ACTOR
  ), 'preview_parameters_mismatch') then return false, 'parameters_not_rejected' end
  if not expectError(MZBankAccountBackfill.Apply(
    preview.runRef, 1, 0, CONFIRMATION, 'different-actor'
  ), 'preview_actor_mismatch') then return false, 'actor_not_rejected' end

  return true, 'ace=owner vectors=9 rejected writes=0'
end

local function snapshotIdentityRows()
  local rows, err = MZBankRepository.listPublicAccountBackfillRows(0, 501)
  if not rows then return nil, err or 'snapshot_failed' end
  local snapshot = {}
  for index, row in ipairs(rows) do
    snapshot[index] = table.concat({
      tostring(row.player_id or ''),
      tostring(row.citizenid or ''),
      tostring(row.account_status or '')
    }, '|')
  end
  return table.concat(snapshot, '\n')
end

local function paginationAndConcurrencyCase()
  local before, beforeError = snapshotIdentityRows()
  if not before then return false, beforeError end

  local first = MZBankAccountBackfill.Preview(1, 0, TEST_ACTOR .. '-page-1')
  if type(first) ~= 'table' or first.ok ~= true or first.totalRead ~= 1
      or first.hasMore ~= true or tonumber(first.nextCursor) == nil then
    return false, 'first_page_invalid'
  end
  local second = MZBankAccountBackfill.Preview(1, first.nextCursor, TEST_ACTOR .. '-page-2')
  if type(second) ~= 'table' or second.ok ~= true or second.totalRead ~= 1
      or tonumber(second.nextCursor) <= tonumber(first.nextCursor) then
    return false, 'second_page_invalid'
  end

  local completed = 0
  local failures = 0
  for index = 1, CONCURRENT_PREVIEWS do
    CreateThread(function()
      local ok, result = pcall(
        MZBankAccountBackfill.Preview, 1, 0, TEST_ACTOR .. '-concurrent-' .. index
      )
      if not ok or type(result) ~= 'table' or result.ok ~= true then failures = failures + 1 end
      completed = completed + 1
    end)
  end
  local waited = 0
  while completed < CONCURRENT_PREVIEWS and waited < CONCURRENT_TIMEOUT_MS do
    Wait(25)
    waited = waited + 25
  end
  if completed ~= CONCURRENT_PREVIEWS then return false, 'concurrent_preview_timeout' end
  if failures ~= 0 then return false, ('concurrent_failures_%s'):format(failures) end

  local after, afterError = snapshotIdentityRows()
  if not after then return false, afterError end
  if after ~= before then return false, 'identity_snapshot_changed' end
  return true, ('pages=2 concurrent=%s failures=0 writes=0'):format(completed)
end

local function syntheticRows(afterPlayerId)
  if tonumber(afterPlayerId) ~= 0 then return {} end
  return {
    { player_id = 2100000001, citizenid = TEST_OWNER_CLOSED, account_status = 'closed' },
    { player_id = 2100000002, citizenid = TEST_OWNER_COLLISION, account_status = nil },
    { player_id = 2100000003, citizenid = TEST_OWNER_FAILURE, account_status = nil }
  }
end

local function injectedStatesCase()
  local originalList = MZBankRepository.listPublicAccountBackfillRows
  local originalEnsure = MZBankAccountService.EnsurePersonalAccount
  local ensureCalls = 0

  MZBankRepository.listPublicAccountBackfillRows = function(afterPlayerId)
    return syntheticRows(afterPlayerId)
  end
  MZBankAccountService.EnsurePersonalAccount = function(identity)
    ensureCalls = ensureCalls + 1
    if type(identity) ~= 'table' or identity.origin ~= 'p2d_backfill' then
      return { ok = false, error = 'invalid_test_origin' }
    end
    if identity.citizenid == TEST_OWNER_COLLISION then
      return {
        ok = true,
        created = true,
        collisionsRecovered = 1,
        account = { status = 'active' }
      }
    end
    if identity.citizenid == TEST_OWNER_FAILURE then
      return { ok = false, error = 'injected_failure' }
    end
    return { ok = false, error = 'unexpected_test_owner' }
  end

  local callOk, resultOrError = pcall(function()
    local preview = MZBankAccountBackfill.Preview(100, 0, TEST_ACTOR .. '-injected')
    if type(preview) ~= 'table' or preview.ok ~= true then
      error('injected_preview_failed')
    end
    syntheticRunRef = preview.runRef
    return MZBankAccountBackfill.Apply(
      preview.runRef, 100, 0, CONFIRMATION, TEST_ACTOR .. '-injected'
    )
  end)

  MZBankRepository.listPublicAccountBackfillRows = originalList
  MZBankAccountService.EnsurePersonalAccount = originalEnsure

  if MZBankRepository.listPublicAccountBackfillRows ~= originalList
      or MZBankAccountService.EnsurePersonalAccount ~= originalEnsure then
    return false, 'dependency_restore_failed'
  end
  if not callOk then return false, resultOrError end
  local result = resultOrError
  if type(result) ~= 'table' then return false, 'injected_result_missing' end
  if result.ok == true or result.error ~= 'backfill_completed_with_failures' then
    return false, 'controlled_failure_not_reported'
  end
  if result.closed ~= 1 or result.created ~= 1 or result.collisionsRecovered ~= 1
      or result.failures ~= 1 or result.nextCursor ~= 0 or result.requiresRetry ~= true then
    return false, 'aggregate_result_mismatch'
  end
  if type(result.failureCodes) ~= 'table' or result.failureCodes.injected_failure ~= 1 then
    return false, 'failure_code_missing'
  end
  if ensureCalls ~= 2 then return false, 'ensure_call_count_mismatch' end
  return true, 'closed=1 created=1 collision=1 failure=1 retry=true writes=0 dependencies=restored'
end

local function auditPrivacyCase()
  if type(syntheticRunRef) ~= 'string' then return false, 'synthetic_run_ref_missing' end
  local rows = MySQL.query.await([[
    SELECT action, actor, target, data_json
    FROM mz_logs
    WHERE scope = ? AND data_json LIKE ?
    ORDER BY id DESC
    LIMIT 20
  ]], { 'bank', '%' .. syntheticRunRef .. '%' }) or {}
  if #rows < 3 then return false, ('audit_rows_%s'):format(#rows) end

  local actions = {}
  for _, row in ipairs(rows) do
    actions[tostring(row.action or '')] = true
    local encoded = tostring(row.data_json or '')
    local lowered = encoded:lower()
    if lowered:find('citizenid', 1, true)
        or lowered:find('license', 1, true)
        or lowered:find('account_number', 1, true)
        or lowered:find('check_digit', 1, true)
        or encoded:find('P2D_RT_', 1, true) then
      return false, 'audit_contains_sensitive_data'
    end
    local decodedOk, decoded = pcall(json.decode, encoded)
    if not decodedOk or type(decoded) ~= 'table' then return false, 'audit_json_invalid' end
    if type(decoded.context) ~= 'table' or decoded.context.zeroBalanceChanges ~= true then
      return false, 'zero_balance_invariant_missing'
    end
  end
  if not actions.public_account_backfill_preview
      or not actions.public_account_backfill_apply_started
      or not actions.public_account_backfill_completed then
    return false, 'audit_actions_missing'
  end
  return true, ('rows=%s actions=preview,start,completed pii=false'):format(#rows)
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
    log(('FAIL P2D-RUNNER-PREFLIGHT detail=%s'):format(safeDetail(readyError)))
    return
  end

  running = true
  syntheticRunRef = nil
  local results = { passed = 0, failed = 0 }
  log('START staging_only=true writes=logs_only balances=false client_input=false injections=restored')

  runCase(results, 'P2D-02', argumentsAndAuthorizationCase)
  runCase(results, 'P2D-05', paginationAndConcurrencyCase)
  runCase(results, 'P2D-06', injectedStatesCase)
  runCase(results, 'P2D-07', auditPrivacyCase)

  log(('SUMMARY executed=%s passed=%s failed=%s'):format(
    results.passed + results.failed, results.passed, results.failed
  ))
  log('END disable runner/apply convars and restart mz_bank')
  running = false
end, true)

log(('enabled staging_only=true command=%s source=console writes=logs_only'):format(
  RUNNER_COMMAND
))
