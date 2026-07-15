local REQUIRED_DEPENDENCIES = {
  'oxmysql', 'ox_lib', 'mz_core', 'mz_inventory'
}

local OBSERVED_DEPENDENCIES = {
  'mz_economy'
}

local readiness = {
  ready = false,
  error = 'not_started',
  dependencies = {},
  migration = MZBankMigrations.getStatus()
}

local function dependencySnapshot()
  local states = {}
  local missing = {}
  for _, resourceName in ipairs(REQUIRED_DEPENDENCIES) do
    local state = GetResourceState(resourceName)
    states[resourceName] = state
    if state ~= 'started' then missing[#missing + 1] = ('%s=%s'):format(resourceName, state) end
  end
  for _, resourceName in ipairs(OBSERVED_DEPENDENCIES) do
    states[resourceName] = GetResourceState(resourceName)
  end
  return states, missing
end

local function isDependencyIn(list, resourceName)
  for _, dependencyName in ipairs(list) do
    if dependencyName == resourceName then return true end
  end
  return false
end

local function setUnavailable(errorCode)
  readiness.ready = false
  readiness.error = errorCode
  readiness.migration = MZBankMigrations.getStatus()
  MZBankService.SetReady(false)
  print(('[mz_bank] unavailable error=%s'):format(tostring(errorCode)))
end

local function copyReadiness()
  local dependencyStates = dependencySnapshot()
  readiness.dependencies = dependencyStates
  local dependencies = {}
  for name, state in pairs(readiness.dependencies) do dependencies[name] = state end
  local migration = readiness.migration or {}
  local economyState = dependencies.mz_economy or 'missing'
  return {
    ready = readiness.ready,
    error = readiness.error,
    degraded = readiness.ready and economyState ~= 'started',
    warning = economyState ~= 'started' and ('dependency_degraded:mz_economy=%s'):format(economyState) or nil,
    dependencies = dependencies,
    migration = {
      ready = migration.ready == true,
      currentVersion = tonumber(migration.currentVersion) or 0,
      expectedVersion = tonumber(migration.expectedVersion) or 0,
      error = migration.error
    }
  }
end

CreateThread(function()
  local dependencyStates, missing = dependencySnapshot()
  readiness.dependencies = dependencyStates
  if #missing > 0 then
    setUnavailable(('dependency_missing:%s'):format(table.concat(missing, ',')))
    return
  end

  local callOk, migrated, migrationStatus = pcall(MZBankMigrations.run)
  readiness.migration = type(migrationStatus) == 'table' and migrationStatus or MZBankMigrations.getStatus()
  if not callOk then
    setUnavailable(('migration_failed:%s'):format(tostring(migrated)))
    return
  end
  if migrated ~= true then
    setUnavailable(('migration_failed:%s'):format(tostring(readiness.migration.error or 'unknown')))
    return
  end

  readiness.ready = true
  readiness.error = nil
  MZBankService.SetReady(true)
  print(('[mz_bank] ready schema_version=%s; balances are provided exclusively by mz_core'):format(
    tostring(readiness.migration.currentVersion)
  ))
  if readiness.dependencies.mz_economy ~= 'started' then
    print(('[mz_bank] degraded dependency=mz_economy state=%s; statement unavailable; core financial operations remain enabled'):format(
      tostring(readiness.dependencies.mz_economy)
    ))
  end

  local previewOk, preview = pcall(MZBankLegacy.preview)
  if previewOk and (preview.bank_accounts.exists or preview.bank_transactions.exists) then
    print(('[mz_bank][legacy] detected accounts_rows=%s transactions_rows=%s; run mz_bank_legacy_preview; no migration applied'):format(
      preview.bank_accounts.rows, preview.bank_transactions.rows
    ))
  end

  pcall(function()
    exports['mz_core']:RegisterItemUseHandler(Config.Card.ItemName, function(source)
      MZBankBridge.Notify(source, 'Use o cartao em um caixa eletronico ou agencia.', 'info')
      return { ok = true, consume = false }
    end)
  end)
end)

exports('GetReadiness', function()
  return copyReadiness()
end)

local function safeServiceCall(handler, ...)
  local ok, result = pcall(handler, ...)
  if ok and type(result) == 'table' then return result end
  if not ok then print(('[mz_bank] service call failed: %s'):format(tostring(result))) end
  return { ok = false, error = 'transaction_failed', message = Config.Locale.transaction_failed }
end

lib.callback.register('mz_bank:server:openSession', function(source, payload)
  return safeServiceCall(MZBankService.OpenSession, source, payload)
end)

lib.callback.register('mz_bank:server:authenticate', function(source, token)
  return safeServiceCall(MZBankService.Authenticate, source, token)
end)

lib.callback.register('mz_bank:server:overview', function(source, token)
  return safeServiceCall(MZBankService.Refresh, source, token)
end)

lib.callback.register('mz_bank:server:withdraw', function(source, token, payload)
  payload = type(payload) == 'table' and payload or {}
  return safeServiceCall(MZBankService.Withdraw, source, token, payload.amount, payload.idempotencyKey)
end)

lib.callback.register('mz_bank:server:deposit', function(source, token, payload)
  payload = type(payload) == 'table' and payload or {}
  return safeServiceCall(MZBankService.Deposit, source, token, payload.amount, payload.idempotencyKey)
end)

lib.callback.register('mz_bank:server:transfer', function(source, token, payload)
  payload = type(payload) == 'table' and payload or {}
  return safeServiceCall(MZBankService.Transfer, source, {
    value = payload.recipientValue
  }, payload.amount, { token = token, idempotencyKey = payload.idempotencyKey })
end)

RegisterNetEvent('mz_bank:server:closeSession', function(token, reason)
  pcall(MZBankService.CloseSession, source, token, reason)
end)

AddEventHandler('playerDropped', function()
  MZBankService.CleanupSource(source)
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName == GetCurrentResourceName() then
    for _, playerId in ipairs(GetPlayers()) do
      MZBankService.CleanupSource(tonumber(playerId))
    end
    return
  end
  if isDependencyIn(OBSERVED_DEPENDENCIES, resourceName) then
    readiness.dependencies[resourceName] = 'stopped'
    print(('[mz_bank] degraded dependency=%s state=stopped; statement unavailable; core financial operations remain enabled'):format(resourceName))
    return
  end
  if isDependencyIn(REQUIRED_DEPENDENCIES, resourceName) then
    readiness.dependencies[resourceName] = 'stopped'
    setUnavailable(('dependency_stopped:%s;restart_mz_bank_after_dependency'):format(resourceName))
  end
end)

AddEventHandler('onResourceStart', function(resourceName)
  if not isDependencyIn(OBSERVED_DEPENDENCIES, resourceName) then return end
  readiness.dependencies[resourceName] = GetResourceState(resourceName)
  print(('[mz_bank] observed dependency=%s state=%s; statement availability restored automatically when ready'):format(
    resourceName,
    tostring(readiness.dependencies[resourceName])
  ))
end)

exports('GetAccountOverview', function(source, context)
  return safeServiceCall(MZBankService.GetAccountOverview, source, context)
end)

exports('GetStatement', function(source, filters, context)
  return safeServiceCall(MZBankService.GetStatement, source, filters, context)
end)

exports('ResolveRecipient', function(source, recipientValue, context)
  return safeServiceCall(MZBankService.ResolveRecipient, source, recipientValue, context)
end)

exports('Transfer', function(source, recipient, amount, context)
  return safeServiceCall(MZBankService.Transfer, source, recipient, amount, context)
end)

exports('GetCards', function(source, context)
  return safeServiceCall(MZBankService.GetCards, source, context)
end)

exports('BlockCard', function(source, cardUid, context)
  return safeServiceCall(MZBankService.BlockCard, source, cardUid, context)
end)

exports('RequestReplacementCard', function(source, context)
  return safeServiceCall(MZBankService.RequestReplacementCard, source, context)
end)
