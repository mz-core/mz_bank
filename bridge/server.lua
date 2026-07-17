MZBankBridge = {}

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function coreExport(name, ...)
  local args = table.pack(...)
  local ok, first, second = pcall(function()
    -- Mantem as chamadas na forma oficial de metodo do FiveM. A versao antiga
    -- usava exports['mz_core'][name](...), o que perdia/deslocava o primeiro
    -- argumento em exports dinamicos (normalmente o source do jogador).
    if name == 'GetMoney' then
      return exports['mz_core']:GetMoney(args[1])
    elseif name == 'NormalizeMoneyAccount' then
      return exports['mz_core']:NormalizeMoneyAccount(args[1])
    elseif name == 'TransferMoneyBetweenAccounts' then
      return exports['mz_core']:TransferMoneyBetweenAccounts(args[1], args[2], args[3], args[4], args[5])
    elseif name == 'TransferBankBetweenPlayers' then
      return exports['mz_core']:TransferBankBetweenPlayers(args[1], args[2], args[3], args[4])
    elseif name == 'RemoveMoney' then
      return exports['mz_core']:RemoveMoney(args[1], args[2], args[3], args[4])
    elseif name == 'AddMoney' then
      return exports['mz_core']:AddMoney(args[1], args[2], args[3], args[4])
    end

    error(('unsupported mz_core export: %s'):format(tostring(name)))
  end)

  if not ok then
    print(('[mz_bank][bridge] mz_core export %s failed: %s'):format(name, tostring(first)))
    return nil, 'bank_unavailable'
  end

  return first, second
end

function MZBankBridge.GetPlayer(source)
  source = tonumber(source)
  if not source or source <= 0 then return nil end

  local ok, player = pcall(function()
    return exports['mz_core']:GetPlayer(source)
  end)
  if not ok then
    print(('[mz_bank][bridge] mz_core export GetPlayer failed: %s'):format(tostring(player)))
    return nil
  end
  return player
end

local function isUsableCachedPlayer(source, player)
  return type(player) == 'table'
    and tostring(player.citizenid or '') ~= ''
    and tonumber(player.source) == tonumber(source)
end

function MZBankBridge.IsPlayerLoaded(source)
  local player = MZBankBridge.GetPlayer(source)
  if isUsableCachedPlayer(source, player) then
    return true
  end

  local ok, loaded = pcall(function()
    return exports['mz_core']:IsPlayerLoaded(source)
  end)
  if not ok then
    print(('[mz_bank][bridge] mz_core export IsPlayerLoaded failed: %s'):format(tostring(loaded)))
    return false
  end
  return loaded == true
end

function MZBankBridge.EnsurePlayerLoaded(source)
  source = tonumber(source)
  if not source or source <= 0 then return nil, 'invalid_source' end

  local existing = MZBankBridge.GetPlayer(source)
  if isUsableCachedPlayer(source, existing) then
    return existing, 'already_cached'
  end

  local ok, player, stateOrErr = pcall(function()
    return exports['mz_core']:EnsurePlayerLoaded(source)
  end)
  if not ok then
    print(('[mz_bank][bridge] mz_core export EnsurePlayerLoaded failed: %s'):format(tostring(player)))
    return nil, 'bank_unavailable'
  end
  if not isUsableCachedPlayer(source, player) then
    return nil, stateOrErr or 'player_not_loaded'
  end
  return player, stateOrErr
end

function MZBankBridge.ResolvePlayer(source, ensureLoaded)
  source = tonumber(source)
  if not source or source <= 0 then return nil, 'invalid_source' end

  local player = MZBankBridge.GetPlayer(source)
  local loadState
  if not isUsableCachedPlayer(source, player) and ensureLoaded == true then
    player, loadState = MZBankBridge.EnsurePlayerLoaded(source)
  end
  if not isUsableCachedPlayer(source, player) then
    return nil, loadState or 'player_not_loaded'
  end

  local citizenid = trim(player.citizenid)
  local charinfo = type(player.charinfo) == 'table' and player.charinfo or {}
  local firstname = trim(charinfo.firstname)
  local lastname = trim(charinfo.lastname)

  -- ResolvePlayerIdentity is only a fallback for charinfo. The cached player
  -- remains authoritative for the citizenid used by the bank session.
  if firstname == '' and lastname == '' then
    local ok, identity = pcall(function()
      return exports['mz_core']:ResolvePlayerIdentity(source)
    end)
    if ok and type(identity) == 'table' and identity.ok == true
      and trim(identity.citizenid) == citizenid then
      firstname = trim(identity.firstname)
      lastname = trim(identity.lastname)
    end
  end

  local displayName = trim(('%s %s'):format(firstname, lastname))
  if displayName == '' then displayName = 'Cliente' end

  return {
    source = source,
    citizenid = citizenid,
    firstname = firstname,
    lastname = lastname,
    displayName = displayName,
    player = player
  }, loadState
end

function MZBankBridge.ResolvePlayerByCitizenId(citizenid)
  citizenid = trim(citizenid)
  if citizenid == '' or #citizenid > 32 then return nil, 'invalid_citizenid' end

  local ok, player = pcall(function()
    return exports['mz_core']:GetPlayerByCitizenId(citizenid)
  end)
  if not ok then
    print(('[mz_bank][bridge] mz_core export GetPlayerByCitizenId failed: %s'):format(tostring(player)))
    return nil, 'bank_unavailable'
  end
  if type(player) ~= 'table' or trim(player.citizenid) ~= citizenid then
    return nil, 'player_not_loaded'
  end

  local source = tonumber(player.source)
  if not source or source <= 0 then return nil, 'player_not_loaded' end
  local identity, identityError = MZBankBridge.ResolvePlayer(source, false)
  if not identity or identity.citizenid ~= citizenid then
    return nil, identityError or 'player_not_loaded'
  end
  return identity
end

function MZBankBridge.GetCitizenId(source)
  local identity = MZBankBridge.ResolvePlayer(source, false)
  return identity and identity.citizenid or nil
end

function MZBankBridge.GetDisplayName(source)
  local identity = MZBankBridge.ResolvePlayer(source, false)
  return identity and identity.displayName or 'Cliente'
end

function MZBankBridge.GetMoney(source, account)
  local money, err = coreExport('GetMoney', source)
  if type(money) ~= 'table' then return nil, err or 'bank_unavailable' end

  local normalized, normalizeErr = coreExport('NormalizeMoneyAccount', account)
  if not normalized then return nil, normalizeErr or 'bank_unavailable' end
  return math.floor(tonumber(money[normalized]) or 0)
end

function MZBankBridge.TransferBetweenOwnAccounts(source, fromAccount, toAccount, amount, metadata)
  local result, err = coreExport('TransferMoneyBetweenAccounts', source, fromAccount, toAccount, amount, metadata)
  if type(result) ~= 'table' then return { ok = false, error = err or 'transaction_failed' } end
  return result
end

function MZBankBridge.TransferBankBetweenPlayers(source, target, amount, metadata)
  local result, err = coreExport('TransferBankBetweenPlayers', source, target, amount, metadata)
  if type(result) ~= 'table' then return { ok = false, error = err or 'transaction_failed' } end
  return result
end

function MZBankBridge.GetPlayerInventory(source)
  source = tonumber(source)
  if not source or source <= 0 then return nil, 'invalid_source' end

  local callOk, ok, rowsOrErr = pcall(function()
    return exports['mz_core']:GetPlayerInventory(source)
  end)
  if not callOk then
    print(('[mz_bank][bridge] mz_core export GetPlayerInventory failed: %s'):format(tostring(ok)))
    return nil, 'inventory_unavailable'
  end
  if ok ~= true then
    print(('[mz_bank] inventory lookup rejected source=%s error=%s'):format(
      tostring(source),
      tostring(rowsOrErr or 'inventory_unavailable')
    ))
    return nil, rowsOrErr or 'inventory_unavailable'
  end
  return rowsOrErr or {}
end

function MZBankBridge.AddBankCard(source, metadata)
  source = tonumber(source)
  if not source or source <= 0 then return false, 'invalid_source' end

  local callOk, ok, resultOrErr = pcall(function()
    return exports['mz_core']:AddPlayerItem(source, Config.Card.ItemName, 1, metadata)
  end)
  if not callOk then
    print(('[mz_bank][bridge] mz_core export AddPlayerItem failed: %s'):format(tostring(ok)))
    return false, 'inventory_unavailable'
  end
  if ok ~= true then
    print(('[mz_bank] bank card delivery rejected source=%s error=%s'):format(
      tostring(source),
      tostring(resultOrErr or 'inventory_full')
    ))
    return false, resultOrErr or 'inventory_full'
  end
  return true, resultOrErr
end

function MZBankBridge.RemoveMoney(source, account, amount, metadata)
  local ok, err = coreExport('RemoveMoney', source, account, amount, metadata)
  return ok == true, err
end

function MZBankBridge.AddMoney(source, account, amount, metadata)
  local ok, err = coreExport('AddMoney', source, account, amount, metadata)
  return ok == true, err
end

function MZBankBridge.GetStatement(source, limit)
  if GetResourceState('mz_economy') ~= 'started' then
    return false, 'statement_unavailable'
  end

  local ok, result, detail = pcall(function()
    return exports['mz_economy']:GetAccountStatement(source, 'bank', limit)
  end)
  if not ok or result ~= true then
    return false, detail or 'statement_unavailable'
  end
  return true, result and detail or {}
end

function MZBankBridge.Notify(source, message, notifyType)
  TriggerClientEvent('mz_bank:client:notify', source, message, notifyType or 'info')
end

function MZBankBridge.Log(action, source, data)
  local player = MZBankBridge.GetPlayer(source)
  local citizenid = player and player.citizenid or 'unknown'
  local ok = pcall(function()
    exports['mz_core']:CreateDetailedLog('bank', action, {
      actor = { type = 'player', id = tostring(citizenid), source = source },
      target = { type = 'bank_channel', id = tostring(data and data.channel or 'unknown') },
      context = data or {},
      meta = { source_resource = 'mz_bank' }
    })
  end)
  if not ok and Config.Debug then
    print(('[mz_bank] log unavailable action=%s citizenid=%s'):format(tostring(action), tostring(citizenid)))
  end
end
