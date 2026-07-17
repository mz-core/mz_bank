local RUNNER_CONVAR = 'mz_bank_p2f_runtime_runner'
local ALLOW_TRANSFER_CONVAR = 'mz_bank_p2f_runtime_allow_transfer'
local ACTOR_SOURCE_CONVAR = 'mz_bank_p2f_runtime_actor_source'
local TARGET_SOURCE_CONVAR = 'mz_bank_p2f_runtime_target_source'
local AMOUNT_CONVAR = 'mz_bank_p2f_runtime_amount'
local INTERNAL_COMMAND = 'mz_bank_p2f_runtime_test'
local REAL_COMMAND = 'mz_bank_p2f_runtime_transfer'

-- Inerte por padrao: nenhum comando, evento, callback, export ou thread.
if GetConvarInt(RUNNER_CONVAR, 0) ~= 1 then return end

local running = false

local function log(message)
  print(('[mz_bank][p2f-runner] %s'):format(tostring(message)))
end

local function safeDetail(value)
  local detail = tostring(value or '')
    :gsub('[\r\n\t]', ' ')
    :gsub('P2F_RT_[%w_%-]+', '<test-identity>')
    :gsub('p2e%-%x+', '<resolution-token>')
    :gsub('p2f_rt_[%w_%-]+', '<idempotency-key>')
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

local function internalSuite()
  if type(MZBankService.ExecuteP2FRuntimeFixture) ~= 'function' then
    return nil, 'runtime_fixture_hook_unavailable'
  end

  local originals = {
    resolvePlayer = MZBankBridge.ResolvePlayer,
    transfer = MZBankBridge.TransferBankBetweenPlayers,
    notify = MZBankBridge.Notify,
    log = MZBankBridge.Log,
    displayName = MZBankBridge.GetDisplayName,
    ownerLookup = MZBankRepository.getPublicAccountByOwner,
    validateResolution = MZBankAccountResolution.ValidateResolutionToken,
    invalidateResolution = MZBankAccountResolution.InvalidateResolutionToken,
    cleanupResolution = MZBankAccountResolution.CleanupSession
  }

  local senderCitizenId = 'P2F_RT_SENDER'
  local targetCitizenId = 'P2F_RT_TARGET'
  local originStatus = 'active'
  local financeMode = 'success'
  local financeCalls = 0
  local committed = 0
  local invalidated = {}
  local audits = {}
  local stored = {}
  local session = {
    token = 'p2f-runtime-session',
    citizenid = senderCitizenId,
    channel = 'branch',
    coords = { x = 0, y = 0, z = 0 },
    authenticated = true
  }

  local function restore()
    MZBankBridge.ResolvePlayer = originals.resolvePlayer
    MZBankBridge.TransferBankBetweenPlayers = originals.transfer
    MZBankBridge.Notify = originals.notify
    MZBankBridge.Log = originals.log
    MZBankBridge.GetDisplayName = originals.displayName
    MZBankRepository.getPublicAccountByOwner = originals.ownerLookup
    MZBankAccountResolution.ValidateResolutionToken = originals.validateResolution
    MZBankAccountResolution.InvalidateResolutionToken = originals.invalidateResolution
    MZBankAccountResolution.CleanupSession = originals.cleanupResolution
  end

  MZBankBridge.ResolvePlayer = function(source)
    return {
      source = source,
      citizenid = senderCitizenId,
      displayName = 'Remetente Teste'
    }
  end
  MZBankBridge.GetDisplayName = function() return 'Remetente Teste' end
  MZBankBridge.Notify = function() end
  MZBankBridge.Log = function(action, source, payload)
    audits[#audits + 1] = { action = action, source = source, payload = payload }
  end
  MZBankRepository.getPublicAccountByOwner = function()
    return {
      id = 970001,
      citizenid = senderCitizenId,
      account_type = 'personal',
      status = originStatus
    }
  end
  MZBankAccountResolution.ValidateResolutionToken = function(_, token)
    if invalidated[token] then return nil, 'invalid_resolution_token' end
    if token == 'invalid' then return nil, 'invalid_resolution_token' end
    if token == 'unavailable' then return nil, 'recipient_unavailable' end
    if token == 'self' then
      return { targetCitizenId = senderCitizenId, targetSource = 66101 }
    end
    return { targetCitizenId = targetCitizenId, targetSource = 66102, accountId = 970002 }
  end
  MZBankAccountResolution.InvalidateResolutionToken = function(_, token)
    invalidated[token] = true
    return true
  end
  MZBankAccountResolution.CleanupSession = function() end
  MZBankBridge.TransferBankBetweenPlayers = function(_, target, amount, metadata)
    financeCalls = financeCalls + 1
    if target ~= targetCitizenId then return { ok = false, error = 'target_mismatch' } end
    if financeMode == 'insufficient' then return { ok = false, error = 'not_enough_money' } end
    if financeMode == 'database_error' then return { ok = false, error = 'database_error' } end
    if financeMode == 'offline' then return { ok = false, error = 'recipient_offline' } end

    local key = tostring(metadata.idempotency_key or '')
    local fingerprint = ('%s|%s|%s'):format(target, amount, metadata.fee or 0)
    local existing = stored[key]
    if existing then
      if existing.fingerprint ~= fingerprint then
        return { ok = false, error = 'idempotency_conflict' }
      end
      return {
        ok = true,
        targetSource = 66102,
        targetCitizenId = targetCitizenId,
        transactionRef = existing.correlationId,
        correlationId = existing.correlationId,
        replayed = true
      }
    end
    committed = committed + 1
    local correlationId = ('p2f-fixture-correlation-%s'):format(committed)
    stored[key] = { fingerprint = fingerprint, correlationId = correlationId }
    return {
      ok = true,
      targetSource = 66102,
      targetCitizenId = targetCitizenId,
      transactionRef = correlationId,
      correlationId = correlationId,
      balances = { sender = 900, recipient = 1100 },
      replayed = false
    }
  end

  local function call(token, amount, key)
    return MZBankService.ExecuteP2FRuntimeFixture(66101, token, amount, key, session)
  end

  local results = { passed = 0, failed = 0 }
  local suiteOk, suiteError = pcall(function()
    runCase(results, 'P2F-INT-01', function()
      return type(MZBankService.TransferByPublicAccount) == 'function'
        and type(MZBankService.ExecuteP2FRuntimeFixture) == 'function',
        'service=available public_surface=false'
    end)

    runCase(results, 'P2F-INT-02', function()
      local result = call('success-active', 100, 'p2f_rt_success_0001')
      if type(result) ~= 'table' or result.ok ~= true or result.confirmed ~= true
          or result.correlationId == nil or invalidated['success-active'] ~= true then
        return false, result and result.error or 'success_failed'
      end
      return true, 'active_to_active=confirmed target=stable token=consumed'
    end)

    runCase(results, 'P2F-INT-03', function()
      local result = call('success-blocked-target', 100, 'p2f_rt_blocked_0002')
      return type(result) == 'table' and result.ok == true,
        'blocked_target=receivable'
    end)

    runCase(results, 'P2F-INT-04', function()
      local before = financeCalls
      for _, status in ipairs({ 'blocked', 'frozen', 'closed' }) do
        originStatus = status
        local result = call('origin-' .. status, 100, 'p2f_rt_origin_' .. status)
        if type(result) ~= 'table' or result.ok == true then return false, status end
      end
      originStatus = 'active'
      return financeCalls == before, 'origin_states=3 denied_before_finance=true'
    end)

    runCase(results, 'P2F-INT-05', function()
      local before = financeCalls
      local result = call('unavailable', 100, 'p2f_rt_target_0005')
      return type(result) == 'table' and result.error == 'recipient_unavailable'
        and financeCalls == before, 'target_revalidation=denied finance=false'
    end)

    runCase(results, 'P2F-INT-06', function()
      local before = financeCalls
      local invalid = call('invalid', 100, 'p2f_rt_invalid_0006')
      local selfResult = call('self', 100, 'p2f_rt_self_000006')
      return invalid.error == 'invalid_resolution_token'
        and selfResult.error == 'self_transfer' and financeCalls == before,
        'invalid_and_self=denied'
    end)

    runCase(results, 'P2F-INT-07', function()
      local before = financeCalls
      local vectors = { 0, -1, 1.5, '10', 1000001, 0 / 0, math.huge }
      for index, amount in ipairs(vectors) do
        local result = call('amount-' .. index, amount, 'p2f_rt_amount_' .. index .. '_0000')
        if type(result) ~= 'table' or result.ok == true then return false, index end
      end
      return financeCalls == before, 'invalid_amount_vectors=7 finance=false'
    end)

    runCase(results, 'P2F-INT-08', function()
      financeMode = 'insufficient'
      local before = financeCalls
      local result = call('insufficient', 100, 'p2f_rt_insufficient')
      financeMode = 'success'
      return result.error == 'not_enough_bank' and financeCalls == before + 1
        and invalidated.insufficient == true, 'insufficient=terminal token=consumed'
    end)

    runCase(results, 'P2F-INT-09', function()
      local first = call('replay-first', 120, 'p2f_rt_replay_00009')
      local second = call('replay-second', 120, 'p2f_rt_replay_00009')
      return first.ok == true and second.ok == true and second.replayed == true
        and first.correlationId == second.correlationId,
        'replay=true correlation=stable'
    end)

    runCase(results, 'P2F-INT-10', function()
      local first = call('conflict-first', 130, 'p2f_rt_conflict_0010')
      local second = call('conflict-second', 131, 'p2f_rt_conflict_0010')
      return first.ok == true and second.error == 'idempotency_conflict',
        'idempotency_conflict=true duplicate=false'
    end)

    runCase(results, 'P2F-INT-11', function()
      local before = committed
      local completed, failures = 0, 0
      for index = 1, 8 do
        CreateThread(function()
          local result = call(
            'concurrent-' .. index, 140, 'p2f_rt_concurrent_11'
          )
          if type(result) ~= 'table' or result.ok ~= true then failures = failures + 1 end
          completed = completed + 1
        end)
      end
      local waited = 0
      while completed < 8 and waited < 20000 do Wait(25); waited = waited + 25 end
      return completed == 8 and failures == 0 and committed == before + 1,
        ('calls=%s committed=%s failures=%s'):format(completed, committed - before, failures)
    end)

    runCase(results, 'P2F-INT-12', function()
      financeMode = 'database_error'
      local result = call('ambiguous', 100, 'p2f_rt_ambiguous_012')
      financeMode = 'success'
      return result.error == 'database_error' and invalidated.ambiguous ~= true,
        'ambiguous_error=preserves_token'
    end)

    runCase(results, 'P2F-INT-13', function()
      financeMode = 'offline'
      local result = call('offline-core', 100, 'p2f_rt_offline_0013')
      financeMode = 'success'
      return result.error == 'recipient_unavailable'
        and invalidated['offline-core'] == true, 'offline=uniform token=consumed'
    end)

    runCase(results, 'P2F-INT-14', function()
      for _, audit in ipairs(audits) do
        local encoded = json.encode(audit.payload or {})
        if encoded:find('p2e-', 1, true)
            or encoded:find(senderCitizenId, 1, true)
            or encoded:find(targetCitizenId, 1, true)
            or encoded:lower():find('citizenid', 1, true) then
          return false, 'audit_contains_sensitive_data'
        end
      end
      return true, ('audits=%s token=false pii=false'):format(#audits)
    end)
  end)

  restore()
  if not suiteOk then return nil, suiteError end
  return results
end

local function getBankSnapshot(citizenid)
  local row = MySQL.single.await([[
    SELECT wallet, bank, dirty
    FROM mz_player_accounts
    WHERE citizenid = ?
    LIMIT 1
  ]], { citizenid })
  if type(row) ~= 'table' then return nil, 'account_snapshot_missing' end
  local snapshot = {
    wallet = tonumber(row.wallet),
    bank = tonumber(row.bank),
    dirty = tonumber(row.dirty)
  }
  if snapshot.wallet == nil or snapshot.bank == nil or snapshot.dirty == nil then
    return nil, 'account_snapshot_invalid'
  end
  return snapshot
end

local function sameSnapshot(left, right)
  return type(left) == 'table' and type(right) == 'table'
    and left.wallet == right.wallet and left.bank == right.bank and left.dirty == right.dirty
end

local function expectedFee(amount)
  local percent = tonumber(Config.TransferFeePercent) or 0
  if percent <= 0 then return 0 end
  return math.floor(amount * percent / 100)
end

local function realTransferSuite()
  if GetConvarInt(ALLOW_TRANSFER_CONVAR, 0) ~= 1 then
    return nil, 'real_transfer_not_enabled'
  end
  local actorSource = GetConvarInt(ACTOR_SOURCE_CONVAR, 0)
  local targetSource = GetConvarInt(TARGET_SOURCE_CONVAR, 0)
  local amount = GetConvarInt(AMOUNT_CONVAR, 1)
  if actorSource <= 0 or targetSource <= 0 or actorSource == targetSource then
    return nil, 'invalid_runtime_sources'
  end
  if amount <= 0 or amount > 1000 then return nil, 'invalid_runtime_amount' end
  if type(MZBankService.GetP2FRuntimeSession) ~= 'function' then
    return nil, 'runtime_session_hook_unavailable'
  end

  local session, sessionError = MZBankService.GetP2FRuntimeSession(actorSource)
  if not session then return nil, sessionError end
  local actorIdentity = MZBankBridge.ResolvePlayer(actorSource, false)
  local targetIdentity = MZBankBridge.ResolvePlayer(targetSource, false)
  if not actorIdentity or not targetIdentity then return nil, 'runtime_player_offline' end
  if actorIdentity.citizenid == targetIdentity.citizenid then return nil, 'self_transfer' end

  local targetAccount, targetError = MZBankRepository.getPublicAccountByOwner(
    targetIdentity.citizenid
  )
  if type(targetAccount) ~= 'table' or targetError
      or MZBankAccountService.CanAccountPerform(targetAccount.status, 'receive') ~= true then
    return nil, 'target_public_account_unavailable'
  end

  local actorBefore, actorSnapshotError = getBankSnapshot(actorIdentity.citizenid)
  if not actorBefore then return nil, actorSnapshotError end
  local targetBefore, targetSnapshotError = getBankSnapshot(targetIdentity.citizenid)
  if not targetBefore then return nil, targetSnapshotError end
  local actorCacheBefore = MZBankBridge.GetMoney(actorSource, 'bank')
  local targetCacheBefore = MZBankBridge.GetMoney(targetSource, 'bank')
  if actorCacheBefore ~= actorBefore.bank or targetCacheBefore ~= targetBefore.bank then
    return nil, 'initial_cache_persistence_mismatch'
  end

  local randomA = MZBankRepository.getSecureAccountRandomHex()
  local randomB = MZBankRepository.getSecureAccountRandomHex()
  if type(randomA) ~= 'string' or type(randomB) ~= 'string' then
    return nil, 'idempotency_random_unavailable'
  end
  local idempotencyKey = ('p2f_rt_%s%s'):format(randomA, randomB):lower()
  local route = {
    branch = targetAccount.branch,
    accountNumber = targetAccount.account_number,
    checkDigit = targetAccount.check_digit
  }

  local function resolveToken()
    local resolved = MZBankService.ResolvePublicRecipient(
      actorSource, route, { token = session.token }
    )
    if type(resolved) ~= 'table' or resolved.ok ~= true
        or type(resolved.data) ~= 'table'
        or type(resolved.data.resolutionToken) ~= 'string' then
      return nil, type(resolved) == 'table' and resolved.error or 'resolution_failed'
    end
    return resolved.data.resolutionToken
  end

  local firstToken, firstTokenError = resolveToken()
  if not firstToken then return nil, firstTokenError end
  local first = MZBankService.TransferByPublicAccount(
    actorSource, firstToken, amount,
    { token = session.token, idempotencyKey = idempotencyKey }
  )
  if type(first) ~= 'table' or first.ok ~= true or first.confirmed ~= true then
    return nil, type(first) == 'table' and first.error or 'first_transfer_failed'
  end
  local correlationId = tostring(first.correlationId or '')
  if correlationId == '' then return nil, 'correlation_missing' end

  local actorAfterFirst = getBankSnapshot(actorIdentity.citizenid)
  local targetAfterFirst = getBankSnapshot(targetIdentity.citizenid)
  local fee = expectedFee(amount)
  if not actorAfterFirst or not targetAfterFirst
      or actorAfterFirst.bank ~= actorBefore.bank - amount - fee
      or targetAfterFirst.bank ~= targetBefore.bank + amount
      or actorAfterFirst.wallet ~= actorBefore.wallet
      or actorAfterFirst.dirty ~= actorBefore.dirty
      or targetAfterFirst.wallet ~= targetBefore.wallet
      or targetAfterFirst.dirty ~= targetBefore.dirty then
    return nil, 'official_balance_delta_mismatch'
  end
  local actorCacheAfterFirst = MZBankBridge.GetMoney(actorSource, 'bank')
  local targetCacheAfterFirst = MZBankBridge.GetMoney(targetSource, 'bank')
  if actorCacheAfterFirst ~= actorAfterFirst.bank
      or targetCacheAfterFirst ~= targetAfterFirst.bank then
    return nil, 'cache_persistence_mismatch_after_commit'
  end

  local replayToken, replayTokenError = resolveToken()
  if not replayToken then return nil, replayTokenError end
  local replay = MZBankService.TransferByPublicAccount(
    actorSource, replayToken, amount,
    { token = session.token, idempotencyKey = idempotencyKey }
  )
  if type(replay) ~= 'table' or replay.ok ~= true or replay.replayed ~= true
      or tostring(replay.correlationId or '') ~= correlationId then
    return nil, 'replay_contract_failed'
  end
  local actorAfterReplay = getBankSnapshot(actorIdentity.citizenid)
  local targetAfterReplay = getBankSnapshot(targetIdentity.citizenid)
  if not sameSnapshot(actorAfterFirst, actorAfterReplay)
      or not sameSnapshot(targetAfterFirst, targetAfterReplay) then
    return nil, 'replay_moved_balance'
  end
  if MZBankBridge.GetMoney(actorSource, 'bank') ~= actorAfterReplay.bank
      or MZBankBridge.GetMoney(targetSource, 'bank') ~= targetAfterReplay.bank then
    return nil, 'cache_persistence_mismatch_after_replay'
  end

  local conflictToken, conflictTokenError = resolveToken()
  if not conflictToken then return nil, conflictTokenError end
  local conflict = MZBankService.TransferByPublicAccount(
    actorSource, conflictToken, amount + 1,
    { token = session.token, idempotencyKey = idempotencyKey }
  )
  if type(conflict) ~= 'table' or conflict.error ~= 'idempotency_conflict' then
    return nil, 'idempotency_conflict_missing'
  end
  local actorAfterConflict = getBankSnapshot(actorIdentity.citizenid)
  local targetAfterConflict = getBankSnapshot(targetIdentity.citizenid)
  if not sameSnapshot(actorAfterFirst, actorAfterConflict)
      or not sameSnapshot(targetAfterFirst, targetAfterConflict) then
    return nil, 'conflict_moved_balance'
  end

  local idempotencyRow = MySQL.single.await([[
    SELECT operation, correlation_id
    FROM mz_account_idempotency
    WHERE source_resource = ? AND actor_citizenid = ? AND idempotency_key = ?
    LIMIT 1
  ]], { 'mz_bank', actorIdentity.citizenid, idempotencyKey })
  if type(idempotencyRow) ~= 'table'
      or tostring(idempotencyRow.operation or '') ~= 'bank_transfer'
      or tostring(idempotencyRow.correlation_id or '') ~= correlationId then
    return nil, 'persistent_idempotency_missing'
  end

  return {
    amount = amount,
    fee = fee,
    correlationId = correlationId,
    senderDelta = actorAfterFirst.bank - actorBefore.bank,
    targetDelta = targetAfterFirst.bank - targetBefore.bank
  }
end

RegisterCommand(INTERNAL_COMMAND, function(source, args)
  if source ~= 0 then return end
  if type(args) == 'table' and #args > 0 then log(('usage: %s'):format(INTERNAL_COMMAND)); return end
  if running then log('refused reason=already_running'); return end
  running = true
  log('START mode=internal staging_only=true fixtures=memory writes=logs_only client_input=false')
  local results, suiteError = internalSuite()
  if not results then
    log(('FAIL P2F-INTERNAL-SUITE detail=%s'):format(safeDetail(suiteError)))
  else
    log(('SUMMARY mode=internal executed=%s passed=%s failed=%s'):format(
      results.passed + results.failed, results.passed, results.failed
    ))
  end
  log('END mode=internal dependencies=restored balances=false')
  running = false
end, true)

RegisterCommand(REAL_COMMAND, function(source, args)
  if source ~= 0 then return end
  if type(args) == 'table' and #args > 0 then log(('usage: %s'):format(REAL_COMMAND)); return end
  if running then log('refused reason=already_running'); return end
  running = true
  log('START mode=real explicit_allow=true amount_capped=1000 client_input=false')
  local result, suiteError = realTransferSuite()
  if not result then
    log(('FAIL P2F-REAL detail=%s'):format(safeDetail(suiteError)))
  else
    log(('PASS P2F-REAL detail=amount=%s fee=%s sender_delta=%s target_delta=%s replay=true conflict=true persistence=true correlation=set'):format(
      result.amount, result.fee, result.senderDelta, result.targetDelta
    ))
  end
  log('END mode=real disable_allow_and_runner_convars=true')
  running = false
end, true)

log(('enabled staging_only=true commands=%s,%s real_transfer=%s sources=%s,%s amount=%s'):format(
  INTERNAL_COMMAND,
  REAL_COMMAND,
  GetConvarInt(ALLOW_TRANSFER_CONVAR, 0) == 1 and 'enabled' or 'disabled',
  GetConvarInt(ACTOR_SOURCE_CONVAR, 0),
  GetConvarInt(TARGET_SOURCE_CONVAR, 0),
  GetConvarInt(AMOUNT_CONVAR, 1)
))
