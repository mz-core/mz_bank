local RegisteredPoints = {}
local RegisteredAtms = {}

local function isCataloguedAtm(coords)
  if not coords then return false end
  local tolerance = tonumber(Config.ATM.catalogMatchDistance) or 2.25
  for _, knownCoords in ipairs(Config.ATM.catalog or {}) do
    if #(coords - knownCoords) <= tolerance then return true end
  end
  return false
end

local function interactionConfig()
  return type(Config.Interaction) == 'table' and Config.Interaction or {}
end

local function canUseMzInteract()
  return interactionConfig().UseMzInteract == true and GetResourceState('mz_interact') == 'started'
end

local function addPoint(data)
  if not canUseMzInteract() then return false end
  local ok, added, detail = pcall(function()
    return exports['mz_interact']:AddPoint(data)
  end)
  if not ok or added ~= true then
    if Config.Debug then
      print(('[mz_bank] mz_interact AddPoint failed id=%s error=%s'):format(
        tostring(data and data.id),
        tostring(detail or added)
      ))
    end
    return false
  end
  RegisteredPoints[data.id] = true
  return true
end

local function removePoint(id)
  if GetResourceState('mz_interact') == 'started' then
    pcall(function() exports['mz_interact']:RemovePoint(id) end)
  end
  RegisteredPoints[id] = nil
  RegisteredAtms[id] = nil
end

local function clearPoints()
  local ids = {}
  for id in pairs(RegisteredPoints) do ids[#ids + 1] = id end
  for _, id in ipairs(ids) do removePoint(id) end
  RegisteredPoints = {}
  RegisteredAtms = {}
end

local function pointEvent(channel, coords)
  return {
    type = 'client',
    name = 'mz_bank:client:openPoint',
    args = { channel, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0 }
  }
end

local function registerBranches()
  if not canUseMzInteract() then return end
  local interaction = interactionConfig()
  for index, branch in ipairs(Config.Branches or {}) do
    local coords = branch.coords
    if coords then
      local id = ('mz_bank:branch:%s'):format(index)
      addPoint({
        id = id,
        coords = coords,
        drawDistance = tonumber(branch.drawDistance or interaction.DrawDistance) or 18.0,
        interactDistance = tonumber(branch.radius or Config.InteractDistance) or 2.0,
        key = tonumber(Config.InteractKey) or 38,
        marker = type(branch.marker) == 'table' and branch.marker or interaction.Marker,
        text = type(branch.text) == 'table' and branch.text or interaction.Text,
        blip = type(branch.blip) == 'table' and branch.blip or interaction.BranchBlip,
        event = pointEvent('branch', coords)
      })
    end
  end
end

local function atmPointId(model, coords)
  return ('mz_bank:atm:%s:%.1f:%.1f:%.1f'):format(
    tostring(model),
    coords.x + 0.0,
    coords.y + 0.0,
    coords.z + 0.0
  )
end

local function registerAtm(model, entity)
  if not entity or entity == 0 or not DoesEntityExist(entity) then return end
  local coords = GetEntityCoords(entity)
  if not isCataloguedAtm(coords) then return end
  local id = atmPointId(model, coords)
  if RegisteredAtms[id] then
    RegisteredAtms[id].entity = entity
    return
  end

  local interaction = interactionConfig()
  local marker = Config.ATM.drawMarker == false and { enabled = false } or interaction.Marker
  local pointCoords = vector3(
    coords.x,
    coords.y,
    coords.z + (tonumber(Config.ATM.pointOffsetZ) or 1.0)
  )
  if addPoint({
    id = id,
    coords = pointCoords,
    drawDistance = tonumber(Config.ATM.drawDistance) or 12.0,
    interactDistance = tonumber(Config.InteractDistance) or 1.5,
    key = tonumber(Config.InteractKey) or 38,
    marker = marker,
    text = interaction.Text,
    blip = Config.ATM.blip,
    -- O ponto visual fica centralizado no ATM; a sessao continua usando as
    -- coordenadas reais do objeto.
    event = pointEvent('atm', coords)
  }) then
    RegisteredAtms[id] = { entity = entity, coords = coords }
  end
end

local function discoverAtms()
  local ped = PlayerPedId()
  local playerCoords = GetEntityCoords(ped)
  local radius = tonumber(Config.ATM.discoveryDistance) or 35.0

  for _, model in ipairs(Config.ATM.models or {}) do
    local entity = GetClosestObjectOfType(
      playerCoords.x, playerCoords.y, playerCoords.z,
      radius, model, false, false, false
    )
    registerAtm(model, entity)
  end

  local stale = {}
  for id, atm in pairs(RegisteredAtms) do
    if not atm.entity or atm.entity == 0 or not DoesEntityExist(atm.entity) then
      stale[#stale + 1] = id
    end
  end
  for _, id in ipairs(stale) do removePoint(id) end
end

local function refreshPoints()
  clearPoints()
  if not canUseMzInteract() then return end
  registerBranches()
  discoverAtms()
end

CreateThread(function()
  Wait(750)
  refreshPoints()
  while true do
    if canUseMzInteract() then discoverAtms() end
    Wait(math.max(500, tonumber(Config.ATM.discoveryIntervalMs) or 1500))
  end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
  if resourceName == 'mz_interact' or resourceName == GetCurrentResourceName() then
    Wait(500)
    refreshPoints()
  end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
  if resourceName == GetCurrentResourceName() then
    clearPoints()
  elseif resourceName == 'mz_interact' then
    RegisteredPoints = {}
    RegisteredAtms = {}
  end
end)
