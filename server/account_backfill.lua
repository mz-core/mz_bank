MZBankAccountBackfill = {}

local policy = type(Config.PublicAccount) == 'table'
  and type(Config.PublicAccount.Backfill) == 'table'
  and Config.PublicAccount.Backfill or {}
local previews = {}

local function integer(value, minimum, maximum, defaultValue)
  if value == nil or value == '' then return defaultValue end
  local number = tonumber(value)
  if not number or number ~= math.floor(number) or number < minimum or number > maximum then return nil end
  return number
end

local function stableError(value)
  value = tostring(value or 'unknown')
  if #value > 64 or not value:match('^[%w_:%-]+$') then return 'internal_error' end
  return value
end

local function actorFor(source)
  if tonumber(source) == 0 then return 'console' end
  return ('source:%s'):format(tostring(source))
end

local function hasRequiredAce(source)
  local ace = tostring(policy.Ace or '')
  if ace == '' then return false, 'backfill_ace_missing' end
  local check = IsPlayerAceAllowed
  local principal = tostring(source)
  if tonumber(source) == 0 then
    check = IsPrincipalAceAllowed
    principal = 'system.console'
  end
  if type(check) ~= 'function' then return false, 'backfill_ace_unavailable' end
  local ok, allowed = pcall(check, principal, ace)
  local normalized = tostring(allowed):lower()
  if ok and (allowed == true or allowed == 1 or normalized == '1' or normalized == 'true') then
    return true
  end
  return false, 'backfill_forbidden'
end

local function applyEnabled()
  if policy.AllowApply == true then return true end
  local convar = tostring(policy.ApplyEnableConvar or '')
  return convar ~= '' and GetConvarInt(convar, 0) == 1
end

local function validatePolicy()
  if policy.Enabled ~= true then return false, 'backfill_disabled' end
  if type(policy.AllowApply) ~= 'boolean' then return false, 'invalid_backfill_allow_apply' end
  if type(policy.ApplyEnableConvar) ~= 'string' or policy.ApplyEnableConvar == '' then
    return false, 'invalid_backfill_apply_convar'
  end
  if type(policy.Ace) ~= 'string' or policy.Ace == '' then return false, 'invalid_backfill_ace' end
  if type(policy.Command) ~= 'string' or not policy.Command:match('^[%w_]+$') then
    return false, 'invalid_backfill_command'
  end
  if tonumber(policy.DefaultBatchSize) ~= 100 then return false, 'invalid_backfill_default_batch' end
  if tonumber(policy.MaxBatchSize) ~= 500 then return false, 'invalid_backfill_max_batch' end
  if tonumber(policy.PreviewMaxAgeSeconds) ~= 1800 then return false, 'invalid_backfill_preview_age' end
  if tonumber(policy.MaxActivePreviews) ~= 32 then return false, 'invalid_backfill_preview_limit' end
  if tostring(policy.ConfirmationPhrase or '') ~= 'APPLY_PUBLIC_ACCOUNT_BACKFILL' then
    return false, 'invalid_backfill_confirmation'
  end
  return true
end

local policyOk, policyError = validatePolicy()

local function schemaReady()
  if type(MZBankMigrations) ~= 'table' or type(MZBankMigrations.getStatus) ~= 'function' then
    return false
  end
  local migration = MZBankMigrations.getStatus()
  return type(migration) == 'table' and migration.ready == true
end

local function cleanupPreviews()
  local now = os.time()
  for runRef, preview in pairs(previews) do
    if now - preview.createdAt > tonumber(policy.PreviewMaxAgeSeconds) then
      previews[runRef] = nil
    end
  end
end

local function activePreviewCount()
  local total = 0
  for _, preview in pairs(previews) do
    if preview.status == 'preview_ready' or preview.status == 'blocked' then total = total + 1 end
  end
  return total
end

local function makeRunRef()
  for _ = 1, 4 do
    local first = MZBankRepository.getSecureAccountRandomHex()
    local second = MZBankRepository.getSecureAccountRandomHex()
    if type(first) == 'string' and type(second) == 'string' then
      local runRef = ('p2d-%s-%s%s'):format(os.time(), first:lower(), second:lower())
      if not previews[runRef] then return runRef end
    end
  end
  return nil
end

local function fingerprintRows(rows)
  local hash = 17
  local length = 0
  for _, row in ipairs(rows) do
    local canonical = table.concat({
      tostring(row.player_id or ''),
      tostring(row.citizenid or ''),
      tostring(row.account_status or '')
    }, '|') .. '\n'
    length = length + #canonical
    for index = 1, #canonical do
      hash = (hash * 131 + canonical:byte(index)) % 2147483647
    end
  end
  return ('p2d-v1:%s:%s:%s'):format(#rows, length, hash)
end

local function collectBatch(batchSize, afterPlayerId)
  local rows, queryError = MZBankRepository.listPublicAccountBackfillRows(afterPlayerId, batchSize + 1)
  if not rows then return nil, queryError or 'backfill_query_failed' end

  local page = {}
  for index = 1, math.min(#rows, batchSize) do page[index] = rows[index] end
  local result = {
    rows = page,
    totalRead = #page,
    existing = 0,
    closed = 0,
    missing = 0,
    invalidRecords = 0,
    hasMore = #rows > batchSize,
    nextCursor = afterPlayerId,
    fingerprint = fingerprintRows(page)
  }

  for _, row in ipairs(page) do
    local playerId = tonumber(row.player_id)
    local citizenid = tostring(row.citizenid or '')
    if not playerId or playerId <= afterPlayerId or citizenid == '' or #citizenid > 32 then
      result.invalidRecords = result.invalidRecords + 1
    else
      result.nextCursor = playerId
      local status = row.account_status and tostring(row.account_status) or nil
      if status then
        result.existing = result.existing + 1
        if status == 'closed' then result.closed = result.closed + 1 end
        if MZBankAccountIdentity.IsValidStatus(status) ~= true then
          result.invalidRecords = result.invalidRecords + 1
        end
      else
        result.missing = result.missing + 1
      end
    end
  end
  return result
end

local function publicSummary(result)
  return {
    runRef = result.runRef,
    batchSize = result.batchSize,
    afterPlayerId = result.afterPlayerId,
    nextCursor = result.nextCursor,
    hasMore = result.hasMore == true,
    totalRead = result.totalRead,
    existing = result.existing,
    created = result.created or 0,
    closed = result.closed,
    missing = result.missing or 0,
    collisionsRecovered = result.collisionsRecovered or 0,
    failures = result.failures or 0,
    failureCodes = result.failureCodes or {},
    invalidRecords = result.invalidRecords or 0,
    interrupted = result.interrupted == true,
    zeroBalanceChanges = true
  }
end

local function writeAudit(action, actor, result)
  local summary = publicSummary(result)
  local ok = pcall(function()
    exports['mz_core']:CreateDetailedLog('bank', action, {
      actor = { type = actor == 'console' and 'console' or 'admin', id = actor },
      target = { type = 'public_account_backfill', id = tostring(result.runRef or 'preview') },
      context = summary,
      meta = { source_resource = 'mz_bank', schema_version = 1 }
    })
  end)
  return ok
end

function MZBankAccountBackfill.GetStatus()
  return {
    ready = policyOk == true and schemaReady(),
    error = not policyOk and policyError or (not schemaReady() and 'schema_not_ready' or nil),
    applyEnabled = policyOk and applyEnabled() or false,
    command = policyOk and policy.Command or nil
  }
end

function MZBankAccountBackfill.Preview(batchSize, afterPlayerId, actor)
  if not policyOk then return { ok = false, error = policyError } end
  if not schemaReady() then return { ok = false, error = 'bank_not_ready' } end
  cleanupPreviews()
  if activePreviewCount() >= tonumber(policy.MaxActivePreviews) then
    return { ok = false, error = 'too_many_active_previews' }
  end

  batchSize = integer(batchSize, 1, tonumber(policy.MaxBatchSize), tonumber(policy.DefaultBatchSize))
  afterPlayerId = integer(afterPlayerId, 0, 2147483647, 0)
  if not batchSize then return { ok = false, error = 'invalid_batch_size' } end
  if not afterPlayerId then return { ok = false, error = 'invalid_after_player_id' } end

  local callOk, batch, batchError = pcall(collectBatch, batchSize, afterPlayerId)
  if not callOk or not batch then
    return { ok = false, error = stableError(callOk and batchError or 'backfill_query_failed') }
  end
  local randomOk, runRef = pcall(makeRunRef)
  if not randomOk or not runRef then return { ok = false, error = 'secure_random_unavailable' } end

  local preview = {
    runRef = runRef,
    actor = tostring(actor or 'unknown'),
    createdAt = os.time(),
    status = batch.invalidRecords == 0 and 'preview_ready' or 'blocked',
    batchSize = batchSize,
    afterPlayerId = afterPlayerId,
    nextCursor = batch.nextCursor,
    hasMore = batch.hasMore,
    totalRead = batch.totalRead,
    existing = batch.existing,
    closed = batch.closed,
    missing = batch.missing,
    invalidRecords = batch.invalidRecords,
    fingerprint = batch.fingerprint
  }
  if not writeAudit('public_account_backfill_preview', preview.actor, preview) then
    return { ok = false, error = 'audit_unavailable' }
  end
  previews[runRef] = preview

  local summary = publicSummary(preview)
  summary.ok = true
  summary.safeToApply = preview.status == 'preview_ready'
  return summary
end

function MZBankAccountBackfill.Apply(runRef, batchSize, afterPlayerId, confirmation, actor)
  if not policyOk then return { ok = false, error = policyError } end
  if not applyEnabled() then return { ok = false, error = 'backfill_apply_disabled' } end
  if tostring(confirmation or '') ~= tostring(policy.ConfirmationPhrase) then
    return { ok = false, error = 'invalid_confirmation' }
  end
  cleanupPreviews()
  runRef = tostring(runRef or '')
  if not runRef:match('^p2d%-%d+%-%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$') then
    return { ok = false, error = 'invalid_run_ref' }
  end
  local preview = previews[runRef]
  if not preview or preview.status ~= 'preview_ready' then
    return { ok = false, error = 'preview_missing_or_not_ready' }
  end

  batchSize = integer(batchSize, 1, tonumber(policy.MaxBatchSize), nil)
  afterPlayerId = integer(afterPlayerId, 0, 2147483647, nil)
  if not batchSize or batchSize ~= preview.batchSize
      or not afterPlayerId or afterPlayerId ~= preview.afterPlayerId then
    return { ok = false, error = 'preview_parameters_mismatch' }
  end
  if tostring(actor or '') ~= preview.actor then
    return { ok = false, error = 'preview_actor_mismatch' }
  end

  local runtime = MZBankAccountService.GetRuntimeStatus()
  if MZBankAccountService.IsEnabled() ~= true or runtime.ready ~= true then
    return { ok = false, error = 'public_account_unavailable' }
  end

  local callOk, current, currentError = pcall(collectBatch, batchSize, afterPlayerId)
  if not callOk or not current then
    return { ok = false, error = stableError(callOk and currentError or 'backfill_query_failed') }
  end
  if current.fingerprint ~= preview.fingerprint or current.invalidRecords ~= 0 then
    preview.status = 'invalidated'
    writeAudit('public_account_backfill_invalidated', preview.actor, preview)
    return { ok = false, error = 'preview_changed_or_invalid' }
  end
  if not writeAudit('public_account_backfill_apply_started', preview.actor, preview) then
    return { ok = false, error = 'audit_unavailable' }
  end

  local result = {
    runRef = runRef,
    batchSize = batchSize,
    afterPlayerId = afterPlayerId,
    nextCursor = preview.nextCursor,
    hasMore = preview.hasMore,
    totalRead = current.totalRead,
    existing = 0,
    created = 0,
    closed = 0,
    missing = current.missing,
    collisionsRecovered = 0,
    failures = 0,
    failureCodes = {},
    invalidRecords = 0,
    interrupted = false
  }

  for _, row in ipairs(current.rows) do
    local status = row.account_status and tostring(row.account_status) or nil
    if status then
      result.existing = result.existing + 1
      if status == 'closed' then result.closed = result.closed + 1 end
    else
      local ensureOk, ensured = pcall(MZBankAccountService.EnsurePersonalAccount, {
        citizenid = tostring(row.citizenid),
        origin = 'p2d_backfill'
      })
      if not ensureOk then
        result.interrupted = true
        result.failures = result.failures + 1
        result.failureCodes.backfill_service_unavailable =
          (result.failureCodes.backfill_service_unavailable or 0) + 1
        break
      elseif type(ensured) == 'table' and ensured.ok == true then
        if ensured.created == true then result.created = result.created + 1
        else result.existing = result.existing + 1 end
        if ensured.account and ensured.account.status == 'closed' then
          result.closed = result.closed + 1
        end
        result.collisionsRecovered = result.collisionsRecovered
          + (tonumber(ensured.collisionsRecovered) or 0)
      else
        local errorCode = stableError(type(ensured) == 'table' and ensured.error or 'account_create_failed')
        result.failures = result.failures + 1
        result.failureCodes[errorCode] = (result.failureCodes[errorCode] or 0) + 1
      end
    end
  end

  if result.interrupted or result.failures > 0 then result.nextCursor = afterPlayerId end
  preview.status = result.interrupted and 'interrupted'
    or (result.failures > 0 and 'completed_with_failures' or 'applied')
  local auditOk = writeAudit(
    result.interrupted and 'public_account_backfill_interrupted' or 'public_account_backfill_completed',
    preview.actor,
    result
  )
  local summary = publicSummary(result)
  summary.ok = not result.interrupted and result.failures == 0 and auditOk
  summary.error = not auditOk and 'audit_unavailable'
    or (result.interrupted and 'backfill_interrupted'
      or (result.failures > 0 and 'backfill_completed_with_failures' or nil))
  summary.requiresRetry = result.interrupted or result.failures > 0
  return summary
end

local function printSummary(label, result)
  print(('[mz_bank][p2d] %s ok=%s run_ref=%s batch=%s after=%s next=%s read=%s existing=%s created=%s closed=%s missing=%s collisions=%s failures=%s invalid=%s has_more=%s retry=%s error=%s zero_balance_changes=true'):format(
    label, tostring(result.ok == true), tostring(result.runRef or 'none'),
    tostring(result.batchSize or 0), tostring(result.afterPlayerId or 0),
    tostring(result.nextCursor or 0), tostring(result.totalRead or 0),
    tostring(result.existing or 0), tostring(result.created or 0),
    tostring(result.closed or 0), tostring(result.missing or 0),
    tostring(result.collisionsRecovered or 0), tostring(result.failures or 0),
    tostring(result.invalidRecords or 0), tostring(result.hasMore == true),
    tostring(result.requiresRetry == true), tostring(result.error or 'none')
  ))
end

if policyOk then
  RegisterCommand(tostring(policy.Command), function(source, args)
    local allowed, aceError = hasRequiredAce(source)
    if not allowed then
      print(('[mz_bank][p2d] denied source=%s error=%s'):format(tostring(source), tostring(aceError)))
      return
    end
    local action = tostring(args and args[1] or ''):lower()
    local actor = actorFor(source)
    if action == 'preview' then
      local result = MZBankAccountBackfill.Preview(args[2], args[3], actor)
      printSummary('preview', result)
      return
    end
    if action == 'apply' then
      local result = MZBankAccountBackfill.Apply(args[2], args[3], args[4], args[5], actor)
      printSummary('apply', result)
      return
    end
    print(('[mz_bank][p2d] usage: %s preview [batch_size] [after_player_id]'):format(policy.Command))
    print(('[mz_bank][p2d] usage: %s apply <run_ref> <batch_size> <after_player_id> %s'):format(
      policy.Command, policy.ConfirmationPhrase
    ))
  end, false)
  print(('[mz_bank][p2d] registered command=%s preview=true apply=%s ace=%s'):format(
    tostring(policy.Command), tostring(applyEnabled()), tostring(policy.Ace)
  ))
else
  print(('[mz_bank][p2d] unavailable error=%s'):format(tostring(policyError)))
end
