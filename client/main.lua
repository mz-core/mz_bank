local isOpen = false
local currentPoint
local sessionToken
local sessionChannel
local sessionExpiresAt = 0
local closeBank
local atmAnimationActive = false
local atmAnimationPending = false
local ATM_SCENARIO = 'PROP_HUMAN_ATM'

local function usesMzInteract()
  return type(Config.Interaction) == 'table'
    and Config.Interaction.UseMzInteract == true
    and GetResourceState('mz_interact') == 'started'
end

local function notify(message, notifyType)
  local text = tostring(message or '')
  if text == '' then text = Config.Locale.transaction_failed end
  local normalizedType = tostring(notifyType or 'info')

  if GetResourceState('mz_notify') == 'started' then
    exports['mz_notify']:Notify({
      title = Config.BankName,
      message = text,
      type = normalizedType
    })
    return
  end
  if lib and type(lib.notify) == 'function' then
    lib.notify({
      title = Config.BankName,
      description = text,
      type = normalizedType
    })
    return
  end
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(text)
  EndTextCommandThefeedPostTicker(false, true)
end

local function findAtmEntity(point)
  if not point or point.channel ~= 'atm' then return 0 end
  if point.entity and point.entity ~= 0 and DoesEntityExist(point.entity) then
    return point.entity
  end

  local coords = point.coords
  if not coords then return 0 end
  for _, model in ipairs(Config.ATM.models or {}) do
    local object = GetClosestObjectOfType(coords.x, coords.y, coords.z, 1.75, model, false, false, false)
    if object ~= 0 and DoesEntityExist(object) then
      point.entity = object
      return object
    end
  end
  return 0
end

local function stopAtmAnimation()
  if not atmAnimationActive and not atmAnimationPending then return end
  atmAnimationActive = false
  atmAnimationPending = false
  local ped = PlayerPedId()
  if ped and ped ~= 0 then
    ClearPedTasks(ped)
  end
end

local function startAtmAnimation(point)
  if not point or point.channel ~= 'atm' then return end

  local ped = PlayerPedId()
  local entity = findAtmEntity(point)
  if entity ~= 0 then
    TaskTurnPedToFaceEntity(ped, entity, 450)
  elseif point.coords then
    TaskTurnPedToFaceCoord(ped, point.coords.x, point.coords.y, point.coords.z, 450)
  end

  atmAnimationPending = true
  CreateThread(function()
    Wait(450)
    atmAnimationPending = false
    if not isOpen or sessionChannel ~= 'atm' then return end
    TaskStartScenarioInPlace(ped, ATM_SCENARIO, 0, true)
    atmAnimationActive = true
  end)
end

local function serverCallback(name, ...)
  local ok, result = pcall(function(...)
    return lib.callback.await(name, false, ...)
  end, ...)
  if ok and type(result) == 'table' then
    if result.ok == true and sessionToken then
      sessionExpiresAt = GetGameTimer() + (Config.SessionTimeoutSeconds * 1000)
    end
    if result.error == 'invalid_session' or result.error == 'session_expired' or result.error == 'too_far' then
      closeBank(result.error)
    end
    return result
  end
  return { ok = false, error = 'bank_unavailable', message = Config.Locale.bank_unavailable }
end

closeBank = function(reason)
  if sessionToken then
    TriggerServerEvent('mz_bank:server:closeSession', sessionToken, reason or 'client_close')
  end
  sessionToken = nil
  sessionChannel = nil
  sessionExpiresAt = 0
  isOpen = false
  stopAtmAnimation()
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'close' })
end

local function openBank(point)
  if isOpen or not point then return end
  local ped = PlayerPedId()
  if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then return end

  local result = serverCallback('mz_bank:server:openSession', {
    channel = point.channel,
    coords = { x = point.coords.x, y = point.coords.y, z = point.coords.z }
  })
  if result.ok ~= true then
    notify(result.message or Config.Locale.bank_unavailable, 'error')
    return
  end

  sessionToken = result.data.token
  sessionChannel = result.data.channel
  sessionExpiresAt = GetGameTimer() + (Config.SessionTimeoutSeconds * 1000)

  local overview
  if result.data.authenticated == true then
    overview = serverCallback('mz_bank:server:authenticate', sessionToken)
    if overview.ok ~= true then
      notify(overview.message or Config.Locale.bank_unavailable, 'error')
      closeBank('initial_overview_failed')
      return
    end
  end

  isOpen = true
  startAtmAnimation(point)
  SetNuiFocus(true, true)
  SendNUIMessage({
    action = 'open',
    bankName = result.data.bankName or Config.BankName,
    currencySymbol = result.data.currencySymbol or Config.CurrencySymbol,
    channel = result.data.channel or point.channel,
    authenticated = result.data.authenticated == true,
    data = overview and overview.data or nil,
    issueMessage = result.data.issueMessage,
    issueOk = result.data.issueOk
  })
end

RegisterNetEvent('mz_bank:client:notify', function(message, notifyType)
  notify(message, notifyType)
end)

RegisterNetEvent('mz_bank:client:openPoint', function(channel, x, y, z)
  local coords = vector3(tonumber(x) or 0.0, tonumber(y) or 0.0, tonumber(z) or 0.0)
  if coords.x == 0.0 and coords.y == 0.0 and coords.z == 0.0 then return end
  local point = { channel = tostring(channel or ''), coords = coords }
  currentPoint = point
  openBank(point)
end)

RegisterNUICallback('close', function(_, cb)
  closeBank('nui_close')
  cb({ ok = true })
end)

RegisterNUICallback('authenticate', function(_, cb)
  cb(serverCallback('mz_bank:server:authenticate', sessionToken))
end)

RegisterNUICallback('refresh', function(_, cb)
  cb(serverCallback('mz_bank:server:overview', sessionToken, sessionChannel))
end)

RegisterNUICallback('withdraw', function(data, cb)
  cb(serverCallback('mz_bank:server:withdraw', sessionToken, data and data.amount))
end)

RegisterNUICallback('deposit', function(data, cb)
  cb(serverCallback('mz_bank:server:deposit', sessionToken, data and data.amount))
end)

RegisterNUICallback('transfer', function(data, cb)
  cb(serverCallback('mz_bank:server:transfer', sessionToken, {
    recipientType = 'server_id',
    recipientValue = data and (data.recipientValue or data.targetId),
    amount = data and data.amount,
    channel = sessionChannel
  }))
end)

local function closestBranch(position)
  for _, branch in ipairs(Config.Branches or {}) do
    local radius = tonumber(branch.radius) or Config.InteractDistance
    if #(position - branch.coords) <= radius then
      return { channel = 'branch', coords = branch.coords }
    end
  end
end

local function closestAtm(position)
  for _, model in ipairs(Config.ATM.models or {}) do
    local object = GetClosestObjectOfType(
      position.x, position.y, position.z,
      Config.InteractDistance + 0.5,
      model, false, false, false
    )
    if object ~= 0 and DoesEntityExist(object) then
      return { channel = 'atm', coords = GetEntityCoords(object), entity = object }
    end
  end
end

CreateThread(function()
  while true do
    local ped = PlayerPedId()
    local sleep = currentPoint and 500 or 1250

    if usesMzInteract() then
      sleep = 1000
    elseif not isOpen and not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped) then
      local position = GetEntityCoords(ped)
      currentPoint = closestBranch(position) or closestAtm(position)
    elseif not isOpen then
      currentPoint = nil
    end

    Wait(sleep)
  end
end)

CreateThread(function()
  while true do
    local sleep = 750
    local fallbackEnabled = type(Config.Interaction) ~= 'table' or Config.Interaction.FallbackMarkers ~= false
    if fallbackEnabled and not usesMzInteract() and currentPoint and not isOpen then
      sleep = 0
      if (currentPoint.channel == 'atm' and Config.ATM.drawMarker) or currentPoint.channel == 'branch' then
        DrawMarker(2, currentPoint.coords.x, currentPoint.coords.y, currentPoint.coords.z + 1.0,
          0.0, 0.0, 0.0, 0.0, 180.0, 0.0, 0.15, 0.15, 0.15,
          60, 130, 120, 200, false, true, 2, false)
      end
      BeginTextCommandDisplayHelp('STRING')
      AddTextComponentSubstringPlayerName('Pressione ~INPUT_CONTEXT~ para usar o ~b~atendimento bancario')
      EndTextCommandDisplayHelp(0, false, true, -1)
      if IsControlJustReleased(0, Config.InteractKey) then openBank(currentPoint) end
    end
    Wait(sleep)
  end
end)

CreateThread(function()
  while true do
    local sleep = 750
    if isOpen then
      sleep = 200
      local ped = PlayerPedId()
      local tooFar = not currentPoint or #(GetEntityCoords(ped) - currentPoint.coords) > Config.SessionDistance
      local expired = GetGameTimer() >= sessionExpiresAt
      if IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) or tooFar or expired then
        closeBank(expired and 'session_expired' or (IsEntityDead(ped) and 'player_dead' or 'too_far'))
      elseif sessionChannel == 'atm' and atmAnimationActive and not IsPedUsingScenario(ped, ATM_SCENARIO) then
        TaskStartScenarioInPlace(ped, ATM_SCENARIO, 0, true)
      end
    end
    Wait(sleep)
  end
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then return end
  stopAtmAnimation()
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'close' })
end)
